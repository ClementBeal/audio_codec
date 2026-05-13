part of 'flac_encoder.dart';

int _resolveFrameParallelism(int configuredParallelism) {
  if (configuredParallelism > 0) {
    return configuredParallelism;
  }

  final cpuCount = Platform.numberOfProcessors;
  if (cpuCount <= 1) {
    return 1;
  }

  // Keep one core for the main isolate.
  return cpuCount - 1;
}

Future<_FlacWorkerPool> _getOrCreateWorkerPool(
  FlacEncoder encoder,
  int workerCount,
) async {
  final existingPool = encoder._workerPool;
  if (existingPool != null && encoder._workerPoolSize == workerCount) {
    return existingPool;
  }

  if (existingPool != null) {
    await existingPool.close();
  }

  final newPool = await _FlacWorkerPool.spawn(workerCount);
  encoder._workerPool = newPool;
  encoder._workerPoolSize = workerCount;
  return newPool;
}

List<_TransferableFrameEncodeTask> _buildTransferableFrameTasks(
  List<_FrameEncodeTask> frameTasks,
) {
  return [
    for (final task in frameTasks)
      (
        config: task.config,
        frameNumber: task.frameNumber,
        channels: [
          for (final channel in task.channels)
            TransferableTypedData.fromList([channel]),
        ],
      ),
  ];
}

Uint8List _encodeFrameTask(_FrameEncodeTask task) {
  final encoder = FlacEncoder();
  encoder._activeConfig = task.config;
  try {
    return encoder._encode(task.channels, task.frameNumber);
  } finally {
    encoder._activeConfig = null;
  }
}

TransferableTypedData _encodeTransferableFrameTask(
  _TransferableFrameEncodeTask task,
) {
  final channels = <Samples>[
    for (final channel in task.channels) Int32List.view(channel.materialize()),
  ];

  final encoder = FlacEncoder();
  encoder._activeConfig = task.config;
  try {
    final encoded = encoder._encode(channels, task.frameNumber);
    return TransferableTypedData.fromList([encoded]);
  } finally {
    encoder._activeConfig = null;
  }
}

class _IndexedTransferableEncodedFrame {
  final int frameIndex;
  final TransferableTypedData bytes;

  const _IndexedTransferableEncodedFrame({
    required this.frameIndex,
    required this.bytes,
  });
}

const _workerMessageEncode = 0;
const _workerMessageClose = 1;
const _workerResponseOk = 0;
const _workerResponseError = 1;

void _flacEncodeWorkerMain(SendPort readyPort) {
  final commandPort = ReceivePort();
  readyPort.send(commandPort.sendPort);

  commandPort.listen((dynamic message) {
    if (message is! List || message.isEmpty) {
      return;
    }

    final messageType = message[0];
    if (messageType == _workerMessageEncode) {
      final frameIndex = message[1] as int;
      final task = message[2] as _TransferableFrameEncodeTask;
      final replyPort = message[3] as SendPort;
      try {
        final encoded = _encodeTransferableFrameTask(task);
        replyPort.send([
          _workerResponseOk,
          frameIndex,
          encoded,
        ]);
      } catch (error, stackTrace) {
        replyPort.send([
          _workerResponseError,
          frameIndex,
          error.toString(),
          stackTrace.toString(),
        ]);
      }
      return;
    }

    if (messageType == _workerMessageClose) {
      final replyPort = message[1] as SendPort;
      replyPort.send(true);
      commandPort.close();
    }
  });
}

class _FlacWorkerPool {
  final List<_FlacWorkerClient> _workers;
  int _nextWorkerIndex = 0;
  bool _closed = false;

  _FlacWorkerPool._(this._workers);

  static Future<_FlacWorkerPool> spawn(int workerCount) async {
    final workers = <_FlacWorkerClient>[];
    for (int i = 0; i < workerCount; i++) {
      workers.add(await _FlacWorkerClient.spawn(i));
    }
    return _FlacWorkerPool._(workers);
  }

  Future<List<_IndexedTransferableEncodedFrame>> encodeTasks(
    List<_TransferableFrameEncodeTask> tasks,
  ) async {
    if (_closed) {
      throw StateError('Flac worker pool is already closed.');
    }

    final futures = <Future<_IndexedTransferableEncodedFrame>>[];
    for (int i = 0; i < tasks.length; i++) {
      final worker = _workers[_nextWorkerIndex];
      _nextWorkerIndex = (_nextWorkerIndex + 1) % _workers.length;
      futures.add(worker.encodeFrame(i, tasks[i]));
    }

    return Future.wait(futures);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await Future.wait([
      for (final worker in _workers) worker.close(),
    ]);
  }
}

class _FlacWorkerClient {
  final Isolate _isolate;
  final SendPort _commandPort;
  bool _closed = false;

  _FlacWorkerClient._(this._isolate, this._commandPort);

  static Future<_FlacWorkerClient> spawn(int workerIndex) async {
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn<SendPort>(
      _flacEncodeWorkerMain,
      readyPort.sendPort,
      debugName: 'flac-encode-worker-$workerIndex',
    );
    final commandPort = await readyPort.first as SendPort;
    readyPort.close();
    return _FlacWorkerClient._(isolate, commandPort);
  }

  Future<_IndexedTransferableEncodedFrame> encodeFrame(
    int frameIndex,
    _TransferableFrameEncodeTask task,
  ) async {
    if (_closed) {
      throw StateError('Flac worker is already closed.');
    }

    final responsePort = ReceivePort();
    _commandPort.send([
      _workerMessageEncode,
      frameIndex,
      task,
      responsePort.sendPort,
    ]);

    final response = await responsePort.first as List<dynamic>;
    responsePort.close();

    final status = response[0];
    if (status == _workerResponseOk) {
      final rawSnapshot = response.length > 3
          ? response[3] as Map<dynamic, dynamic>
          : <dynamic, dynamic>{};
      final profilingSnapshot = <String, Map<String, int>>{};
      for (final entry in rawSnapshot.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) {
          continue;
        }
        final castedValue = <String, int>{};
        for (final valueEntry in value.entries) {
          if (valueEntry.key is String && valueEntry.value is int) {
            castedValue[valueEntry.key as String] = valueEntry.value as int;
          }
        }
        profilingSnapshot[key] = castedValue;
      }

      return _IndexedTransferableEncodedFrame(
        frameIndex: response[1] as int,
        bytes: response[2] as TransferableTypedData,
      );
    }

    final frame = response[1];
    final error = response.length > 2 ? response[2] : 'unknown error';
    final stack = response.length > 3 ? response[3] : '';
    throw StateError('Worker failed on frame $frame: $error\n$stack');
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    final ackPort = ReceivePort();
    _commandPort.send([_workerMessageClose, ackPort.sendPort]);
    await ackPort.first;
    ackPort.close();

    _isolate.kill(priority: Isolate.immediate);
  }
}

import 'dart:isolate';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/utils/bit_writer.dart';
import 'package:audio_codec/src/utils/crc/crc16.dart';
import 'package:audio_codec/src/utils/crc/crc8.dart';

class FlacEncoderConfig {
  final int frameBlockSize;
  final int sampleRate;
  final int bitsPerSample;
  final int maxFixedPredictorOrder;
  final int maxLpcOrder;
  final int lpcCoefficientPrecision;
  // 0 => auto (based on CPU count), 1 => sequential, >1 => fixed parallelism.
  final int frameParallelism;

  const FlacEncoderConfig({
    this.frameBlockSize = 4096,
    this.sampleRate = 44100,
    this.bitsPerSample = 16,
    this.maxFixedPredictorOrder = 4,
    this.maxLpcOrder = 8,
    this.lpcCoefficientPrecision = 12,
    this.frameParallelism = 0,
  }) : assert(frameParallelism >= 0, 'frameParallelism must be >= 0');
}

class FlacEncoder {
  // Mandatory FLAC stream signature: first 4 bytes of the file.
  static const _flacMagicWord = [0x66, 0x4C, 0x61, 0x43]; // "fLaC"

  // Fixed STREAMINFO payload length in FLAC (always 34 bytes).
  static const _streamInfoBlockLength = 34;

  // Frame header block-size code: read 16-bit (blocksize - 1) after coded number.
  static const _frameBlockSizeCode = 0x7;

  // Frame header sample-rate code for 44.1kHz.
  static const _frameSampleRateCode = 0x9;

  // Frame header bit-depth code for 16-bit samples.
  static const _frameBitDepthCode = 0x4;

  // Subframe header byte for constant samples (no wasted bits).
  static const _constantSubframeHeader = 0x00;

  // Subframe header byte for verbatim samples (no wasted bits).
  static const _verbatimSubframeHeader = 0x02;

  FlacEncoderConfig? _activeConfig;
  Int32List _residualScratch = Int32List(0);
  Int32List _foldedResidualScratch = Int32List(0);

  FlacEncoderConfig get _config {
    final config = _activeConfig;
    if (config == null) {
      throw StateError('Encoder config is not set.');
    }
    return config;
  }

  Uint8List encode(
    List<Samples> samples, {
    required FlacEncoderConfig config,
  }) {
    _activeConfig = config;
    try {
      final bytes = BytesBuilder(copy: false);
      bytes.add(_flacMagicWord);
      _writeStreamInfoBlock(bytes, samples);

      final frameTasks = _buildFrameTasks(
        samples,
        config,
        copyChannels: false,
      );

      for (final task in frameTasks) {
        bytes.add(_encode(task.channels, task.frameNumber));
      }

      return bytes.toBytes();
    } finally {
      _activeConfig = null;
    }
  }

  Future<Uint8List> encodeParallel(
    List<Samples> samples, {
    required FlacEncoderConfig config,
  }) async {
    _activeConfig = config;
    try {
      final bytes = BytesBuilder(copy: false);
      bytes.add(_flacMagicWord);
      _writeStreamInfoBlock(bytes, samples);

      final frameTasks = _buildFrameTasks(
        samples,
        config,
        copyChannels: false,
      );

      if (frameTasks.isEmpty) {
        return bytes.toBytes();
      }

      final parallelism = _resolveFrameParallelism(config.frameParallelism);
      if (parallelism <= 1 || frameTasks.length == 1) {
        for (final task in frameTasks) {
          bytes.add(_encodeFrameTask(task));
        }
      } else {
        final transferableTasks = _buildTransferableFrameTasks(frameTasks);
        final workerCount = math.min(parallelism, frameTasks.length);
        final indexedChunks = List.generate(
          workerCount,
          (_) => <_IndexedTransferableFrameEncodeTask>[],
          growable: false,
        );
        for (int i = 0; i < transferableTasks.length; i++) {
          indexedChunks[i % workerCount].add(
            _IndexedTransferableFrameEncodeTask(
              frameIndex: i,
              task: transferableTasks[i],
            ),
          );
        }

        final encodedChunkFutures = <Future<List<_IndexedTransferableEncodedFrame>>>[];
        for (int i = 0; i < workerCount; i++) {
          final chunk = indexedChunks[i];
          encodedChunkFutures.add(
            Isolate.run(
              () => _encodeTransferableFrameChunk(chunk),
              debugName: 'flac-encode-worker-$i',
            ),
          );
        }
        final encodedChunks = await Future.wait(encodedChunkFutures);

        final encodedFrames = List<Uint8List?>.filled(frameTasks.length, null);
        for (final chunk in encodedChunks) {
          for (final encoded in chunk) {
            encodedFrames[encoded.frameIndex] =
                encoded.bytes.materialize().asUint8List();
          }
        }

        for (int i = 0; i < frameTasks.length; i++) {
          final encodedFrame = encodedFrames[i];
          if (encodedFrame == null) {
            throw StateError('Missing encoded frame at index $i');
          }
          bytes.add(encodedFrame);
        }
      }

      return bytes.toBytes();
    } finally {
      _activeConfig = null;
    }
  }

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

  List<_FrameEncodeTask> _buildFrameTasks(
    List<Samples> samples,
    FlacEncoderConfig config, {
    required bool copyChannels,
  }) {
    final tasks = <_FrameEncodeTask>[];
    final totalSamples = samples.first.length;
    final frameBlockSize = config.frameBlockSize;

    int frameNumber = 0;
    for (int start = 0; start < totalSamples; start += frameBlockSize) {
      final endExclusive = (start + frameBlockSize < totalSamples)
          ? start + frameBlockSize
          : totalSamples;

      final frameChannels = <Samples>[
        for (final channel in samples)
          copyChannels
              ? Int32List.fromList(channel.sublist(start, endExclusive))
              : Int32List.sublistView(channel, start, endExclusive),
      ];

      tasks.add(
        _FrameEncodeTask(
          config: config,
          frameNumber: frameNumber,
          channels: frameChannels,
        ),
      );
      frameNumber++;
    }

    return tasks;
  }

  List<_TransferableFrameEncodeTask> _buildTransferableFrameTasks(
    List<_FrameEncodeTask> frameTasks,
  ) {
    return [
      for (final task in frameTasks)
        _TransferableFrameEncodeTask(
          config: task.config,
          frameNumber: task.frameNumber,
          channels: [
            for (final channel in task.channels)
              TransferableTypedData.fromList([channel]),
          ],
        ),
    ];
  }

  /// Writes the first FLAC metadata block (`STREAMINFO`).
  ///
  /// This block is mandatory and must appear right after the magic word.
  /// It provides core stream information (sample rate, channels,
  /// bits per sample, total samples) so the decoder can initialize
  /// decoding correctly.
  void _writeStreamInfoBlock(BytesBuilder bytes, List<Samples> samples) {
    // "last-metadata-block" bit:
    // 1 = this block is the last metadata block (minimal case for now).
    const isLastMetadataBlock = 1;

    // Metadata block type:
    // 0 = STREAMINFO according to the FLAC spec.
    const streamInfoMetadataType = 0;

    final streamInfoHeaderFirstByte =
        (isLastMetadataBlock << 7) | streamInfoMetadataType;

    // FLAC metadata header:
    // - 1 byte: isLast(1 bit) + type(7 bits)
    // - 3 bytes: payload length (here 34 => STREAMINFO)
    bytes.add([
      streamInfoHeaderFirstByte,
      0x00,
      0x00,
      _streamInfoBlockLength,
    ]);

    final streamInfo = Uint8List(_streamInfoBlockLength);
    final streamInfoView = ByteData.sublistView(streamInfo);

    // Target block size declared in STREAMINFO.
    streamInfoView.setUint16(
        0, _config.frameBlockSize, Endian.big); // min block size
    streamInfoView.setUint16(
        2, _config.frameBlockSize, Endian.big); // max block size

    // Sample rate declared in STREAMINFO.
    // FLAC stores "channels - 1" in a 3-bit field.
    final channelsMinusOne = samples.length - 1;

    // FLAC stores "bitsPerSample - 1" in a 5-bit field.
    final bitsPerSampleMinusOne = _config.bitsPerSample - 1;

    // Total number of inter-channel samples declared in the stream.
    final totalSamples = samples.first.length;

    // STREAMINFO 64-bit packed field:
    // [sampleRate:20][channels-1:3][bitsPerSample-1:5][totalSamples:36]
    final packed = (_config.sampleRate << 44) |
        (channelsMinusOne << 41) |
        (bitsPerSampleMinusOne << 36) |
        totalSamples;

    // Write the packed field into bytes 10..17 of the STREAMINFO payload.
    for (var i = 0; i < 8; i++) {
      streamInfo[10 + i] = (packed >> ((7 - i) * 8)) & 0xFF;
    }

    // Last 16 bytes (PCM MD5) are left as zero for now.
    bytes.add(streamInfo);
  }

  Uint8List _encode(List<Samples> samples, int frameNumber) {
    final frame = BytesBuilder(copy: false);
    final header = BytesBuilder(copy: false);

    final channels = samples.length;
    final blockSize = samples.first.length;

    // 0xFFF8:
    // sync code + reserved bit + fixed-blocksize strategy.
    header.add(const [0xFF, 0xF8]);

    // 4 bits block size code + 4 bits sample rate code.
    header.addByte((_frameBlockSizeCode << 4) | _frameSampleRateCode);

    // 4 bits channel assignment + 3 bits bit depth code + reserved bit.
    header.addByte(((channels - 1) << 4) | (_frameBitDepthCode << 1));

    // In fixed-blocksize mode, this coded number is the frame number.
    header.add(_encodeFrameNumber(frameNumber));

    // Because we use block-size code 0x7, we append blockSize - 1 on 16 bits.
    final encodedBlockSize = blockSize - 1;
    header.addByte((encodedBlockSize >> 8) & 0xFF);
    header.addByte(encodedBlockSize & 0xFF);

    final headerBytes = header.toBytes();
    final headerCrc = calculateCRC8(headerBytes);

    frame.add(headerBytes);
    frame.addByte(headerCrc);

    final subframeWriter = BitWriter(frame);

    // One subframe per channel:
    // - constant if all samples in the channel chunk are identical
    // - fixed predictor + Rice residuals if profitable
    // - verbatim otherwise
    for (final channel in samples) {
      if (_isConstantChannel(channel)) {
        _writeConstantSubframe(subframeWriter, channel.first);
      } else {
        final fixedDecision = _chooseFixedPredictor(channel);
        final lpcDecision = _chooseLpcPredictor(channel);

        if (fixedDecision != null &&
            (lpcDecision == null ||
                fixedDecision.estimatedBits <= lpcDecision.estimatedBits)) {
          _writeFixedSubframe(subframeWriter, channel, fixedDecision);
        } else if (lpcDecision != null) {
          _writeLpcSubframe(subframeWriter, channel, lpcDecision);
        } else {
          _writeVerbatimSubframe(subframeWriter, channel);
        }
      }
    }

    // Frame CRC16 must be byte-aligned.
    subframeWriter.alignToByte();

    final frameBytesWithoutCrc16 = frame.toBytes();
    final frameCrc16 = calculateCRC16(frameBytesWithoutCrc16);
    frame.addByte((frameCrc16 >> 8) & 0xFF);
    frame.addByte(frameCrc16 & 0xFF);

    return frame.toBytes();
  }

  bool _isConstantChannel(Samples channel) {
    if (channel.isEmpty) {
      return true;
    }

    final reference = channel.first;
    for (int i = 1; i < channel.length; i++) {
      if (channel[i] != reference) {
        return false;
      }
    }

    return true;
  }

  _FixedPredictorDecision? _chooseFixedPredictor(Samples channel) {
    final verbatimBits = 8 + channel.length * _config.bitsPerSample;
    _FixedPredictorDecision? best;
    _ensureResidualScratchCapacity(channel.length);

    final maxOrder = channel.length > _config.maxFixedPredictorOrder
        ? _config.maxFixedPredictorOrder
        : channel.length;

    for (int order = 0; order <= maxOrder; order++) {
      final residualLength =
          _computeFixedResidualsInto(channel, order, _residualScratch);
      _foldResidualsInto(
        _residualScratch,
        residualLength,
        _foldedResidualScratch,
      );
      final riceParameter =
          _chooseRiceParameter(_foldedResidualScratch, residualLength);
      final estimatedBits =
          _estimateFixedSubframeBitCount(order, residualLength, riceParameter);

      if (estimatedBits >= verbatimBits) {
        continue;
      }

      if (best == null || estimatedBits < best.estimatedBits) {
        best = _FixedPredictorDecision(
          order: order,
          riceParameter: riceParameter,
          residuals: _copyInt32Prefix(_residualScratch, residualLength),
          estimatedBits: estimatedBits,
        );
      }
    }

    return best;
  }

  _LpcPredictorDecision? _chooseLpcPredictor(Samples channel) {
    final verbatimBits = 8 + channel.length * _config.bitsPerSample;
    _LpcPredictorDecision? best;

    final maxOrder = channel.length - 1 < _config.maxLpcOrder
        ? channel.length - 1
        : _config.maxLpcOrder;
    if (maxOrder < 1) {
      return null;
    }
    _ensureResidualScratchCapacity(channel.length);

    final autocorrelation = _computeAutocorrelation(channel, maxOrder);
    if (autocorrelation == null) {
      return null;
    }

    final a = List<double>.filled(maxOrder + 1, 0.0, growable: false);
    double error = autocorrelation[0];
    const epsilon = 1e-12;

    for (int order = 1; order <= maxOrder; order++) {
      if (error.abs() < epsilon) {
        break;
      }

      double lambda = autocorrelation[order];
      for (int j = 1; j < order; j++) {
        lambda -= a[j] * autocorrelation[order - j];
      }

      lambda /= error;

      final previous = List<double>.from(a, growable: false);
      a[order] = lambda;
      for (int j = 1; j < order; j++) {
        a[j] = previous[j] - lambda * previous[order - j];
      }

      error *= (1.0 - lambda * lambda);
      if (!error.isFinite || error <= epsilon) {
        break;
      }

      final floating = [for (int i = 1; i <= order; i++) a[i]];
      final quantized = _quantizeLpcCoefficients(
        floating,
        _config.lpcCoefficientPrecision,
      );
      if (quantized == null) {
        continue;
      }

      final residualLength =
          _computeLpcResidualsInto(channel, quantized, order, _residualScratch);
      _foldResidualsInto(
        _residualScratch,
        residualLength,
        _foldedResidualScratch,
      );
      final riceParameter =
          _chooseRiceParameter(_foldedResidualScratch, residualLength);
      final estimatedBits = _estimateLpcSubframeBitCount(
        order,
        residualLength,
        riceParameter,
        quantized.precision,
      );

      if (estimatedBits >= verbatimBits) {
        continue;
      }

      if (best == null || estimatedBits < best.estimatedBits) {
        best = _LpcPredictorDecision(
          order: order,
          riceParameter: riceParameter,
          residuals: _copyInt32Prefix(_residualScratch, residualLength),
          estimatedBits: estimatedBits,
          qlpPrecision: quantized.precision,
          shift: quantized.shift,
          coefficients: quantized.coefficients,
        );
      }
    }

    return best;
  }

  int _computeFixedResidualsInto(
    Samples channel,
    int order,
    Int32List outResiduals,
  ) {
    int outIndex = 0;
    for (int i = order; i < channel.length; i++) {
      final sample = channel[i];
      int prediction;

      switch (order) {
        case 0:
          prediction = 0;
          break;
        case 1:
          prediction = channel[i - 1];
          break;
        case 2:
          prediction = 2 * channel[i - 1] - channel[i - 2];
          break;
        case 3:
          prediction = 3 * channel[i - 1] - 3 * channel[i - 2] + channel[i - 3];
          break;
        case 4:
          prediction = 4 * channel[i - 1] -
              6 * channel[i - 2] +
              4 * channel[i - 3] -
              channel[i - 4];
          break;
        default:
          throw ArgumentError.value(order, 'order', 'unsupported fixed order');
      }

      outResiduals[outIndex++] = sample - prediction;
    }

    return outIndex;
  }

  int _chooseRiceParameter(Int32List foldedResiduals, int length) {
    if (length == 0) {
      return 0;
    }

    int sumAbs = 0;
    for (int i = 0; i < length; i++) {
      sumAbs += (foldedResiduals[i] + 1) >> 1;
    }

    final meanAbs = sumAbs / length;
    final estimated = meanAbs <= 0
        ? 0
        : (math.log(meanAbs * math.ln2) / math.ln2).round().clamp(0, 14);

    final candidateMin = estimated > 0 ? estimated - 1 : 0;
    final candidateMax = estimated < 14 ? estimated + 1 : 14;

    int bestParameter = estimated;
    int bestBits =
        _estimateRiceBitsForParameter(foldedResiduals, length, estimated);

    for (int parameter = candidateMin; parameter <= candidateMax; parameter++) {
      if (parameter == estimated) {
        continue;
      }

      final bits =
          _estimateRiceBitsForParameter(foldedResiduals, length, parameter);
      if (bits < bestBits) {
        bestBits = bits;
        bestParameter = parameter;
      }
    }

    return bestParameter;
  }

  int _estimateRiceBitsForParameter(
    Int32List foldedResiduals,
    int length,
    int parameter,
  ) {
    int bits = 0;
    for (int i = 0; i < length; i++) {
      final quotient = foldedResiduals[i] >> parameter;
      bits += quotient + 1 + parameter;
    }
    return bits;
  }

  int _estimateFixedSubframeBitCount(
    int order,
    int residualLength,
    int riceParameter,
  ) {
    // Subframe header + warm-up samples + residual header.
    int bits = 8 + (order * _config.bitsPerSample) + 10;

    for (int i = 0; i < residualLength; i++) {
      final quotient = _foldedResidualScratch[i] >> riceParameter;
      bits += quotient + 1 + riceParameter;
    }

    return bits;
  }

  int _estimateLpcSubframeBitCount(
    int order,
    int residualLength,
    int riceParameter,
    int qlpPrecision,
  ) {
    // Subframe header + warm-up samples + LPC params + residual header.
    int bits = 8 +
        (order * _config.bitsPerSample) +
        4 +
        5 +
        (order * qlpPrecision) +
        10;

    for (int i = 0; i < residualLength; i++) {
      final quotient = _foldedResidualScratch[i] >> riceParameter;
      bits += quotient + 1 + riceParameter;
    }

    return bits;
  }

  int _fixedSubframeHeaderForOrder(int order) {
    final subframeType = 8 + order;
    return subframeType << 1;
  }

  int _lpcSubframeHeaderForOrder(int order) {
    final subframeType = 31 + order;
    return subframeType << 1;
  }

  /// Writes a FLAC `constant` subframe for one channel.
  ///
  /// Layout:
  /// - 1 byte subframe header (`_constantSubframeHeader`)
  /// - 1 signed sample value, reused for the whole block
  ///
  /// With the current 16-bit encoder configuration, this value is written
  /// on 2 bytes in big-endian order.
  void _writeConstantSubframe(BitWriter writer, int sampleValue) {
    writer.writeBits(_constantSubframeHeader, 8);
    writer.writeSigned(sampleValue, _config.bitsPerSample);
  }

  /// Writes a FLAC `fixed predictor` subframe.
  ///
  /// The layout is:
  /// - fixed subframe header (order 0..4)
  /// - warm-up samples (`order` values)
  /// - residual coded with partitioned Rice method 0 and partition order 0
  void _writeFixedSubframe(
    BitWriter writer,
    Samples channel,
    _FixedPredictorDecision decision,
  ) {
    writer.writeBits(_fixedSubframeHeaderForOrder(decision.order), 8);

    for (int i = 0; i < decision.order; i++) {
      writer.writeSigned(channel[i], _config.bitsPerSample);
    }

    _writeRiceResiduals(writer, decision.residuals, decision.riceParameter);
  }

  void _writeLpcSubframe(
    BitWriter writer,
    Samples channel,
    _LpcPredictorDecision decision,
  ) {
    writer.writeBits(_lpcSubframeHeaderForOrder(decision.order), 8);

    for (int i = 0; i < decision.order; i++) {
      writer.writeSigned(channel[i], _config.bitsPerSample);
    }

    writer.writeBits(decision.qlpPrecision - 1, 4);
    writer.writeSigned(decision.shift, 5);

    for (final coefficient in decision.coefficients) {
      writer.writeSigned(coefficient, decision.qlpPrecision);
    }

    _writeRiceResiduals(writer, decision.residuals, decision.riceParameter);
  }

  void _writeRiceResiduals(
    BitWriter writer,
    Int32List residuals,
    int riceParameter,
  ) {
    // Residual header:
    // - method 0 => 4-bit Rice parameter
    // - partition order 0 => single partition
    writer.writeBits(0, 2);
    writer.writeBits(0, 4);
    writer.writeBits(riceParameter, 4);

    for (int i = 0; i < residuals.length; i++) {
      final folded = _foldResidual(residuals[i]);
      final quotient = folded >> riceParameter;
      final remainderMask = (1 << riceParameter) - 1;
      final remainder = folded & remainderMask;

      writer.writeUnaryZeroCount(quotient);
      if (riceParameter > 0) {
        writer.writeBits(remainder, riceParameter);
      }
    }
  }

  int _foldResidual(int residual) {
    return residual >= 0 ? (residual << 1) : ((-residual << 1) - 1);
  }

  void _foldResidualsInto(
    Int32List residuals,
    int length,
    Int32List outFoldedResiduals,
  ) {
    for (int i = 0; i < length; i++) {
      outFoldedResiduals[i] = _foldResidual(residuals[i]);
    }
  }

  List<double>? _computeAutocorrelation(Samples channel, int maxOrder) {
    final r = List<double>.filled(maxOrder + 1, 0.0, growable: false);
    for (int lag = 0; lag <= maxOrder; lag++) {
      double sum = 0.0;
      for (int i = lag; i < channel.length; i++) {
        sum += channel[i] * channel[i - lag];
      }
      r[lag] = sum;
    }

    if (r[0] == 0.0 || !r[0].isFinite) {
      return null;
    }

    return r;
  }

  _QuantizedLpc? _quantizeLpcCoefficients(
    List<double> coefficients,
    int precision,
  ) {
    final maxAbs = coefficients.fold<double>(
      0.0,
      (current, value) => math.max(current, value.abs()),
    );

    if (maxAbs == 0.0 || !maxAbs.isFinite) {
      return null;
    }

    final qMax = (1 << (precision - 1)) - 1;
    final qMin = -(1 << (precision - 1));

    final shiftFromMax = (math.log(qMax / maxAbs) / math.ln2).floor();
    final shift = shiftFromMax.clamp(0, 15);
    final scale = math.pow(2.0, shift).toDouble();

    final qlp = <int>[];
    bool hasNonZero = false;
    for (final coefficient in coefficients) {
      int quantized = (coefficient * scale).round();
      if (quantized > qMax) {
        quantized = qMax;
      } else if (quantized < qMin) {
        quantized = qMin;
      }
      if (quantized != 0) {
        hasNonZero = true;
      }
      qlp.add(quantized);
    }

    if (!hasNonZero) {
      return null;
    }

    return _QuantizedLpc(
      precision: precision,
      shift: shift,
      coefficients: qlp,
    );
  }

  int _computeLpcResidualsInto(
    Samples channel,
    _QuantizedLpc quantized,
    int order,
    Int32List outResiduals,
  ) {
    int outIndex = 0;
    for (int i = order; i < channel.length; i++) {
      int prediction = 0;
      for (int j = 0; j < order; j++) {
        prediction += quantized.coefficients[j] * channel[i - 1 - j];
      }
      prediction >>= quantized.shift;
      outResiduals[outIndex++] = channel[i] - prediction;
    }

    return outIndex;
  }

  void _ensureResidualScratchCapacity(int minLength) {
    if (_residualScratch.length < minLength) {
      _residualScratch = Int32List(minLength);
    }
    if (_foldedResidualScratch.length < minLength) {
      _foldedResidualScratch = Int32List(minLength);
    }
  }

  Int32List _copyInt32Prefix(Int32List source, int length) {
    final copy = Int32List(length);
    copy.setRange(0, length, source);
    return copy;
  }

  /// Writes a FLAC `verbatim` subframe for one channel.
  ///
  /// Layout:
  /// - 1 byte subframe header (`_verbatimSubframeHeader`)
  /// - all channel samples written directly, without prediction/residual coding
  ///
  /// Each sample is currently encoded as signed 16-bit big-endian.
  void _writeVerbatimSubframe(BitWriter writer, Samples channel) {
    writer.writeBits(_verbatimSubframeHeader, 8);

    // Write each sample as signed big-endian 16-bit.
    for (final sample in channel) {
      writer.writeSigned(sample, _config.bitsPerSample);
    }
  }

  /// Encodes the frame index for the FLAC frame header.
  ///
  /// In fixed-blocksize mode, FLAC stores a "coded number" after the
  /// 4-byte header fields. Here, that coded number is the frame number.
  ///
  /// FLAC uses a UTF-8-like variable-length binary layout:
  /// - small values use 1 byte
  /// - larger values use multiple bytes
  ///
  /// Examples:
  /// - frameNumber 0   -> [0x00]
  /// - frameNumber 127 -> [0x7F]
  /// - frameNumber 128 -> [0xC2, 0x80]
  List<int> _encodeFrameNumber(int frameNumber) {
    // Fast path: values < 128 fit in one byte.
    if (frameNumber < 0x80) {
      return [frameNumber];
    }

    // Decide how many continuation bytes we need.
    // Each continuation byte stores 6 payload bits.
    int continuationBytes;
    if (frameNumber < (1 << 11)) {
      continuationBytes = 1;
    } else if (frameNumber < (1 << 16)) {
      continuationBytes = 2;
    } else if (frameNumber < (1 << 21)) {
      continuationBytes = 3;
    } else if (frameNumber < (1 << 26)) {
      continuationBytes = 4;
    } else if (frameNumber < (1 << 31)) {
      continuationBytes = 5;
    } else {
      throw ArgumentError.value(
        frameNumber,
        'frameNumber',
        'coded number too large',
      );
    }

    // Total output size = first byte + continuation bytes.
    final bytes = List<int>.filled(continuationBytes + 1, 0);
    int remaining = frameNumber;

    // Fill continuation bytes from right to left.
    // Format is 10xxxxxx, where xxxxxx are payload bits.
    for (int i = continuationBytes; i >= 1; i--) {
      bytes[i] = 0x80 | (remaining & 0x3F);
      remaining >>= 6;
    }

    // Prefix in the first byte indicates total length:
    // 110xxxxx, 1110xxxx, 11110xxx, 111110xx, 1111110x.
    const leadingPrefix = [0x00, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC];
    final firstPayloadBits = 6 - continuationBytes;
    final firstPayloadMask = (1 << firstPayloadBits) - 1;
    bytes[0] =
        leadingPrefix[continuationBytes] | (remaining & firstPayloadMask);

    return bytes;
  }
}

class _FixedPredictorDecision {
  final int order;
  final int riceParameter;
  final Int32List residuals;
  final int estimatedBits;

  const _FixedPredictorDecision({
    required this.order,
    required this.riceParameter,
    required this.residuals,
    required this.estimatedBits,
  });
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

List<_IndexedTransferableEncodedFrame> _encodeTransferableFrameChunk(
  List<_IndexedTransferableFrameEncodeTask> chunk,
) {
  return [
    for (final indexedTask in chunk)
      _IndexedTransferableEncodedFrame(
        frameIndex: indexedTask.frameIndex,
        bytes: _encodeTransferableFrameTask(indexedTask.task),
      ),
  ];
}

TransferableTypedData _encodeTransferableFrameTask(
  _TransferableFrameEncodeTask task,
) {
  final channels = <Samples>[
    for (final channel in task.channels)
      Int32List.view(channel.materialize()),
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

class _IndexedTransferableFrameEncodeTask {
  final int frameIndex;
  final _TransferableFrameEncodeTask task;

  const _IndexedTransferableFrameEncodeTask({
    required this.frameIndex,
    required this.task,
  });
}

class _IndexedTransferableEncodedFrame {
  final int frameIndex;
  final TransferableTypedData bytes;

  const _IndexedTransferableEncodedFrame({
    required this.frameIndex,
    required this.bytes,
  });
}

class _FrameEncodeTask {
  final FlacEncoderConfig config;
  final int frameNumber;
  final List<Samples> channels;

  const _FrameEncodeTask({
    required this.config,
    required this.frameNumber,
    required this.channels,
  });
}

class _TransferableFrameEncodeTask {
  final FlacEncoderConfig config;
  final int frameNumber;
  final List<TransferableTypedData> channels;

  const _TransferableFrameEncodeTask({
    required this.config,
    required this.frameNumber,
    required this.channels,
  });
}

class _LpcPredictorDecision {
  final int order;
  final int riceParameter;
  final Int32List residuals;
  final int estimatedBits;
  final int qlpPrecision;
  final int shift;
  final List<int> coefficients;

  const _LpcPredictorDecision({
    required this.order,
    required this.riceParameter,
    required this.residuals,
    required this.estimatedBits,
    required this.qlpPrecision,
    required this.shift,
    required this.coefficients,
  });
}

class _QuantizedLpc {
  final int precision;
  final int shift;
  final List<int> coefficients;

  const _QuantizedLpc({
    required this.precision,
    required this.shift,
    required this.coefficients,
  });
}

// Protocol section: Native FLAC stream (RFC 9639)
// Bytes: file-level layout
// Layout:
// AAAAAAAA BBBBBBBB CCCCCCCC DDDDDDDD
// Meaning:
// - A..D: ASCII "fLaC" stream marker.
// - Then one or more metadata blocks, starting with mandatory STREAMINFO.
// - Then a sequence of audio frames.
//
// Protocol section: Metadata block header
// Bytes: per metadata block, 0..3
// Layout:
// ABBBBBBB CCCCCCCC DDDDDDDD EEEEEEEE
// Meaning:
// - A: is_last_metadata_block, 1 bit.
// - B: block type, 7 bits (STREAMINFO = 0).
// - C..E: metadata payload length, 24-bit big-endian.
// Constraints:
// - STREAMINFO payload length is exactly 34 bytes.
//
// Protocol section: Frame header prefix and checksums
// Bytes: per frame, header then subframes then footer
// Layout:
// 11111111 11111RSB AAAABBBB CCCCDDDR [coded_number...] [extras...] HHHHHHHH
// Meaning:
// - R: reserved bit, must be 0.
// - S: blocking strategy (0 fixed-blocksize, 1 variable-blocksize).
// - B: block-size code, 4 bits.
// - A: sample-rate code, 4 bits.
// - C: channel assignment, 4 bits.
// - D: bits-per-sample code, 3 bits.
// - Final R: reserved bit, must be 0.
// - H: CRC-8 over frame header bytes before CRC-8 itself.
// Constraints:
// - Channel assignment must match FLAC 1..8 channel semantics.
// - Frame payload ends on a byte boundary, then CRC-16 is appended.
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/utils/bit_writer.dart';
import 'package:audio_codec/src/utils/crc/crc16.dart';
import 'package:audio_codec/src/utils/crc/crc8.dart';
import 'package:crypto/crypto.dart';

part 'flac_encoder_parallel.dart';

class FlacEncoderConfig {
  final int frameBlockSize;
  final int sampleRate;
  final int bitsPerSample;
  final int maxFixedPredictorOrder;
  final int maxLpcOrder;
  final int lpcCoefficientPrecision;
  // If fixed prediction already saves this fraction over verbatim, LPC search
  // is skipped for that subframe. LPC can still be forced by setting this to 1.
  final double lpcSearchFixedPredictorSkipGain;
  // 0 => auto (based on CPU count), 1 => sequential, >1 => fixed parallelism.
  final int frameParallelism;

  const FlacEncoderConfig({
    this.frameBlockSize = 4096,
    this.sampleRate = 44100,
    this.bitsPerSample = 16,
    this.maxFixedPredictorOrder = 4,
    this.maxLpcOrder = 8,
    this.lpcCoefficientPrecision = 12,
    this.lpcSearchFixedPredictorSkipGain = 0.25,
    this.frameParallelism = 0,
  })  : assert(frameParallelism >= 0, 'frameParallelism must be >= 0'),
        assert(frameBlockSize > 0, 'frameBlockSize must be > 0'),
        assert(frameBlockSize <= 0xFFFF, 'frameBlockSize must be <= 65535'),
        assert(sampleRate > 0, 'sampleRate must be > 0'),
        assert(sampleRate <= 0xFFFFF, 'sampleRate must be <= 1048575'),
        assert(bitsPerSample >= 4, 'bitsPerSample must be >= 4'),
        assert(bitsPerSample <= 32, 'bitsPerSample must be <= 32'),
        assert(
            maxFixedPredictorOrder >= 0, 'maxFixedPredictorOrder must be >= 0'),
        assert(
            maxFixedPredictorOrder <= 4, 'maxFixedPredictorOrder must be <= 4'),
        assert(maxLpcOrder >= 0, 'maxLpcOrder must be >= 0'),
        assert(maxLpcOrder <= 32, 'maxLpcOrder must be <= 32'),
        assert(lpcCoefficientPrecision >= 1,
            'lpcCoefficientPrecision must be >= 1'),
        assert(lpcCoefficientPrecision <= 15,
            'lpcCoefficientPrecision must be <= 15'),
        assert(lpcSearchFixedPredictorSkipGain >= 0,
            'lpcSearchFixedPredictorSkipGain must be >= 0'),
        assert(lpcSearchFixedPredictorSkipGain <= 1,
            'lpcSearchFixedPredictorSkipGain must be <= 1');
}

class FlacEncoder {
  // Mandatory FLAC stream signature: first 4 bytes of the file.
  static const _flacMagicWord = [0x66, 0x4C, 0x61, 0x43]; // "fLaC"

  // Fixed STREAMINFO payload length in FLAC (always 34 bytes).
  static const _streamInfoBlockLength = 34;

  // Frame header block-size code: read 16-bit (blocksize - 1) after coded number.
  static const _frameBlockSizeCode = 0x7;

  // Subframe header byte for constant samples (no wasted bits).
  static const _constantSubframeHeader = 0x00;

  // Subframe header byte for verbatim samples (no wasted bits).
  static const _verbatimSubframeHeader = 0x02;

  static const _minFlacChannels = 1;
  static const _maxFlacChannels = 8;
  static const _minFlacBitsPerSample = 4;
  static const _maxFlacBitsPerSample = 32;
  static const _minFlacSampleRate = 1;
  static const _maxFlacSampleRate = 0xFFFFF;
  static const _maxFlacBlockSize = 0xFFFF;
  static const _maxFlacFixedPredictorOrder = 4;
  static const _maxFlacLpcOrder = 32;
  static const _minFlacQlpPrecision = 1;
  static const _maxFlacQlpPrecision = 15;
  static const _maxFlacTotalSamples = 0xFFFFFFFFF; // 36-bit STREAMINFO field.

  FlacEncoderConfig? _activeConfig;
  Int32List _residualScratch = Int32List(0);
  Int32List _foldedResidualScratch = Int32List(0);
  _FlacWorkerPool? _workerPool;
  int _workerPoolSize = 0;

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
    _validateEncoderInput(samples, config);
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
    _validateEncoderInput(samples, config);
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
        final workerPool = await _getOrCreateWorkerPool(this, parallelism);
        final encodedChunks = await workerPool.encodeTasks(transferableTasks);

        final encodedFrames = List<Uint8List?>.filled(frameTasks.length, null);
        for (final encoded in encodedChunks) {
          encodedFrames[encoded.frameIndex] =
              encoded.bytes.materialize().asUint8List();
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

  Future<void> close() async {
    final workerPool = _workerPool;
    _workerPool = null;
    _workerPoolSize = 0;
    if (workerPool != null) {
      await workerPool.close();
    }
  }

  void _validateEncoderInput(List<Samples> samples, FlacEncoderConfig config) {
    _validateConfig(config);
    _validateSampleMatrix(samples, config.bitsPerSample);
  }

  void _validateConfig(FlacEncoderConfig config) {
    if (config.frameParallelism < 0) {
      throw RangeError.value(
        config.frameParallelism,
        'frameParallelism',
        'must be >= 0',
      );
    }
    if (config.frameBlockSize < 1 ||
        config.frameBlockSize > _maxFlacBlockSize) {
      throw RangeError.value(
        config.frameBlockSize,
        'frameBlockSize',
        'must be in [1, $_maxFlacBlockSize]',
      );
    }
    if (config.sampleRate < _minFlacSampleRate ||
        config.sampleRate > _maxFlacSampleRate) {
      throw RangeError.value(
        config.sampleRate,
        'sampleRate',
        'must be in [$_minFlacSampleRate, $_maxFlacSampleRate]',
      );
    }
    if (config.bitsPerSample < _minFlacBitsPerSample ||
        config.bitsPerSample > _maxFlacBitsPerSample) {
      throw RangeError.value(
        config.bitsPerSample,
        'bitsPerSample',
        'must be in [$_minFlacBitsPerSample, $_maxFlacBitsPerSample]',
      );
    }
    if (config.maxFixedPredictorOrder < 0 ||
        config.maxFixedPredictorOrder > _maxFlacFixedPredictorOrder) {
      throw RangeError.value(
        config.maxFixedPredictorOrder,
        'maxFixedPredictorOrder',
        'must be in [0, $_maxFlacFixedPredictorOrder]',
      );
    }
    if (config.maxLpcOrder < 0 || config.maxLpcOrder > _maxFlacLpcOrder) {
      throw RangeError.value(
        config.maxLpcOrder,
        'maxLpcOrder',
        'must be in [0, $_maxFlacLpcOrder]',
      );
    }
    if (config.lpcCoefficientPrecision < _minFlacQlpPrecision ||
        config.lpcCoefficientPrecision > _maxFlacQlpPrecision) {
      throw RangeError.value(
        config.lpcCoefficientPrecision,
        'lpcCoefficientPrecision',
        'must be in [$_minFlacQlpPrecision, $_maxFlacQlpPrecision]',
      );
    }
    if (config.lpcSearchFixedPredictorSkipGain < 0 ||
        config.lpcSearchFixedPredictorSkipGain > 1) {
      throw RangeError.value(
        config.lpcSearchFixedPredictorSkipGain,
        'lpcSearchFixedPredictorSkipGain',
        'must be in [0, 1]',
      );
    }
  }

  void _validateSampleMatrix(List<Samples> samples, int bitsPerSample) {
    if (samples.length < _minFlacChannels ||
        samples.length > _maxFlacChannels) {
      throw RangeError.value(
        samples.length,
        'samples.length',
        'must be in [$_minFlacChannels, $_maxFlacChannels]',
      );
    }

    final totalSamples = samples.first.length;
    if (totalSamples > _maxFlacTotalSamples) {
      throw RangeError.value(
        totalSamples,
        'samples.first.length',
        'must be <= $_maxFlacTotalSamples (36-bit STREAMINFO limit)',
      );
    }

    final minSampleValue = -(1 << (bitsPerSample - 1));
    final maxSampleValue = (1 << (bitsPerSample - 1)) - 1;

    for (int channelIndex = 0; channelIndex < samples.length; channelIndex++) {
      final channel = samples[channelIndex];
      if (channel.length != totalSamples) {
        throw ArgumentError(
          'All channels must have the same sample count. '
          'Channel 0 has $totalSamples samples, '
          'channel $channelIndex has ${channel.length}.',
        );
      }
      for (int sampleIndex = 0; sampleIndex < channel.length; sampleIndex++) {
        final sample = channel[sampleIndex];
        if (sample < minSampleValue || sample > maxSampleValue) {
          throw RangeError(
            'Sample out of range for $bitsPerSample-bit FLAC: '
            'channel $channelIndex sample $sampleIndex = $sample '
            'not in [$minSampleValue, $maxSampleValue].',
          );
        }
      }
    }
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
        (
          config: config,
          frameNumber: frameNumber,
          channels: frameChannels,
        ),
      );
      frameNumber++;
    }

    return tasks;
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
    if (totalSamples > _maxFlacTotalSamples) {
      throw RangeError.value(
        totalSamples,
        'totalSamples',
        'must be <= $_maxFlacTotalSamples (36-bit STREAMINFO field)',
      );
    }

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

    final md5Signature = _computePcmMd5(samples);
    streamInfo.setRange(18, 34, md5Signature);

    bytes.add(streamInfo);
  }

  Uint8List _computePcmMd5(List<Samples> samples) {
    final channelCount = samples.length;
    if (channelCount == 0) {
      return Uint8List.fromList(md5.convert(const <int>[]).bytes);
    }

    final bytesPerSample = (_config.bitsPerSample + 7) >> 3;
    final totalSamples = samples.first.length;
    final pcm = Uint8List(totalSamples * channelCount * bytesPerSample);

    int offset = 0;
    for (int sampleIndex = 0; sampleIndex < totalSamples; sampleIndex++) {
      for (int channelIndex = 0; channelIndex < channelCount; channelIndex++) {
        final sample = samples[channelIndex][sampleIndex];
        for (int byteIndex = 0; byteIndex < bytesPerSample; byteIndex++) {
          pcm[offset++] = (sample >> (8 * byteIndex)) & 0xFF;
        }
      }
    }

    return Uint8List.fromList(md5.convert(pcm).bytes);
  }

  Uint8List _encode(List<Samples> samples, int frameNumber) {
    final frame = BitWriter();

    final channels = samples.length;
    final blockSize = samples.first.length;
    final sampleRateHeader = _resolveFrameSampleRateHeader(_config.sampleRate);
    final frameBitDepthCode = _resolveFrameBitDepthCode(_config.bitsPerSample);

    // 0xFFF8:
    // sync code + reserved bit + fixed-blocksize strategy.
    frame.addBytes(const [0xFF, 0xF8]);

    // 4 bits block size code + 4 bits sample rate code.
    frame.addByte((_frameBlockSizeCode << 4) | sampleRateHeader.code);

    // 4 bits channel assignment + 3 bits bit depth code + reserved bit.
    frame.addByte(((channels - 1) << 4) | (frameBitDepthCode << 1));

    // In fixed-blocksize mode, this coded number is the frame number.
    frame.addBytes(_encodeFrameNumber(frameNumber));

    // Because we use block-size code 0x7, we append blockSize - 1 on 16 bits.
    final encodedBlockSize = blockSize - 1;
    frame.addByte((encodedBlockSize >> 8) & 0xFF);
    frame.addByte(encodedBlockSize & 0xFF);
    frame.addBytes(sampleRateHeader.extraBytes);

    final headerCrc = calculateCRC8Range(frame.rawBuffer, 0, frame.length);
    frame.addByte(headerCrc);

    final subframeWriter = frame;

    // One subframe per channel:
    // - constant if all samples in the channel chunk are identical
    // - fixed predictor + Rice residuals if profitable
    // - verbatim otherwise
    for (final channel in samples) {
      if (_isConstantChannel(channel)) {
        _writeConstantSubframe(subframeWriter, channel.first);
      } else {
        final fixedDecision = _chooseFixedPredictor(channel);
        final lpcDecision = _shouldSearchLpc(channel, fixedDecision)
            ? _chooseLpcPredictor(channel)
            : null;

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

    final frameCrc16 = calculateCRC16Range(frame.rawBuffer, 0, frame.length);
    frame.addByte((frameCrc16 >> 8) & 0xFF);
    frame.addByte(frameCrc16 & 0xFF);

    return frame.toBytes();
  }

  ({int code, List<int> extraBytes}) _resolveFrameSampleRateHeader(
    int sampleRate,
  ) {
    // Prefer compact standard FLAC header codes when available.
    switch (sampleRate) {
      case 8000:
        return (code: 0x4, extraBytes: const []);
      case 16000:
        return (code: 0x5, extraBytes: const []);
      case 22050:
        return (code: 0x6, extraBytes: const []);
      case 24000:
        return (code: 0x7, extraBytes: const []);
      case 32000:
        return (code: 0x8, extraBytes: const []);
      case 44100:
        return (code: 0x9, extraBytes: const []);
      case 48000:
        return (code: 0xA, extraBytes: const []);
      case 88200:
        return (code: 0x1, extraBytes: const []);
      case 96000:
        return (code: 0xB, extraBytes: const []);
      case 176400:
        return (code: 0x2, extraBytes: const []);
      case 192000:
        return (code: 0x3, extraBytes: const []);
    }

    // 8-bit sample rate in kHz, written at the end of the frame header.
    if (sampleRate > 0 && sampleRate % 1000 == 0) {
      final rateInKhz = sampleRate ~/ 1000;
      if (rateInKhz <= 0xFF) {
        return (code: 0xC, extraBytes: [rateInKhz]);
      }
    }

    // 16-bit sample rate in Hz, written at the end of the frame header.
    if (sampleRate > 0 && sampleRate <= 0xFFFF) {
      return (
        code: 0xD,
        extraBytes: [
          (sampleRate >> 8) & 0xFF,
          sampleRate & 0xFF,
        ],
      );
    }

    // 16-bit sample rate in tens of Hz, written at the end of the frame header.
    if (sampleRate > 0 && sampleRate % 10 == 0) {
      final rateInTensOfHz = sampleRate ~/ 10;
      if (rateInTensOfHz <= 0xFFFF) {
        return (
          code: 0xE,
          extraBytes: [
            (rateInTensOfHz >> 8) & 0xFF,
            rateInTensOfHz & 0xFF,
          ],
        );
      }
    }

    // Fall back to STREAMINFO as required by FLAC when no compact code fits.
    return (code: 0x0, extraBytes: const []);
  }

  int _resolveFrameBitDepthCode(int bitsPerSample) {
    return switch (bitsPerSample) {
      8 => 0x1,
      12 => 0x2,
      16 => 0x4,
      20 => 0x5,
      24 => 0x6,
      32 => 0x7,
      _ => 0x0, // from STREAMINFO
    };
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

  bool _shouldSearchLpc(
    Samples channel,
    _FixedPredictorDecision? fixedDecision,
  ) {
    if (_config.maxLpcOrder <= 0) {
      return false;
    }
    if (fixedDecision == null) {
      return true;
    }

    final verbatimBits = 8 + channel.length * _config.bitsPerSample;
    final fixedSavings = verbatimBits - fixedDecision.estimatedBits;
    if (fixedSavings <= 0) {
      return true;
    }

    final fixedGain = fixedSavings / verbatimBits;

    // Heuristic: LPC is much more expensive than fixed prediction because it
    // runs autocorrelation, Levinson-Durbin, coefficient quantization, and
    // residual scoring for each order. On the local 31 MB 44.1 kHz stereo
    // benchmark, the post-Rice-optimization encoder is dominated by this LPC
    // search. Skipping LPC when fixed prediction already saves 25% over
    // verbatim keeps a useful compression check while avoiding many expensive
    // searches. The default 25% threshold is deliberately conservative: the
    // local benchmark showed that lower thresholds are faster but grow output
    // size more aggressively. Risk: some material may compress smaller with LPC
    // despite a good fixed predictor. Fallback: set
    // lpcSearchFixedPredictorSkipGain to 1.0 to force the old exhaustive LPC
    // search whenever fixed is profitable.
    return fixedGain < _config.lpcSearchFixedPredictorSkipGain;
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
      final residualAbsSum = _foldResidualsInto(
        _residualScratch,
        residualLength,
        _foldedResidualScratch,
      );
      final riceCoding = _chooseRiceCoding(
        _foldedResidualScratch,
        residualLength,
        residualAbsSum,
      );
      final estimatedBits =
          _estimateFixedSubframeBitCount(order, riceCoding.encodedBits);

      if (estimatedBits >= verbatimBits) {
        continue;
      }

      if (best == null || estimatedBits < best.estimatedBits) {
        best = _FixedPredictorDecision(
          order: order,
          riceParameter: riceCoding.parameter,
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
      final residualAbsSum = _foldResidualsInto(
        _residualScratch,
        residualLength,
        _foldedResidualScratch,
      );
      final riceCoding = _chooseRiceCoding(
        _foldedResidualScratch,
        residualLength,
        residualAbsSum,
      );
      final estimatedBits = _estimateLpcSubframeBitCount(
        order,
        quantized.precision,
        riceCoding.encodedBits,
      );

      if (estimatedBits >= verbatimBits) {
        continue;
      }

      if (best == null || estimatedBits < best.estimatedBits) {
        best = (
          order: order,
          riceParameter: riceCoding.parameter,
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
    final channelLength = channel.length;

    switch (order) {
      case 0:
        for (int i = 0; i < channelLength; i++) {
          outResiduals[i] = channel[i];
        }
        return channelLength;
      case 1:
        int outIndex = 0;
        for (int i = 1; i < channelLength; i++) {
          outResiduals[outIndex++] = channel[i] - channel[i - 1];
        }
        return outIndex;
      case 2:
        int outIndex = 0;
        for (int i = 2; i < channelLength; i++) {
          outResiduals[outIndex++] =
              channel[i] - 2 * channel[i - 1] + channel[i - 2];
        }
        return outIndex;
      case 3:
        int outIndex = 0;
        for (int i = 3; i < channelLength; i++) {
          outResiduals[outIndex++] = channel[i] -
              3 * channel[i - 1] +
              3 * channel[i - 2] -
              channel[i - 3];
        }
        return outIndex;
      case 4:
        int outIndex = 0;
        for (int i = 4; i < channelLength; i++) {
          outResiduals[outIndex++] = channel[i] -
              4 * channel[i - 1] +
              6 * channel[i - 2] -
              4 * channel[i - 3] +
              channel[i - 4];
        }
        return outIndex;
      default:
        throw ArgumentError.value(order, 'order', 'unsupported fixed order');
    }
  }

  _RiceCodingDecision _chooseRiceCoding(
    Int32List foldedResiduals,
    int length,
    int residualAbsSum,
  ) {
    if (length == 0) {
      return (parameter: 0, encodedBits: 0);
    }

    final meanAbs = residualAbsSum / length;
    final estimated = meanAbs <= 0
        ? 0
        : (math.log(meanAbs * math.ln2) / math.ln2).round().clamp(0, 14);

    final candidateMin = estimated > 0 ? estimated - 1 : 0;
    final candidateMax = estimated < 14 ? estimated + 1 : 14;

    final parameter0 = candidateMin;
    final parameter1 = candidateMin + 1;
    final parameter2 = candidateMin + 2;
    final hasParameter1 = parameter1 <= candidateMax;
    final hasParameter2 = parameter2 <= candidateMax;
    final fixedBits0 = 1 + parameter0;
    final fixedBits1 = 1 + parameter1;
    final fixedBits2 = 1 + parameter2;

    // Rice parameter selection is a hot path. The folded residuals are already
    // materialized for the eventual writer, so we score every candidate in one
    // scan and reuse the winning encoded bit count for subframe selection.
    int bits0 = 0;
    int bits1 = 0;
    int bits2 = 0;
    for (int i = 0; i < length; i++) {
      final folded = foldedResiduals[i];
      bits0 += (folded >> parameter0) + fixedBits0;
      if (hasParameter1) {
        bits1 += (folded >> parameter1) + fixedBits1;
      }
      if (hasParameter2) {
        bits2 += (folded >> parameter2) + fixedBits2;
      }
    }

    int bestParameter = parameter0;
    int bestBits = bits0;
    if (hasParameter1 && bits1 < bestBits) {
      bestParameter = parameter1;
      bestBits = bits1;
    }
    if (hasParameter2 && bits2 < bestBits) {
      bestParameter = parameter2;
      bestBits = bits2;
    }

    return (parameter: bestParameter, encodedBits: bestBits);
  }

  int _estimateFixedSubframeBitCount(
    int order,
    int riceEncodedBits,
  ) {
    // Subframe header + warm-up samples + residual header.
    return 8 + (order * _config.bitsPerSample) + 10 + riceEncodedBits;
  }

  int _estimateLpcSubframeBitCount(
    int order,
    int qlpPrecision,
    int riceEncodedBits,
  ) {
    // Subframe header + warm-up samples + LPC params + residual header.
    return 8 +
        (order * _config.bitsPerSample) +
        4 +
        5 +
        (order * qlpPrecision) +
        10 +
        riceEncodedBits;
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
      final residual = residuals[i];
      final folded = residual >= 0 ? (residual << 1) : ((-residual << 1) - 1);
      final quotient = folded >> riceParameter;
      final remainderMask = (1 << riceParameter) - 1;
      final remainder = folded & remainderMask;

      writer.writeUnaryZeroCount(quotient);
      if (riceParameter > 0) {
        writer.writeBits(remainder, riceParameter);
      }
    }
  }

  int _foldResidualsInto(
    Int32List residuals,
    int length,
    Int32List outFoldedResiduals,
  ) {
    // Unroll by 4 to reduce loop overhead on hot paths.
    int i = 0;
    int sumAbs = 0;
    final unrolledEnd = length - (length % 4);
    while (i < unrolledEnd) {
      final r0 = residuals[i];
      outFoldedResiduals[i] = r0 >= 0 ? (r0 << 1) : ((-r0 << 1) - 1);
      sumAbs += r0 >= 0 ? r0 : -r0;
      final r1 = residuals[i + 1];
      outFoldedResiduals[i + 1] = r1 >= 0 ? (r1 << 1) : ((-r1 << 1) - 1);
      sumAbs += r1 >= 0 ? r1 : -r1;
      final r2 = residuals[i + 2];
      outFoldedResiduals[i + 2] = r2 >= 0 ? (r2 << 1) : ((-r2 << 1) - 1);
      sumAbs += r2 >= 0 ? r2 : -r2;
      final r3 = residuals[i + 3];
      outFoldedResiduals[i + 3] = r3 >= 0 ? (r3 << 1) : ((-r3 << 1) - 1);
      sumAbs += r3 >= 0 ? r3 : -r3;
      i += 4;
    }

    while (i < length) {
      final residual = residuals[i];
      outFoldedResiduals[i] =
          residual >= 0 ? (residual << 1) : ((-residual << 1) - 1);
      sumAbs += residual >= 0 ? residual : -residual;
      i++;
    }

    return sumAbs;
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

    return (
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

typedef _FrameEncodeTask = ({
  FlacEncoderConfig config,
  int frameNumber,
  List<Samples> channels,
});

typedef _TransferableFrameEncodeTask = ({
  FlacEncoderConfig config,
  int frameNumber,
  List<TransferableTypedData> channels,
});

typedef _LpcPredictorDecision = ({
  int order,
  int riceParameter,
  Int32List residuals,
  int estimatedBits,
  int qlpPrecision,
  int shift,
  List<int> coefficients,
});

typedef _QuantizedLpc = ({
  int precision,
  int shift,
  List<int> coefficients,
});

typedef _RiceCodingDecision = ({
  int parameter,
  int encodedBits,
});

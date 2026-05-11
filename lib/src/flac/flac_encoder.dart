import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/utils/crc/crc8.dart';

class FlacEncoder {
  // Mandatory FLAC stream signature: first 4 bytes of the file.
  static const _flacMagicWord = [0x66, 0x4C, 0x61, 0x43]; // "fLaC"

  // Fixed STREAMINFO payload length in FLAC (always 34 bytes).
  static const _streamInfoBlockLength = 34;

  // Number of inter-channel samples targeted per frame.
  static const _frameBlockSize = 4096;

  // Stream sample rate currently emitted by this encoder.
  static const _sampleRate = 44100;

  // Stream bit depth currently emitted by this encoder.
  static const _bitsPerSample = 16;

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

  // Maximum fixed predictor order defined by FLAC.
  static const _maxFixedPredictorOrder = 4;

  Uint8List encode(List<Samples> samples) {
    final bytes = BytesBuilder(copy: false);
    bytes.add(_flacMagicWord);
    _writeStreamInfoBlock(bytes, samples);

    final totalSamples = samples.first.length;
    int frameNumber = 0;

    for (int start = 0; start < totalSamples; start += _frameBlockSize) {
      // End index (exclusive) of the current frame window, clamped to
      // totalSamples for the last partial frame.
      final endExclusive = (start + _frameBlockSize < totalSamples)
          ? start + _frameBlockSize
          : totalSamples;

      // Per-channel PCM chunk for this frame: each entry is one channel
      // restricted to [start, endExclusive).
      final frameChannels = <Samples>[
        for (final channel in samples)
          Int32List.fromList(channel.sublist(start, endExclusive)),
      ];

      bytes.add(_encode(frameChannels, frameNumber));
      frameNumber++;
    }

    return bytes.toBytes();
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
    streamInfoView.setUint16(0, _frameBlockSize, Endian.big); // min block size
    streamInfoView.setUint16(2, _frameBlockSize, Endian.big); // max block size

    // Sample rate declared in STREAMINFO.
    // FLAC stores "channels - 1" in a 3-bit field.
    final channelsMinusOne = samples.length - 1;

    // FLAC stores "bitsPerSample - 1" in a 5-bit field.
    const bitsPerSampleMinusOne = _bitsPerSample - 1;

    // Total number of inter-channel samples declared in the stream.
    final totalSamples = samples.first.length;

    // STREAMINFO 64-bit packed field:
    // [sampleRate:20][channels-1:3][bitsPerSample-1:5][totalSamples:36]
    final packed = (_sampleRate << 44) |
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

    final subframeWriter = _BitWriter(frame);

    // One subframe per channel:
    // - constant if all samples in the channel chunk are identical
    // - fixed predictor + Rice residuals if profitable
    // - verbatim otherwise
    for (final channel in samples) {
      if (_isConstantChannel(channel)) {
        _writeConstantSubframe(subframeWriter, channel.first);
      } else {
        final fixedDecision = _chooseFixedPredictor(channel);
        if (fixedDecision != null) {
          _writeFixedSubframe(subframeWriter, channel, fixedDecision);
        } else {
          _writeVerbatimSubframe(subframeWriter, channel);
        }
      }
    }

    // Frame CRC16 must be byte-aligned.
    subframeWriter.alignToByte();

    final frameBytesWithoutCrc16 = frame.toBytes();
    final frameCrc16 = _calculateCrc16(frameBytesWithoutCrc16);
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
    final verbatimBits = 8 + channel.length * _bitsPerSample;
    _FixedPredictorDecision? best;

    final maxOrder = channel.length > _maxFixedPredictorOrder
        ? _maxFixedPredictorOrder
        : channel.length;

    for (int order = 0; order <= maxOrder; order++) {
      final residuals = _computeFixedResiduals(channel, order);
      final riceParameter = _chooseRiceParameter(residuals);
      final estimatedBits =
          _estimateFixedSubframeBitCount(order, residuals, riceParameter);

      if (estimatedBits >= verbatimBits) {
        continue;
      }

      if (best == null || estimatedBits < best.estimatedBits) {
        best = _FixedPredictorDecision(
          order: order,
          riceParameter: riceParameter,
          residuals: residuals,
          estimatedBits: estimatedBits,
        );
      }
    }

    return best;
  }

  List<int> _computeFixedResiduals(Samples channel, int order) {
    final residuals = <int>[];

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

      residuals.add(sample - prediction);
    }

    return residuals;
  }

  int _chooseRiceParameter(List<int> residuals) {
    if (residuals.isEmpty) {
      return 0;
    }

    int bestParameter = 0;
    int bestBits = 1 << 30;

    for (int parameter = 0; parameter <= 14; parameter++) {
      int bits = 0;
      for (final residual in residuals) {
        final folded = _foldResidual(residual);
        final quotient = folded >> parameter;
        bits += quotient + 1 + parameter;
      }

      if (bits < bestBits) {
        bestBits = bits;
        bestParameter = parameter;
      }
    }

    return bestParameter;
  }

  int _estimateFixedSubframeBitCount(
    int order,
    List<int> residuals,
    int riceParameter,
  ) {
    // Subframe header + warm-up samples + residual header.
    int bits = 8 + (order * _bitsPerSample) + 10;

    for (final residual in residuals) {
      final folded = _foldResidual(residual);
      final quotient = folded >> riceParameter;
      bits += quotient + 1 + riceParameter;
    }

    return bits;
  }

  int _fixedSubframeHeaderForOrder(int order) {
    final subframeType = 8 + order;
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
  void _writeConstantSubframe(_BitWriter writer, int sampleValue) {
    writer.writeBits(_constantSubframeHeader, 8);
    writer.writeSigned(sampleValue, _bitsPerSample);
  }

  /// Writes a FLAC `fixed predictor` subframe.
  ///
  /// The layout is:
  /// - fixed subframe header (order 0..4)
  /// - warm-up samples (`order` values)
  /// - residual coded with partitioned Rice method 0 and partition order 0
  void _writeFixedSubframe(
    _BitWriter writer,
    Samples channel,
    _FixedPredictorDecision decision,
  ) {
    writer.writeBits(_fixedSubframeHeaderForOrder(decision.order), 8);

    for (int i = 0; i < decision.order; i++) {
      writer.writeSigned(channel[i], _bitsPerSample);
    }

    // Residual header:
    // - method 0 => 4-bit Rice parameter
    // - partition order 0 => single partition
    writer.writeBits(0, 2);
    writer.writeBits(0, 4);
    writer.writeBits(decision.riceParameter, 4);

    for (final residual in decision.residuals) {
      final folded = _foldResidual(residual);
      final quotient = folded >> decision.riceParameter;
      final remainderMask = (1 << decision.riceParameter) - 1;
      final remainder = folded & remainderMask;

      writer.writeUnaryZeroCount(quotient);
      if (decision.riceParameter > 0) {
        writer.writeBits(remainder, decision.riceParameter);
      }
    }
  }

  int _foldResidual(int residual) {
    return residual >= 0 ? (residual << 1) : ((-residual << 1) - 1);
  }

  /// Writes a FLAC `verbatim` subframe for one channel.
  ///
  /// Layout:
  /// - 1 byte subframe header (`_verbatimSubframeHeader`)
  /// - all channel samples written directly, without prediction/residual coding
  ///
  /// Each sample is currently encoded as signed 16-bit big-endian.
  void _writeVerbatimSubframe(_BitWriter writer, Samples channel) {
    writer.writeBits(_verbatimSubframeHeader, 8);

    // Write each sample as signed big-endian 16-bit.
    for (final sample in channel) {
      writer.writeSigned(sample, _bitsPerSample);
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

  /// Frame footer CRC-16 with polynomial x^16 + x^15 + x^2 + x^0.
  int _calculateCrc16(List<int> data) {
    int crc = 0;
    const polynomial = 0x8005;

    for (final byte in data) {
      crc ^= (byte << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ polynomial) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }

    return crc;
  }
}

class _FixedPredictorDecision {
  final int order;
  final int riceParameter;
  final List<int> residuals;
  final int estimatedBits;

  const _FixedPredictorDecision({
    required this.order,
    required this.riceParameter,
    required this.residuals,
    required this.estimatedBits,
  });
}

class _BitWriter {
  final BytesBuilder _bytes;
  int _currentByte = 0;
  int _nextBitIndex = 7;

  _BitWriter(this._bytes);

  void writeBits(int value, int bitCount) {
    for (int i = bitCount - 1; i >= 0; i--) {
      final bit = (value >> i) & 0x1;
      _currentByte |= bit << _nextBitIndex;
      _nextBitIndex--;

      if (_nextBitIndex < 0) {
        _bytes.addByte(_currentByte & 0xFF);
        _currentByte = 0;
        _nextBitIndex = 7;
      }
    }
  }

  void writeSigned(int value, int bitCount) {
    final mask = (1 << bitCount) - 1;
    writeBits(value & mask, bitCount);
  }

  void writeUnaryZeroCount(int zeroCount) {
    for (int i = 0; i < zeroCount; i++) {
      writeBits(0, 1);
    }
    writeBits(1, 1);
  }

  void alignToByte() {
    if (_nextBitIndex == 7) {
      return;
    }

    _bytes.addByte(_currentByte & 0xFF);
    _currentByte = 0;
    _nextBitIndex = 7;
  }
}

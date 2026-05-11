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

  // Subframe header byte for verbatim samples (no wasted bits).
  static const _verbatimSubframeHeader = 0x02;

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

    // One verbatim subframe per channel.
    for (final channel in samples) {
      frame.addByte(_verbatimSubframeHeader);

      // Write each sample as signed big-endian 16-bit.
      for (final sample in channel) {
        final sample16 = sample & 0xFFFF;
        frame.addByte((sample16 >> 8) & 0xFF);
        frame.addByte(sample16 & 0xFF);
      }
    }

    final frameBytesWithoutCrc16 = frame.toBytes();
    final frameCrc16 = _calculateCrc16(frameBytesWithoutCrc16);
    frame.addByte((frameCrc16 >> 8) & 0xFF);
    frame.addByte(frameCrc16 & 0xFF);

    return frame.toBytes();
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

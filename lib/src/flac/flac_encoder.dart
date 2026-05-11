import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';

class FlacEncoder {
  // Mandatory FLAC stream signature: first 4 bytes of the file.
  static const _flacMagicWord = [0x66, 0x4C, 0x61, 0x43]; // "fLaC"

  // Fixed STREAMINFO payload length in FLAC (always 34 bytes).
  static const _streamInfoBlockLength = 34;

  // Number of inter-channel samples targeted per frame.
  static const _frameBlockSize = 4096;

  Uint8List encode(List<Samples> samples) {
    final bytes = BytesBuilder(copy: false);
    bytes.add(_flacMagicWord);
    _writeStreamInfoBlock(bytes, samples);

    final totalSamples = samples.first.length;
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

      bytes.add(_encode(frameChannels));
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
    const sampleRate = 44100;

    // FLAC stores "channels - 1" in a 3-bit field.
    final channelsMinusOne = samples.length - 1;

    // FLAC stores "bitsPerSample - 1" in a 5-bit field.
    const bitsPerSampleMinusOne = 15; // 16-bit PCM

    // Total number of inter-channel samples declared in the stream.
    final totalSamples = samples.first.length;

    // STREAMINFO 64-bit packed field:
    // [sampleRate:20][channels-1:3][bitsPerSample-1:5][totalSamples:36]
    final packed = (sampleRate << 44) |
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

  Uint8List _encode(List<Samples> _) {
    throw UnimplementedError('_encode is not implemented yet');
  }
}

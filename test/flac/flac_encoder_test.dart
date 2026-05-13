import 'dart:typed_data';

import 'package:audio_codec/audio_codec.dart';
import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('Encoder writes STREAMINFO MD5 matching PCM payload', () {
    final left = Int32List.fromList([
      0,
      1200,
      -800,
      3200,
      -1600,
      400,
      700,
      -350,
      0,
      100,
      -200,
      300,
    ]);
    final right = Int32List.fromList([
      0,
      -900,
      1100,
      -2600,
      1400,
      -500,
      650,
      -200,
      50,
      -120,
      220,
      -330,
    ]);
    final channels = <Samples>[left, right];

    final encoder = FlacEncoder();
    final encoded = encoder.encode(
      channels,
      config: const FlacEncoderConfig(
        sampleRate: 48000,
        bitsPerSample: 16,
        frameBlockSize: 8,
      ),
    );

    final decoder = FlacDecoder.fromBytes(encoded);
    final result = decoder.decode();
    while (decoder.hasNextFrame()) {
      decoder.readFrame();
    }

    final expectedMd5 = _computePcmMd5(channels, 16);
    expect(result.streamInfoBlock?.md5Signature, expectedMd5);
    expect(decoder.isCorrect(), isTrue);
    decoder.close();
  });
}

List<int> _computePcmMd5(List<Samples> channels, int bitsPerSample) {
  final bytesPerSample = (bitsPerSample + 7) >> 3;
  final totalSamples = channels.first.length;
  final pcm = Uint8List(totalSamples * channels.length * bytesPerSample);

  int offset = 0;
  for (int sampleIndex = 0; sampleIndex < totalSamples; sampleIndex++) {
    for (int channelIndex = 0; channelIndex < channels.length; channelIndex++) {
      final sample = channels[channelIndex][sampleIndex];
      for (int byteIndex = 0; byteIndex < bytesPerSample; byteIndex++) {
        pcm[offset++] = (sample >> (8 * byteIndex)) & 0xFF;
      }
    }
  }

  return md5.convert(pcm).bytes;
}

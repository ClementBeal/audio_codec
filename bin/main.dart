import 'dart:io';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/pcm/pcm_decoder.dart';

void main(List<String> args) {
  final inputPath = args[0];

  if (inputPath.endsWith("flac")) {
    final decoder = FlacDecoder(track: File(inputPath));
    decoder.decode(); // Decode metadata

    // Decode frames and write to PCM
    while (decoder.hasNextFrame()) {
      try {
        decoder.readFrame();
      } catch (e) {
        rethrow;
      }
    }

    decoder.close();
  } else if (inputPath.endsWith("pcm")) {
    final encoding = PCMEncoding.fromString(args[1]);

    if (encoding == null) {
      throw Exception("The PCM decoder are wrong : ${args[1]}");
    }

    PcmDecoder(
      track: File(inputPath),
      sampleRate: 44100,
      nbChannel: 1,
      encoding: encoding,
    );
  }
}

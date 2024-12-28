import 'dart:io';

import 'package:audio_codec/src/flac/flac_decoder.dart';

void main(List<String> args) {
  final inputPath = args[0];

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
}

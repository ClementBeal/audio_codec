import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/wav/wav_encoder.dart';

void main() {
  final flacFile = File('test.flac');

  final decoder = FlacDecoder(track: flacFile);
  final result = decoder.decode();

  print(result.streamInfoBlock);

  final pcmSamples = Int32List(
    result.streamInfoBlock!.totalSamples * result.streamInfoBlock!.channels,
  );

  // Decode frames and write to PCM
  int frameNumber = 0;

  while (decoder.hasNextFrame()) {
    final frame = decoder.readFrame();

    writeFrameToPcm(
      pcmSamples,
      frame,
      frameNumber,
      result.streamInfoBlock!.sampleRate,
    );

    frameNumber++;
  }

  decoder.close();

  WavEncoder(
    sampleRate: result.streamInfoBlock!.sampleRate,
    numChannels: result.streamInfoBlock!.channels,
    bitDepth: result.streamInfoBlock!.bitsPerSample,
  ).encode(
    File("output.wav"),
    pcmSamples,
  );
}

void writeFrameToPcm(
    Int32List samples, FlacFrame frame, int frameNumber, int sampleRate) {
  final numChannels = frame.channels.nbChannels;
  final numSamples = frame.blockSize;

  // Calculate the starting index in 'samples' for this frame
  final frameStart = frameNumber * numSamples * numChannels;

  // Interleave and write samples
  for (int i = 0; i < numSamples; i++) {
    for (int c = 0; c < numChannels; c++) {
      // Write directly to the correct position in 'samples'
      samples[frameStart + i * numChannels + c] = frame.subframes[c][i];
    }
  }
}

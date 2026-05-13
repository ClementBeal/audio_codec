import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/wav/wav_encoder.dart';

void main() {
  final flacFile = File('test.flac');

  final decoder = FlacDecoder.fromFile(flacFile);
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
    interleavedPcmToLittleEndianBytes(
      pcmSamples,
      result.streamInfoBlock!.bitsPerSample,
    ),
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

Uint8List interleavedPcmToLittleEndianBytes(Int32List samples, int bitDepth) {
  if (bitDepth % 8 != 0) {
    throw ArgumentError('Bit depth must be a multiple of 8');
  }

  final bytesPerSample = bitDepth ~/ 8;
  final output = Uint8List(samples.length * bytesPerSample);
  final buffer = ByteData.sublistView(output);

  for (var i = 0; i < samples.length; i++) {
    final offset = i * bytesPerSample;
    final sample = samples[i];

    switch (bytesPerSample) {
      case 1:
        buffer.setInt8(offset, sample);
      case 2:
        buffer.setInt16(offset, sample, Endian.little);
      case 3:
        buffer.setUint8(offset, sample & 0xFF);
        buffer.setUint8(offset + 1, (sample >> 8) & 0xFF);
        buffer.setUint8(offset + 2, (sample >> 16) & 0xFF);
      case 4:
        buffer.setInt32(offset, sample, Endian.little);
      default:
        throw UnsupportedError('Unsupported bit depth: $bitDepth');
    }
  }

  return output;
}

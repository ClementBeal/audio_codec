import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/utils/buffer.dart';

class PcmDecoder {
  late Buffer buffer;

  final int nbChannel;
  final int sampleRate;
  final PCMDecoderEncoding encoding;

  late final lengthFile = buffer.randomAccessFile.lengthSync();
  late final int nbSamples;
  late final int samplesPerChannel;

  late final channels = [
    for (int i = 0; i < nbChannel; i++) Int32List(samplesPerChannel)
  ];

  PcmDecoder({
    required File track,
    required this.sampleRate,
    required this.nbChannel,
    required this.encoding,
  }) {
    buffer = Buffer(randomAccessFile: track.openSync());
    nbSamples = lengthFile ~/ encoding.bitsPerSamples;
    samplesPerChannel = nbSamples ~/ nbChannel;
  }

  void close() {
    buffer.randomAccessFile.close();
  }

  List<Samples> decode() {
    final bytesToRead = encoding.bitsPerSamples;
    final data = buffer.read(bytesToRead * nbChannel);

    if (data.isEmpty) return channels;

    switch (encoding) {
      case PCMDecoderEncoding.signed8bits:
        _signed8Bits(data);
        break;
      case PCMDecoderEncoding.unsigned8bits:
        _unsigned8Bits(data);
        break;
    }

    return channels;
  }

  void _unsigned8Bits(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 1;

    for (int i = 0; i < data.length; i += bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          channels[channel][sampleCounter] =
              data[i + channel * bytesPerSamples];
        }
      }

      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _signed8Bits(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 1;

    for (int i = 0; i < data.length; i += bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          channels[channel][sampleCounter] =
              data[i + channel * bytesPerSamples].toSigned(8);
        }
      }

      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }
}

enum PCMDecoderEncoding {
  signed8bits(8),
  unsigned8bits(8);

  final int bitsPerSamples;

  const PCMDecoderEncoding(this.bitsPerSamples);
}

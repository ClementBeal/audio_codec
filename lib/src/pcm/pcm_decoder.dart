import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/utils/buffer.dart';

class PcmDecoder {
  late Buffer buffer;

  final int nbChannel;
  final Endian endian;
  final bool signedData;
  final int sampleRate;
  final int bitPerSample;

  late final lengthFile = buffer.randomAccessFile.lengthSync();
  late final bytesPerSamples = (bitPerSample ~/ 8);
  late final nbSamples = lengthFile ~/ bytesPerSamples;
  late final samplesPerChannel = nbSamples ~/ nbChannel;

  late final channels = [
    for (int i = 0; i < nbChannel; i++) Int32List(samplesPerChannel)
  ];

  int id = 0;

  PcmDecoder({
    required File track,
    required this.bitPerSample,
    required this.sampleRate,
    required this.nbChannel,
    required this.endian,
    required this.signedData,
  }) {
    buffer = Buffer(randomAccessFile: track.openSync());
  }

  void close() {
    buffer.randomAccessFile.close();
  }

  List<Samples> decode() {
    print("Size : $lengthFile");
    print("Nb channel : $nbChannel");
    print("Bits per sample : $bitPerSample bits");
    print("Bytes per sample : $bytesPerSamples bytes");
    print("Samples per channel : $samplesPerChannel bytes");

    int sampleCounter = 0;

    while (id < lengthFile && sampleCounter < samplesPerChannel) {
      final bytesToRead = bytesPerSamples;
      final data = buffer.read(bytesToRead * nbChannel);
      id += data.length;

      if (data.isEmpty) break;

      if (signedData && bitPerSample == 8) {
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
    }

    return channels;
  }
}

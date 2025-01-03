import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/pcm/pcm_decoder.dart';

class PcmEncoder {
  late final int nbChannel;
  late final int samplesPerChannel;
  final List<Samples> channels;

  PcmEncoder({required this.channels})
      : nbChannel = channels.length,
        samplesPerChannel = channels.first.length;

  Uint8List encode(PCMEncoding encoding) {
    switch (encoding) {
      case PCMEncoding.signed8bits:
        return _signed8Bits(channels);
      case PCMEncoding.signed16bitsBE:
        return _signed16BitsBE(channels);
      case PCMEncoding.signed16bitsLE:
        // TODO: Handle this case.
        throw UnimplementedError();
      case PCMEncoding.signed24bitsBE:
        // TODO: Handle this case.
        throw UnimplementedError();
      case PCMEncoding.signed24bitsLE:
        // TODO: Handle this case.
        throw UnimplementedError();
      case PCMEncoding.signed32bitsBE:
        // TODO: Handle this case.
        throw UnimplementedError();
      case PCMEncoding.signed32bitsLE:
        // TODO: Handle this case.
        throw UnimplementedError();
      case PCMEncoding.unsigned8bits:
        return _unsigned8Bits(channels);
      case PCMEncoding.unsigned16bitsBE:
        return _unsigned16BitsBE(channels);
      case PCMEncoding.unsigned16bitsLE:
        return _unsigned16BitsLE(channels);
      case PCMEncoding.unsigned24bitsBE:
        return _unsigned24BitsBE(channels);
      case PCMEncoding.unsigned24bitsLE:
        return _unsigned24BitsLE(channels);
      case PCMEncoding.unsigned32bitsBE:
        return _unsigned32BitsBE(channels);
      case PCMEncoding.unsigned32bitsLE:
        return _unsigned32BitsLE(channels);
    }
  }

  Uint8List _signed8Bits(List<Samples> data) {
    int bytesPerSamples = 1;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        buffer.setInt8(
            channel + i * nbChannel * bytesPerSamples, data[channel][i]);
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _unsigned8Bits(List<Samples> data) {
    int bytesPerSamples = 1;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        buffer.setUint8(
            channel + i * nbChannel * bytesPerSamples, data[channel][i]);
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _signed16BitsBE(List<Samples> data) {
    int bytesPerSamples = 2;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        buffer.setInt16(
            channel + i * nbChannel * bytesPerSamples, data[channel][i]);
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _unsigned16BitsBE(List<Samples> data) {
    int bytesPerSamples = 2;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        buffer.setUint16(
            bytesPerSamples * channel + i * nbChannel * bytesPerSamples,
            data[channel][i]);
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _unsigned24BitsBE(List<Samples> data) {
    int bytesPerSamples = 3;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        int sample = data[channel][i];
        int offset =
            bytesPerSamples * channel + i * nbChannel * bytesPerSamples;
        buffer.setUint8(offset, (sample >> 16) & 0xFF);
        buffer.setUint8(offset + 1, (sample >> 8) & 0xFF);
        buffer.setUint8(offset + 2, sample & 0xFF);
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _unsigned32BitsBE(List<Samples> data) {
    int bytesPerSamples = 4;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        buffer.setUint32(
            bytesPerSamples * channel + i * nbChannel * bytesPerSamples,
            data[channel][i]);
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _unsigned16BitsLE(List<Samples> data) {
    int bytesPerSamples = 2;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        buffer.setUint16(
            bytesPerSamples * channel + i * nbChannel * bytesPerSamples,
            data[channel][i],
            Endian.little); // Note the Endian.little parameter
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _unsigned24BitsLE(List<Samples> data) {
    int bytesPerSamples = 3;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        int sample = data[channel][i];
        int offset =
            bytesPerSamples * channel + i * nbChannel * bytesPerSamples;
        // Set bytes in little-endian order (LSB first)
        buffer.setUint8(offset, sample & 0xFF);
        buffer.setUint8(offset + 1, (sample >> 8) & 0xFF);
        buffer.setUint8(offset + 2, (sample >> 16) & 0xFF);
      }
    }

    return buffer.buffer.asUint8List();
  }

  Uint8List _unsigned32BitsLE(List<Samples> data) {
    int bytesPerSamples = 4;

    final buffer = ByteData(samplesPerChannel * nbChannel * bytesPerSamples);

    for (var i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        buffer.setUint32(
            bytesPerSamples * channel + i * nbChannel * bytesPerSamples,
            data[channel][i],
            Endian.little); // Note the Endian.little parameter
      }
    }

    return buffer.buffer.asUint8List();
  }
}

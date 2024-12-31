import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';

class PcmDecoder {
  late RandomAccessFile buffer;

  final int nbChannel;
  final int sampleRate;
  final PCMDecoderEncoding encoding;

  late final lengthFile = buffer.lengthSync();
  late final int nbSamples;
  late final int samplesPerChannel;

  late final List<Samples> channels;

  PcmDecoder({
    required File track,
    required this.sampleRate,
    required this.nbChannel,
    required this.encoding,
  }) {
    buffer = track.openSync();
    // buffer = Buffer(randomAccessFile: track.openSync());
    nbSamples = lengthFile ~/ encoding.bytesPerSamples;
    samplesPerChannel = nbSamples ~/ nbChannel;
    channels = [
      for (int i = 0; i < nbChannel; i++) Int32List(samplesPerChannel)
    ];
  }

  void close() {
    buffer.close();
  }

  List<Samples> decode() {
    final data = buffer.readSync(lengthFile);

    if (data.isEmpty) return channels;

    switch (encoding) {
      case PCMDecoderEncoding.signed8bits:
        _signed8Bits(data);
        break;
      case PCMDecoderEncoding.unsigned8bits:
        _unsigned8Bits(data);
        break;
      case PCMDecoderEncoding.unsigned16bitsBE:
        _unsigned16BitsBE(data);
      case PCMDecoderEncoding.unsigned16bitsLE:
        _unsigned16BitsLE(data);
      case PCMDecoderEncoding.unsigned24bitsBE:
        _unsigned24BitsBE(data);
      case PCMDecoderEncoding.unsigned24bitsLE:
        _unsigned24BitsLE(data);
      case PCMDecoderEncoding.unsigned32bitsBE:
        _unsigned32BitsBE(data);
      case PCMDecoderEncoding.unsigned32bitsLE:
        _unsigned32BitsLE(data);
      case PCMDecoderEncoding.signed16bitsBE:
        _signed16BitsBE(data);
      case PCMDecoderEncoding.signed16bitsLE:
        _signed16BitsLE(data);
      case PCMDecoderEncoding.signed24bitsBE:
        _signed24BitsBE(data);
      case PCMDecoderEncoding.signed24bitsLE:
        _signed24BitsLE(data);
      case PCMDecoderEncoding.signed32bitsBE:
        _signed32BitsBE(data);
      case PCMDecoderEncoding.signed32bitsLE:
        _signed32BitsLE(data);
    }

    return channels;
  }

  void _unsigned8Bits(Uint8List data) {
    int bytesPerSamples = 1;

    for (int i = 0; i < samplesPerChannel; i++) {
      for (int channel = 0; channel < nbChannel; channel++) {
        channels[channel][i] = data[i * nbChannel + channel * bytesPerSamples];
      }
    }
  }

  void _unsigned16BitsBE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 2;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples] << 8) |
              data[i + channel * bytesPerSamples + 1];
          channels[channel][sampleCounter] = sample;
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _unsigned24BitsBE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 3;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples] << 16) |
              data[i + channel * bytesPerSamples + 1] << 8 |
              data[i + channel * bytesPerSamples + 2];
          channels[channel][sampleCounter] = sample;
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _unsigned32BitsBE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 4;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples] << 24) |
              data[i + channel * bytesPerSamples + 1] << 16 |
              data[i + channel * bytesPerSamples + 2] << 8 |
              data[i + channel * bytesPerSamples + 3];
          channels[channel][sampleCounter] = sample;
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _unsigned16BitsLE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 2;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples + 1] << 8) |
              data[i + channel * bytesPerSamples];
          channels[channel][sampleCounter] = sample;
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _unsigned24BitsLE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 3;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples + 2] << 16) |
              data[i + channel * bytesPerSamples + 1] << 8 |
              data[i + channel * bytesPerSamples];
          channels[channel][sampleCounter] = sample;
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _unsigned32BitsLE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 4;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples + 3] << 24) |
              data[i + channel * bytesPerSamples + 2] << 16 |
              data[i + channel * bytesPerSamples + 1] << 8 |
              data[i + channel * bytesPerSamples];
          channels[channel][sampleCounter] = sample;
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
              data[i * nbChannel + channel * bytesPerSamples].toSigned(8);
        }
      }

      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _signed16BitsBE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 2;

    for (int i = 0; i < data.length; i += bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          channels[channel][sampleCounter] =
              (data[i * nbChannel + channel * bytesPerSamples] << 8 |
                      data[i * nbChannel + channel * bytesPerSamples + 1])
                  .toSigned(16);
        }
      }

      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _signed24BitsBE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 3;

    for (int i = 0; i < data.length; i += bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          channels[channel][sampleCounter] =
              (data[i * nbChannel + channel * bytesPerSamples] << 16 |
                      data[i * nbChannel + channel * bytesPerSamples + 1] << 8 |
                      data[i * nbChannel + channel * bytesPerSamples + 2])
                  .toSigned(24);
        }
      }

      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _signed32BitsBE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 4;

    for (int i = 0; i < data.length; i += bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          channels[channel][sampleCounter] =
              (data[i * nbChannel + channel * bytesPerSamples] << 24 |
                      data[i * nbChannel + channel * bytesPerSamples + 1] <<
                          16 |
                      data[i * nbChannel + channel * bytesPerSamples + 2] << 8 |
                      data[i * nbChannel + channel * bytesPerSamples + 3])
                  .toSigned(32);
        }
      }

      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _signed16BitsLE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 2;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples + 1] << 8) |
              data[i + channel * bytesPerSamples];
          channels[channel][sampleCounter] = sample.toSigned(16);
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _signed24BitsLE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 3;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples + 2] << 16) |
              data[i + channel * bytesPerSamples + 1] << 8 |
              data[i + channel * bytesPerSamples];
          channels[channel][sampleCounter] = sample.toSigned(24);
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }

  void _signed32BitsLE(Uint8List data) {
    int sampleCounter = 0;
    int bytesPerSamples = 4;

    for (int i = 0; i < data.length; i += nbChannel * bytesPerSamples) {
      for (int channel = 0; channel < nbChannel; channel++) {
        if (sampleCounter < samplesPerChannel) {
          int sample = (data[i + channel * bytesPerSamples + 3] << 24) |
              data[i + channel * bytesPerSamples + 2] << 16 |
              data[i + channel * bytesPerSamples + 1] << 8 |
              data[i + channel * bytesPerSamples];
          channels[channel][sampleCounter] = sample.toSigned(32);
        }
      }
      if (sampleCounter < samplesPerChannel) {
        sampleCounter++;
      }
    }
  }
}

enum PCMDecoderEncoding {
  // signed
  signed8bits(1),
  signed16bitsBE(2),
  signed16bitsLE(2),
  signed24bitsBE(3),
  signed24bitsLE(3),
  signed32bitsBE(4),
  signed32bitsLE(4),
  // unsigned
  unsigned8bits(1),
  unsigned16bitsBE(2),
  unsigned16bitsLE(2),
  unsigned24bitsBE(3),
  unsigned24bitsLE(3),
  unsigned32bitsBE(4),
  unsigned32bitsLE(4);

  final int bytesPerSamples;

  const PCMDecoderEncoding(this.bytesPerSamples);

  static PCMDecoderEncoding? fromString(String possibleEncoding) {
    return switch (possibleEncoding) {
      "u8" => PCMDecoderEncoding.unsigned8bits,
      "s8" => PCMDecoderEncoding.unsigned8bits,
      "u16be" => PCMDecoderEncoding.unsigned16bitsBE,
      "u16le" => PCMDecoderEncoding.unsigned16bitsLE,
      "s16be" => PCMDecoderEncoding.signed16bitsBE,
      "s16le" => PCMDecoderEncoding.signed16bitsLE,
      "u24be" => PCMDecoderEncoding.unsigned24bitsBE,
      "u24le" => PCMDecoderEncoding.unsigned24bitsLE,
      "s24be" => PCMDecoderEncoding.signed24bitsBE,
      "s24le" => PCMDecoderEncoding.signed24bitsLE,
      "u32be" => PCMDecoderEncoding.unsigned32bitsBE,
      "u32le" => PCMDecoderEncoding.unsigned32bitsLE,
      "s32be" => PCMDecoderEncoding.signed32bitsBE,
      "s32le" => PCMDecoderEncoding.signed32bitsLE,
      _ => null
    };
  }
}

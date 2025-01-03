import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';

class PcmDecoder {
  late RandomAccessFile buffer;

  final int nbChannel;
  final int sampleRate;
  final PCMEncoding encoding;

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
      case PCMEncoding.signed8bits:
        _signed8Bits(data);
        break;
      case PCMEncoding.unsigned8bits:
        _unsigned8Bits(data);
        break;
      case PCMEncoding.unsigned16bitsBE:
        _unsigned16BitsBE(data);
      case PCMEncoding.unsigned16bitsLE:
        _unsigned16BitsLE(data);
      case PCMEncoding.unsigned24bitsBE:
        _unsigned24BitsBE(data);
      case PCMEncoding.unsigned24bitsLE:
        _unsigned24BitsLE(data);
      case PCMEncoding.unsigned32bitsBE:
        _unsigned32BitsBE(data);
      case PCMEncoding.unsigned32bitsLE:
        _unsigned32BitsLE(data);
      case PCMEncoding.signed16bitsBE:
        _signed16BitsBE(data);
      case PCMEncoding.signed16bitsLE:
        _signed16BitsLE(data);
      case PCMEncoding.signed24bitsBE:
        _signed24BitsBE(data);
      case PCMEncoding.signed24bitsLE:
        _signed24BitsLE(data);
      case PCMEncoding.signed32bitsBE:
        _signed32BitsBE(data);
      case PCMEncoding.signed32bitsLE:
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

enum PCMEncoding {
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

  const PCMEncoding(this.bytesPerSamples);

  static PCMEncoding? fromString(String possibleEncoding) {
    return switch (possibleEncoding) {
      "u8" => PCMEncoding.unsigned8bits,
      "s8" => PCMEncoding.unsigned8bits,
      "u16be" => PCMEncoding.unsigned16bitsBE,
      "u16le" => PCMEncoding.unsigned16bitsLE,
      "s16be" => PCMEncoding.signed16bitsBE,
      "s16le" => PCMEncoding.signed16bitsLE,
      "u24be" => PCMEncoding.unsigned24bitsBE,
      "u24le" => PCMEncoding.unsigned24bitsLE,
      "s24be" => PCMEncoding.signed24bitsBE,
      "s24le" => PCMEncoding.signed24bitsLE,
      "u32be" => PCMEncoding.unsigned32bitsBE,
      "u32le" => PCMEncoding.unsigned32bitsLE,
      "s32be" => PCMEncoding.signed32bitsBE,
      "s32le" => PCMEncoding.signed32bitsLE,
      _ => null
    };
  }
}

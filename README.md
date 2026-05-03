# audio_codec

[![pub.dev badge](https://img.shields.io/pub/v/audio_codec.svg)](https://pub.dev/packages/audio_codec)

A Dart library for audio decoding.

## Supported Formats

This package supports `FLAC` and `OGG + FLAC`.

## Installation

Add `audio_codec` to your `pubspec.yaml`:

```yaml
dependencies:
  audio_codec: ^0.1.0
```

Then, run:

```bash
dart pub get
```

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/audio_codec.dart';
import 'package:audio_codec/src/wav/wav_encoder.dart';

void main() {
  final flacFile = File('test.flac');

  final decoder = FlacDecoder.fromFile(flacFile);
  final result = decoder.decode();

  final pcmSamples = Int32List(
    result.streamInfoBlock!.totalSamples * result.streamInfoBlock!.channels,
  );

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
```

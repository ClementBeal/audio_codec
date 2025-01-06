# audio_codecs

[![pub.dev badge](https://img.shields.io/pub/v/audio_codecs.svg)](https://pub.dev/packages/audio_codecs)

A Dart library for decoding (and potentially encoding) audio files. This package provides a convenient way to work with various audio codecs within your Dart and Flutter applications.

## Codecs Support

| Codec | Decoding Status | Encoding Status | Notes                                                       |
| ----- | --------------- | --------------- | ----------------------------------------------------------- |
| FLAC  | Good            | -               | Decoding is functional, may have some minor audio glitches. |
| MP3   | -               | -               | Not yet implemented.                                        |
| OPUS  | -               | -               | Not yet implemented.                                        |
| WAV   | -               | Good            | Writing is supported.                                       |
| PCM   | Excellent       | Excellent       |                                                             |

## Status Levels

The "Status" column in the Codecs table uses the following quality indicators:

| Status    | Description                                                                                                      |
| --------- | ---------------------------------------------------------------------------------------------------------------- |
| -         | Not started yet.                                                                                                 |
| Passable  | The codec is partially implemented. For decoding, this might mean the file can be decoded, but with issues.      |
| Good      | The codec is mostly functional. For decoding, it might mean files can be decoded but with some audible glitches. |
| Excellent | The codec is fully implemented and considered stable. For decoding, it means no audible glitches.                |

## Installation

Add `audio_codecs` to your `pubspec.yaml`:

```yaml
dependencies:
  audio_codecs: ^0.0.1
```

Then, run:

```bash
dart pub get
```

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:audio_codec/src/wav/wav_encoder.dart';

void main() {
  final flacFile = File('test.flac');

  final decoder = FlacDecoder(track: flacFile);
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

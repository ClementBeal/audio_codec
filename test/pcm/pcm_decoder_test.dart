import 'dart:io';

import 'package:audio_codec/src/pcm/pcm_decoder.dart';
import 'package:test/test.dart';

void main() {
  group(
    "unsigned 8 bits",
    () {
      tearDown(
        () {
          File("a.pcm").deleteSync();
        },
      );

      test(
        "1 channel",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0, 123, 255, 11]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 1,
            encoding: PCMDecoderEncoding.unsigned8bits,
          );

          final channels = decoder.decode();

          expect(channels.length, 1);
          expect(channels[0], [0, 123, 255, 11]);
        },
      );

      test(
        "2 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0, 123, 255, 11]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 2,
            encoding: PCMDecoderEncoding.unsigned8bits,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0, 255]);
          expect(channels[1], [123, 11]);
        },
      );
      test(
        "3 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 3,
            encoding: PCMDecoderEncoding.unsigned8bits,
          );

          final channels = decoder.decode();

          expect(channels.length, 3);
          expect(channels[0], [0, 3, 6]);
          expect(channels[1], [1, 4, 7]);
          expect(channels[2], [2, 5, 8]);
        },
      );
    },
  );
}

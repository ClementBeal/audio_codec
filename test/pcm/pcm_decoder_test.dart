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

  group(
    "unsigned 16 bits Big-Endian",
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
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x11]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 1,
            encoding: PCMDecoderEncoding.unsigned16bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 1);
          expect(channels[0], [0x0B2A, 0x2311]);
        },
      );

      test(
        "2 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x11]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 2,
            encoding: PCMDecoderEncoding.unsigned16bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x0B2A]);
          expect(channels[1], [0x2311]);
        },
      );

      test(
        "2 channels - lot of data",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x11, 0x01, 0x02, 0x03, 0x04]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 2,
            encoding: PCMDecoderEncoding.unsigned16bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x0B2A, 0x0102]);
          expect(channels[1], [0x2311, 0x0304]);
        },
      );

      test(
        "3 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x11, 0x12, 0x98]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 3,
            encoding: PCMDecoderEncoding.unsigned16bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 3);
          expect(channels[0], [0x0B2A]);
          expect(channels[1], [0x2311]);
          expect(channels[2], [0x1298]);
        },
      );
    },
  );

  group(
    "unsigned 24 bits Big-Endian",
    () {
      tearDown(
        () {
          // File("a.pcm").deleteSync();
        },
      );

      test(
        "1 channel",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0x0B, 0x2A, 0x23]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 1,
            encoding: PCMDecoderEncoding.unsigned24bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 1);
          expect(channels[0], [0x0B2A23]);
        },
      );

      test(
        "2 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x11, 0x54, 0x98]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 2,
            encoding: PCMDecoderEncoding.unsigned24bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x0B2A23]);
          expect(channels[1], [0x115498]);
        },
      );

      test(
        "3 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync(
              [0x0B, 0x2A, 0x23, 0x11, 0x12, 0x98, 0x32, 0x11, 0x84]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 3,
            encoding: PCMDecoderEncoding.unsigned24bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 3);
          expect(channels[0], [0x0B2A23]);
          expect(channels[1], [0x111298]);
          expect(channels[2], [0x321184]);
        },
      );
    },
  );
}

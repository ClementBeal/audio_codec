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
          File("a.pcm").deleteSync();
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

  group(
    "unsigned 32 bits Big-Endian",
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
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x99]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 1,
            encoding: PCMDecoderEncoding.unsigned32bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 1);
          expect(channels[0], [0x0B2A2399]);
        },
      );

      test(
        "2 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x11, 0x54, 0x98, 0xAA, 0xBB]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 2,
            encoding: PCMDecoderEncoding.unsigned32bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x0B2A2311]);
          expect(channels[1], [0x5498AABB]);
        },
      );

      test(
        "3 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([
            0x0B, 0x2A, 0x23, 0x11, //
            0x12, 0x98, 0x32, 0x11, //
            0x04, 0xAA, 0xBB, 0xCC, //
          ]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 3,
            encoding: PCMDecoderEncoding.unsigned32bitsBE,
          );

          final channels = decoder.decode();

          expect(channels.length, 3);
          expect(channels[0], [0x0B2A2311]);
          expect(channels[1], [0x12983211]);
          expect(channels[2], [0x04AABBCC]);
        },
      );
    },
  );

  group(
    "unsigned 16 bits Little-Endian",
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
            encoding: PCMDecoderEncoding.unsigned16bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 1);
          expect(channels[0], [0x2A0B, 0x1123]);
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
            encoding: PCMDecoderEncoding.unsigned16bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x2A0B]);
          expect(channels[1], [0x1123]);
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
            encoding: PCMDecoderEncoding.unsigned16bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x2A0B, 0x0201]);
          expect(channels[1], [0x1123, 0x0403]);
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
            encoding: PCMDecoderEncoding.unsigned16bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 3);
          expect(channels[0], [0x2A0B]);
          expect(channels[1], [0x1123]);
          expect(channels[2], [0x9812]);
        },
      );
    },
  );

  group(
    "unsigned 24 bits Little-Endian",
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
          a.writeAsBytesSync([0x0B, 0x2A, 0x23]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 1,
            encoding: PCMDecoderEncoding.unsigned24bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 1);
          expect(channels[0], [0x232A0B]);
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
            encoding: PCMDecoderEncoding.unsigned24bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x232A0B]);
          expect(channels[1], [0x985411]);
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
            encoding: PCMDecoderEncoding.unsigned24bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 3);
          expect(channels[0], [0x232A0B]);
          expect(channels[1], [0x981211]);
          expect(channels[2], [0x841132]);
        },
      );
    },
  );

  group(
    "unsigned 32 bits Little-Endian",
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
          a.writeAsBytesSync([0x01, 0x0A, 0x23, 0x20]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 1,
            encoding: PCMDecoderEncoding.unsigned32bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 1);
          expect(channels[0], [0x20230A01]);
        },
      );

      test(
        "2 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([0x0B, 0x2A, 0x23, 0x01, 0x54, 0x98, 0xAA, 0x02]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 2,
            encoding: PCMDecoderEncoding.unsigned32bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 2);
          expect(channels[0], [0x01232A0B]);
          expect(channels[1], [0x02AA9854]);
        },
      );

      test(
        "3 channels",
        () {
          final a = File("a.pcm");
          a.writeAsBytesSync([
            0x0B, 0x2A, 0x23, 0x11, //
            0x12, 0x98, 0x32, 0x11, //
            0x04, 0xAA, 0xBB, 0x08, //
          ]);

          final decoder = PcmDecoder(
            track: a,
            sampleRate: 44100,
            nbChannel: 3,
            encoding: PCMDecoderEncoding.unsigned32bitsLE,
          );

          final channels = decoder.decode();

          expect(channels.length, 3);
          expect(channels[0], [0x11232A0B]);
          expect(channels[1], [0x11329812]);
          expect(channels[2], [0x08BBAA04]);
        },
      );
    },
  );
}

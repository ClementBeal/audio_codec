import 'dart:typed_data';

import 'package:audio_codec/src/pcm/pcm_decoder.dart';
import 'package:audio_codec/src/pcm/pcm_encoder.dart';
import 'package:test/test.dart';

void main() {
  group("unsigned 8 bits", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([1, 2, 3, 4])
      ]);

      final result = encoder.encode(PCMEncoding.unsigned8bits);

      expect(result, hasLength(4));
      expect(result, [1, 2, 3, 4]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([1, 3, 5, 7]),
        Int32List.fromList([2, 4, 6, 8]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned8bits);

      expect(result, hasLength(8));
      expect(result, [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([1, 4, 7, 10]),
        Int32List.fromList([2, 5, 8, 11]),
        Int32List.fromList([3, 6, 9, 12]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned8bits);

      expect(result, hasLength(12));
      expect(result, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    });
  });

  group("signed 8 bits", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([-1, 2, 3, 4])
      ]);

      final result = encoder.encode(PCMEncoding.signed8bits);

      expect(result, hasLength(4));
      expect(result, [255, 2, 3, 4]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([1, -2, 5, 7]),
        Int32List.fromList([-1, 4, 6, 8]),
      ]);

      final result = encoder.encode(PCMEncoding.signed8bits);

      expect(result, hasLength(8));
      expect(result, [1, 255, 254, 4, 5, 6, 7, 8]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([1, -2, 7, 10]),
        Int32List.fromList([2, 5, -3, 11]),
        Int32List.fromList([3, 6, 9, -1]),
      ]);

      final result = encoder.encode(PCMEncoding.signed8bits);

      expect(result, hasLength(12));
      expect(result, [1, 2, 3, 254, 5, 6, 7, 253, 9, 10, 11, 255]);
    });
  });

  // Unsigned Big-Endian

  group("unsigned 16 bits Big-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, 0x0304])
      ]);

      final result = encoder.encode(PCMEncoding.unsigned16bitsBE);

      expect(result, hasLength(4));
      expect(result, [0x01, 0x02, 0x03, 0x04]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102]),
        Int32List.fromList([0x0304]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned16bitsBE);

      expect(result, hasLength(4));
      expect(result, [0x01, 0x02, 0x03, 0x04]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0104]),
        Int32List.fromList([0x0205]),
        Int32List.fromList([0x0306]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned16bitsBE);

      expect(result, hasLength(6));
      expect(result, [0x01, 0x04, 0x02, 0x05, 0x03, 0x06]);
    });
  });

  group("unsigned 24 bits Big-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, 0x030405])
      ]);

      final result = encoder.encode(PCMEncoding.unsigned24bitsBE);

      expect(result, hasLength(6));
      expect(result, [0x01, 0x02, 0x03, 0x03, 0x04, 0x05]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203]),
        Int32List.fromList([0x030405]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned24bitsBE);

      expect(result, hasLength(6));
      expect(result, [0x01, 0x02, 0x03, 0x03, 0x04, 0x05]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010409]),
        Int32List.fromList([0x020509]),
        Int32List.fromList([0x030609]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned24bitsBE);

      expect(result, hasLength(9));
      expect(result, [
        0x01, 0x04, 0x09, //
        0x02, 0x05, 0x09, //
        0x03, 0x06, 0x09,
      ]);
    });
  });

  group("unsigned 32  bits Big-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, 0x05060708])
      ]);

      final result = encoder.encode(PCMEncoding.unsigned32bitsBE);

      expect(result, hasLength(8));
      expect(result, [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304]),
        Int32List.fromList([0x05060708]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned32bitsBE);

      expect(result, hasLength(8));
      expect(result, [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304]),
        Int32List.fromList([0x05060708]),
        Int32List.fromList([0x090A0B0C]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned32bitsBE);

      expect(result, hasLength(12));
      expect(result, [
        0x01, 0x02, 0x03, 0x04, //
        0x05, 0x06, 0x07, 0x08, //
        0x09, 0x0A, 0x0B, 0x0C, //
      ]);
    });
  });

  // Unsigned Little-Endian

  group("unsigned 16 bits Little-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, 0x0304])
      ]);

      final result = encoder.encode(PCMEncoding.unsigned16bitsLE);

      expect(result, hasLength(4));
      expect(result, [0x02, 0x01, 0x04, 0x03]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102]),
        Int32List.fromList([0x0304]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned16bitsLE);

      expect(result, hasLength(4));
      expect(result, [0x02, 0x01, 0x04, 0x03]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0104]),
        Int32List.fromList([0x0205]),
        Int32List.fromList([0x0306]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned16bitsLE);

      expect(result, hasLength(6));
      expect(result, [0x04, 0x01, 0x05, 0x02, 0x06, 0x03]);
    });
  });

  group("unsigned 24 bits Little-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, 0x030405])
      ]);

      final result = encoder.encode(PCMEncoding.unsigned24bitsLE);

      expect(result, hasLength(6));
      expect(result, [0x03, 0x02, 0x01, 0x05, 0x04, 0x03]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203]),
        Int32List.fromList([0x030405]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned24bitsLE);

      expect(result, hasLength(6));
      expect(result, [0x03, 0x02, 0x01, 0x05, 0x04, 0x03]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010409]),
        Int32List.fromList([0x020509]),
        Int32List.fromList([0x030609]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned24bitsLE);

      expect(result, hasLength(9));
      expect(result, [
        0x09, 0x04, 0x01, //
        0x09, 0x05, 0x02, //
        0x09, 0x06, 0x03,
      ]);
    });
  });

  group("unsigned 32 bits Little-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, 0x05060708])
      ]);

      final result = encoder.encode(PCMEncoding.unsigned32bitsLE);

      expect(result, hasLength(8));
      expect(result, [0x04, 0x03, 0x02, 0x01, 0x08, 0x07, 0x06, 0x05]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304]),
        Int32List.fromList([0x05060708]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned32bitsLE);

      expect(result, hasLength(8));
      expect(result, [0x04, 0x03, 0x02, 0x01, 0x08, 0x07, 0x06, 0x05]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304]),
        Int32List.fromList([0x05060708]),
        Int32List.fromList([0x090A0B0C]),
      ]);

      final result = encoder.encode(PCMEncoding.unsigned32bitsLE);

      expect(result, hasLength(12));
      expect(result, [
        0x04, 0x03, 0x02, 0x01, //
        0x08, 0x07, 0x06, 0x05, //
        0x0C, 0x0B, 0x0A, 0x09, //
      ]);
    });
  });

  // Signed Big-Endian

  group("signed 16 bits Big-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, 0x0102, 0x0304, 0xE304])
      ]);

      final result = encoder.encode(PCMEncoding.signed16bitsBE);

      expect(result, hasLength(8));
      expect(result, [0x01, 0x02, 0x01, 0x02, 0x03, 0x04, 0xE3, 0x04]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, 0x0102]),
        Int32List.fromList([0x0304, 0x0304]),
      ]);

      final result = encoder.encode(PCMEncoding.signed16bitsBE);

      expect(result, hasLength(8));
      expect(result, [0x01, 0x02, 0x03, 0x04, 0x01, 0x02, 0x03, 0x04]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, 0x0102]),
        Int32List.fromList([0x0304, 0x0304]),
        Int32List.fromList([0x0506, 0x0506]),
      ]);

      final result = encoder.encode(PCMEncoding.signed16bitsBE);

      expect(result, hasLength(12));
      expect(result, [
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, //
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, //
      ]);
    });
  });

  group("signed 24 bits Big-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, -0x040506, 0x070809, -0x0A0B0C])
      ]);

      final result = encoder.encode(PCMEncoding.signed24bitsBE);

      expect(result, hasLength(12));
      expect(result, [
        0x01, 0x02, 0x03, 0xFB, 0xFA, 0xFA, 0x07, 0x08, //
        0x09, 0xF5, 0xF4, 0xF4,
      ]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, -0x040506]),
        Int32List.fromList([0x070809, -0x0A0B0C]),
      ]);

      final result = encoder.encode(PCMEncoding.signed24bitsBE);

      expect(result, hasLength(12));
      expect(result, [
        0x01, 0x02, 0x03, 0x07, 0x08, 0x09, 0xFB, 0xFA, //
        0xFA, 0xF5, 0xF4, 0xF4,
      ]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, -0x040506]),
        Int32List.fromList([0x070809, -0x0A0B0C]),
        Int32List.fromList([0x0D0E0F, -0x101112]),
      ]);

      final result = encoder.encode(PCMEncoding.signed24bitsBE);

      expect(result, hasLength(18));
      expect(result, [
        0x01, 0x02, 0x03, 0x07, 0x08, 0x09, 0x0D, 0x0E, //
        0x0F, 0xFB, 0xFA, 0xFA, 0xF5, 0xF4, 0xF4, 0xEF, //
        0xEE, 0xEE,
      ]);
    });
  });

  group("signed 32 bits Big-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, -0x05060708, 0x090A0B0C, -0x0D0E0F10])
      ]);

      final result = encoder.encode(PCMEncoding.signed32bitsBE);

      expect(result, hasLength(16));
      expect(result, [
        0x01, 0x02, 0x03, 0x04, 0xFA, 0xF9, 0xF8, 0xF8, //
        0x09, 0x0A, 0x0B, 0x0C, 0xF2, 0xF1, 0xF0, 0xF0, //
      ]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, -0x05060708]),
        Int32List.fromList([0x090A0B0C, -0x0D0E0F10]),
      ]);

      final result = encoder.encode(PCMEncoding.signed32bitsBE);

      expect(result, hasLength(16));
      expect(result, [
        0x01, 0x02, 0x03, 0x04, 0x09, 0x0A, 0x0B, 0x0C, //
        0xFA, 0xF9, 0xF8, 0xF8, 0xF2, 0xF1, 0xF0, 0xF0, //
      ]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, -0x05060708]),
        Int32List.fromList([0x090A0B0C, -0x0D0E0F10]),
        Int32List.fromList([0x11121314, -0x15161718]),
      ]);

      final result = encoder.encode(PCMEncoding.signed32bitsBE);

      expect(result, hasLength(24));
      expect(result, [
        0x01, 0x02, 0x03, 0x04, 0x09, 0x0A, 0x0B, 0x0C, //
        0x11, 0x12, 0x13, 0x14, 0xFA, 0xF9, 0xF8, 0xF8, //
        0xF2, 0xF1, 0xF0, 0xF0, 0xEA, 0xE9, 0xE8, 0xE8, //
      ]);
    });
  });

  // Signed Little-Endian

  group("signed 16 bits Little-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, -0x0304, 0x0506, -0x0708])
      ]);

      final result = encoder.encode(PCMEncoding.signed16bitsLE);

      expect(result, hasLength(8));
      expect(result, [0x02, 0x01, 0xFC, 0xFC, 0x06, 0x05, 0xF8, 0xF8]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, -0x0304]),
        Int32List.fromList([0x0506, -0x0708]),
      ]);

      final result = encoder.encode(PCMEncoding.signed16bitsLE);

      expect(result, hasLength(8));
      expect(result, [0x02, 0x01, 0x06, 0x05, 0xFC, 0xFC, 0xF8, 0xF8]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x0102, -0x0304]),
        Int32List.fromList([0x0506, -0x0708]),
        Int32List.fromList([0x090A, -0x0B0C]),
      ]);

      final result = encoder.encode(PCMEncoding.signed16bitsLE);

      expect(result, hasLength(12));
      expect(result, [
        0x02, 0x01, 0x06, 0x05, //
        0x0A, 0x09, 0xFC, 0xFC, //
        0xF8, 0xF8, 0xF4, 0xF4, //
      ]);
    });
  });

  group("signed 24 bits Little-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, -0x040506, 0x070809, -0x0A0B0C])
      ]);

      final result = encoder.encode(PCMEncoding.signed24bitsLE);

      expect(result, hasLength(12));
      expect(result, [
        0x03, 0x02, 0x01, 0xFA, 0xFA, 0xFB, 0x09, 0x08, //
        0x07, 0xF4, 0xF4, 0xF5,
      ]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, -0x040506]),
        Int32List.fromList([0x070809, -0x0A0B0C]),
      ]);

      final result = encoder.encode(PCMEncoding.signed24bitsLE);

      expect(result, hasLength(12));
      expect(result, [
        0x03, 0x02, 0x01, 0x09, 0x08, 0x07, 0xFA, 0xFA, //
        0xFB, 0xF4, 0xF4, 0xF5,
      ]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x010203, -0x040506]),
        Int32List.fromList([0x070809, -0x0A0B0C]),
        Int32List.fromList([0x0D0E0F, -0x101112]),
      ]);

      final result = encoder.encode(PCMEncoding.signed24bitsLE);

      expect(result, hasLength(18));
      expect(result, [
        0x03, 0x02, 0x01, 0x09, 0x08, 0x07, 0x0F, 0x0E, //
        0x0D, 0xFA, 0xFA, 0xFB, 0xF4, 0xF4, 0xF5, 0xEE, //
        0xEE, 0xEF,
      ]);
    });
  });

  group("signed 32 bits Little-Endian", () {
    test("1 channel", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, -0x05060708, 0x090A0B0C, -0x0D0E0F10])
      ]);

      final result = encoder.encode(PCMEncoding.signed32bitsLE);

      expect(result, hasLength(16));
      expect(result, [
        0x04, 0x03, 0x02, 0x01, 0xF8, 0xF8, 0xF9, 0xFA, //
        0x0C, 0x0B, 0x0A, 0x09, 0xF0, 0xF0, 0xF1, 0xF2, //
      ]);
    });

    test("2 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, -0x05060708]),
        Int32List.fromList([0x090A0B0C, -0x0D0E0F10]),
      ]);

      final result = encoder.encode(PCMEncoding.signed32bitsLE);

      expect(result, hasLength(16));
      expect(result, [
        0x04, 0x03, 0x02, 0x01, 0x0C, 0x0B, 0x0A, 0x09, //
        0xF8, 0xF8, 0xF9, 0xFA, 0xF0, 0xF0, 0xF1, 0xF2, //
      ]);
    });

    test("3 channels", () {
      final encoder = PcmEncoder(channels: [
        Int32List.fromList([0x01020304, -0x05060708]),
        Int32List.fromList([0x090A0B0C, -0x0D0E0F10]),
        Int32List.fromList([0x11121314, -0x15161718]),
      ]);

      final result = encoder.encode(PCMEncoding.signed32bitsLE);

      expect(result, hasLength(24));
      expect(result, [
        0x04, 0x03, 0x02, 0x01, 0x0C, 0x0B, 0x0A, 0x09, //
        0x14, 0x13, 0x12, 0x11, 0xF8, 0xF8, 0xF9, 0xFA, //
        0xF0, 0xF0, 0xF1, 0xF2, 0xE8, 0xE8, 0xE9, 0xEA, //
      ]);
    });
  });
}

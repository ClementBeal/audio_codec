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
}

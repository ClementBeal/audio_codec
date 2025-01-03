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
}

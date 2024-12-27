import 'dart:io';

import 'package:audio_codec/src/flac/flac_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    test('Official test 1', () {
      final decoder = FlacDecoder(
        track: File("test/flac/data/official_test_1.flac"),
      );

      final result = decoder.decode();
      final frame = decoder.readFrame();

      expect(frame.subframes.length, 2);

      decoder.close();

      expect(result.streamInfoBlock?.minBlocksize, 0x1000);
      expect(result.streamInfoBlock?.maxBlocksize, 0x1000);
      expect(result.streamInfoBlock?.minFramesize, 0x00000f);
      expect(result.streamInfoBlock?.maxFramesize, 0x00000f);
      expect(result.streamInfoBlock?.sampleRate, 44100);
      expect(result.streamInfoBlock?.channels, 2);
      expect(result.streamInfoBlock?.bitsPerSample, 16);
      expect(result.streamInfoBlock?.totalSamples, 1);
      expect(result.streamInfoBlock?.md5Signature, [
        0x3e,
        0x84,
        0xb4,
        0x18,
        0x07,
        0xdc,
        0x69,
        0x03,
        0x07,
        0x58,
        0x6a,
        0x3d,
        0xad,
        0x1a,
        0x2e,
        0x0f
      ]);

      // test the frame

      expect(frame.hasBlockingStrategy, false);
      expect(frame.blockSize, 1);
      expect(frame.samplerate, 44100);
      expect(frame.channels, AudioChannelLayout.stereo);
      expect(frame.bitdepth, 16);
      expect(frame.codedNumber, 0);
      expect(frame.crc, 0xbf);

      expect(decoder.isCorrect(), true);
    });

    test('Official test 2', () {
      final decoder = FlacDecoder(
        track: File("test/flac/data/official_test_2.flac"),
      );

      final result = decoder.decode();
      final frame = decoder.readFrame();
      decoder.readFrame();

      expect(frame.subframes.length, 2);

      final subframe1 = frame.subframes[0];
      final subframe2 = frame.subframes[1];

      decoder.close();

      expect(result.streamInfoBlock?.minBlocksize, 0x0010);
      expect(result.streamInfoBlock?.maxBlocksize, 0x0010);
      expect(result.streamInfoBlock?.minFramesize, 0x000017);
      expect(result.streamInfoBlock?.maxFramesize, 0x000044);
      expect(result.streamInfoBlock?.sampleRate, 44100);
      expect(result.streamInfoBlock?.channels, 2);
      expect(result.streamInfoBlock?.bitsPerSample, 16);
      expect(result.streamInfoBlock?.totalSamples, 19);
      expect(result.streamInfoBlock?.md5Signature, [
        0xd5,
        0xb0,
        0x56,
        0x49,
        0x75,
        0xe9,
        0x8b,
        0x8d,
        0x8b,
        0x93,
        0x04,
        0x22,
        0x75,
        0x7b,
        0x81,
        0x03,
      ]);

      expect(result.seekpoints.length, 1);
      expect(result.seekpoints[0].sampleNumber, 0);
      expect(result.seekpoints[0].offset, 0);
      expect(result.seekpoints[0].numberOfSamples, 0x0010);

      // test the frame

      expect(frame.hasBlockingStrategy, false);
      expect(frame.blockSize, 16);
      expect(frame.samplerate, 44100);
      expect(frame.channels, AudioChannelLayout.rightSideStereo);
      expect(frame.bitdepth, 16);
      expect(frame.codedNumber, 0);
      expect(frame.crc, 0x99);

      // test the first sub frame

      expect(subframe1, [
        10372,
        18041,
        14942,
        17876,
        15627,
        17899,
        16242,
        18077,
        16824,
        18263,
        17295,
        -14418,
        -15201,
        -14508,
        -15195,
        -14818
      ]);

      // test the second sub frame

      expect(subframe2, [
        6070,
        10545,
        8743,
        10449,
        9143,
        10463,
        9502,
        10569,
        9840,
        10680,
        10113,
        -8428,
        -8895,
        -8476,
        -8896,
        -8653
      ]);

      expect(decoder.isCorrect(), true);
    });

    test('Official test 3', () {
      final decoder = FlacDecoder(
        track: File("test/flac/data/official_test_3.flac"),
      );

      final result = decoder.decode();
      final frame = decoder.readFrame();

      expect(frame.subframes.length, 1);

      final subframe1 = frame.subframes[0];

      decoder.close();

      expect(result.streamInfoBlock?.minBlocksize, 0x1000);
      expect(result.streamInfoBlock?.maxBlocksize, 0x1000);
      expect(result.streamInfoBlock?.minFramesize, 0x00001f);
      expect(result.streamInfoBlock?.maxFramesize, 0x00001f);
      expect(result.streamInfoBlock?.sampleRate, 32000);
      expect(result.streamInfoBlock?.channels, 1);
      expect(result.streamInfoBlock?.bitsPerSample, 8);
      expect(result.streamInfoBlock?.totalSamples, 24);

      // test the frame

      expect(frame.hasBlockingStrategy, false);
      expect(frame.blockSize, 24);
      expect(frame.samplerate, 32000);
      expect(frame.channels, AudioChannelLayout.mono);
      expect(frame.bitdepth, 8);
      expect(frame.codedNumber, 0);
      expect(frame.crc, 0xe9);

      // test the first sub frame

      // expect(subframe1.subframeType, 9);
      // expect(subframe1.isUsingWastedBits, false);
      // expect(subframe1.wastedBits, 0);
      expect(subframe1, [
        0,
        79,
        111,
        78,
        8,
        -61,
        -90,
        -68,
        -13,
        42,
        67,
        53,
        13,
        -27,
        -46,
        -38,
        -12,
        14,
        24,
        19,
        6,
        -4,
        -5,
        0
      ]);

      expect(decoder.isCorrect(), true);
      expect(
          decoder.totalSamples, decoder.result.streamInfoBlock?.totalSamples);
    });
  });
}

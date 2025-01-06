import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/flac/linear_predictor.dart';
import 'package:audio_codec/src/utils/buffer.dart';
import 'package:audio_codec/src/utils/crc/crc8.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import 'package:audio_codec/src/utils/number.dart';

typedef Samples = Int32List;

/// Contains all the metadata information that can be useful
class FlacResult {
  StreamInfo? streamInfoBlock;
  List<Seekpoint> seekpoints = [];

  FlacResult();
}

/// Decode a Flac file by reading it frame by frame.
///
/// To use it :
/// 1. `.decode()` to extract the mandatory metadata
/// 2. `readFrame()` until `.hasNextFrame()` is false
class FlacDecoder {
  final FlacResult result = FlacResult();
  late final RandomAccessFile reader;
  late final Buffer bufferedFile;

  final output = AccumulatorSink<Digest>();
  late final md5Input = md5.startChunkedConversion(output);
  int totalSamples = 0;

  FlacDecoder({required File track}) {
    reader = track.openSync();
    bufferedFile = Buffer(randomAccessFile: reader);
  }

  FlacResult decode() {
    if (!isFlac()) {
      throw Exception("Not a Flac file");
    }

    FlacBlock currentBlock;

    do {
      currentBlock = _readBlock();

      if (currentBlock.blockType == 0) {
        result.streamInfoBlock = _readStreamInfoBlock();
      } else if (currentBlock.blockType == 3) {
        result.seekpoints = readSeektableBlock(currentBlock.length);
      } else {
        bufferedFile.skip(currentBlock.length);
      }
    } while (!currentBlock.isLast);

    return result;
  }

  List<Samples> decodeAll() {
    final channels = List.generate(
      result.streamInfoBlock!.channels,
      (index) => Int32List(result.streamInfoBlock!.totalSamples),
      growable: false,
    );

    int sampleIndex = 0; // Use sampleIndex to track the total samples written

    while (hasNextFrame()) {
      final frame = readFrame();

      for (var i = 0; i < frame.subframes.length; i++) {
        final subframe = frame.subframes[i];

        // for (var j = 0; j < subframe.length; j++) {
        channels[i]
            .setRange(sampleIndex, sampleIndex + frame.blockSize, subframe);
        // }
      }

      sampleIndex += frame.blockSize;
    }

    return channels;
  }

  /// Close the [reader] when the decoding is done
  void close() {
    reader.closeSync();
  }

  /// A Flac file must start with the magic word "fLaC"
  bool isFlac() {
    return String.fromCharCodes(bufferedFile.read(4)) == "fLaC";
  }

  /// Read a metadata block
  /// In Flac, we can have up to 128 different type of metadata block
  /// According to the documentation, only a handfull of types are defined.
  /// `Streaminfo` (type 0) must be the first metadatablock
  ///
  /// If the block is the last metadata block, the first bit is set to 1
  FlacBlock _readBlock() {
    final headerBytes = bufferedFile.read(4);

    return FlacBlock(
      isLast: ((headerBytes[0] >> 7) & 0x1) == 1, // Bit 7
      blockType: (headerBytes[0] & 0x7F), // Bit 6-0
      length: (headerBytes[1] << 16) | (headerBytes[2] << 8) | (headerBytes[3]),
    );
  }

  StreamInfo _readStreamInfoBlock() {
    // Read fields in order
    final minBlocksizeBytes = bufferedFile.read(2);
    final maxBlocksizeBytes = bufferedFile.read(2);
    final minFramesizeBytes = bufferedFile.read(3);
    final maxFramesizeBytes = bufferedFile.read(3);

    // Read and parse the 8-byte packed field
    // AAAAAAAA AAAAAAAA
    // AAAABBBC CCCCDDDD
    // DDDDDDDD DDDDDDDD
    // DDDDDDDD DDDDDDDD
    // A -> sample rate (20 bits)
    // B -> channels (3 bits)
    // C -> bit per sample (5 bits)
    // D -> total samples in stream (36 bits)
    // Total -> 8 bytes
    final packedBytes = bufferedFile.read(8);

    // Extract individual fields from packedBytes
    final sampleRate = (packedBytes[0] << 12) |
        (packedBytes[1] << 4) |
        ((packedBytes[2] >> 4) & 0x0F);

    final channels = ((packedBytes[2] >> 1) & 0x07) + 1;
    final bitsPerSample =
        (((packedBytes[2] & 0x01) << 4) | ((packedBytes[3] >> 4) & 0x0F)) + 1;

    final totalSamples = ((packedBytes[3] & 0x0F) << 32) |
        (packedBytes[4] << 24) |
        (packedBytes[5] << 16) |
        (packedBytes[6] << 8) |
        (packedBytes[7]);

    final md5Signature = bufferedFile.read(16);

    return StreamInfo(
      minBlocksize: (minBlocksizeBytes[0] << 8) | minBlocksizeBytes[1],
      maxBlocksize: (maxBlocksizeBytes[0] << 8) | maxBlocksizeBytes[1],
      minFramesize: (minFramesizeBytes[0] << 16) |
          (minFramesizeBytes[1] << 8) |
          minFramesizeBytes[2],
      maxFramesize: (maxFramesizeBytes[0] << 16) |
          (maxFramesizeBytes[1] << 8) |
          maxFramesizeBytes[2],
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      totalSamples: totalSamples,
      md5Signature: md5Signature,
    );
  }

  List<Seekpoint> readSeektableBlock(int length) {
    int totalSeekpoints = length ~/ 18;

    final seekPoints = <Seekpoint>[];

    for (var i = 0; i < totalSeekpoints; i++) {
      final buffer = Uint8List.fromList(bufferedFile.read(8 + 8 + 2));

      final a = ByteData.view(buffer.buffer).getUint64(0);
      final b = ByteData.view(buffer.buffer).getUint64(8);
      final c = ByteData.view(buffer.buffer).getUint16(16);

      seekPoints.add(Seekpoint(sampleNumber: a, offset: b, numberOfSamples: c));
    }

    return seekPoints;
  }

  FlacFrame readFrame() {
    final bytes = <int>[];

    // 15 first bits -> sync word (0b1111 1111 1111 00)
    final firstPackage = bufferedFile.read(2);
    bytes.addAll(firstPackage);

    final syncWord = (firstPackage[0] << 8 | firstPackage[1]);

    if (syncWord != 0xFFF8 && syncWord != 0xFFF9) {
      throw Exception(
          "Frame sync word is wrong (${syncWord.toRadixString(16)} != ${0xFFF8.toRadixString(16)})");
    }

    final bitIsReserved = (firstPackage[1] >> 1 & 0x1) == 0;
    final blockingStrategy = (firstPackage[1] & 0x1) == 1;

    final secondPackage = bufferedFile.read(1)[0];
    bytes.add(secondPackage);

    int blockSizeInInterChannelSamples = _decodeBlockSize(secondPackage >> 4);
    final sampleRate = _decodeSampleRateBit(secondPackage & 0x0F) ?? -1;

    final thirdPackage = bufferedFile.read(1)[0];
    bytes.add(thirdPackage);

    final channelAssignment = _decodeChannel(thirdPackage >> 4);
    final bitDepth = _decodeBitDepth((thirdPackage >> 1) & 0x07);
    // reserved and must be 0
    if (thirdPackage & 0x1 != 0) {
      throw Exception("Reversed bit after bit depth is not set to 0");
    }

    // sample or a frame number
    // it depends if it's a blocking strategy or not
    final (codedValue, codedValueBytes) = _decodeCodedNumber();
    bytes.addAll(codedValueBytes);

    // if the block size is undefined, we take the 8/16 bits after the coded value
    if (blockSizeInInterChannelSamples < 0) {
      if (secondPackage >> 4 == 6) {
        final blockSize = bufferedFile.read(1)[0];
        blockSizeInInterChannelSamples = blockSize + 1;
        bytes.add(blockSize);
      } else {
        final blockSize = bufferedFile.read(2);
        blockSizeInInterChannelSamples = blockSize[0] << 8 | blockSize[1] + 1;
        bytes.addAll(blockSize);
      }
    }

    final calculatedCRC = calculateCRC8(bytes);
    final crc = bufferedFile.read(1)[0];
    bytes.add(crc);

    if (crc != calculatedCRC) {
      throw Exception(
          "The checksum of the frame header is not equal to the computed one ($crc != $calculatedCRC)");
    }

    List<Samples> subframes = [
      for (int i = 0; i < channelAssignment.nbChannels; i++)
        _readSubframe(bufferedFile, blockSizeInInterChannelSamples, bitDepth,
            _isSideChannel(i, channelAssignment))
    ];

    if (channelAssignment == AudioChannelLayout.rightSideStereo) {
      decorrelateRightSide(subframes[1], subframes[0]);
    } else if (channelAssignment == AudioChannelLayout.midSideStereo) {
      decorrelateMidSide(subframes[0], subframes[1]);
    } else if (channelAssignment == AudioChannelLayout.leftSideStereo) {
      decorrelateLeftSide(subframes[0], subframes[1]);
    }

    _addToMd5(subframes, bitDepth);

    totalSamples += subframes.first.length;

    bufferedFile.align();

    final frameCRCBytes = bufferedFile.read(2);

    // ignore: unused_local_variable
    final frameCRC = frameCRCBytes[0] << 8 | frameCRCBytes[1];
    // ignore: unused_local_variable
    final calculatedFrameCRC = _calculateCRC16(bytes);

    // if (frameCRC != calculatedFrameCRC) {
    //   throw Exception(
    //       "Frame CRC is different of the computed one ($frameCRC != $calculatedFrameCRC)");
    // }

    return FlacFrame(
      hasBitReserved: bitIsReserved,
      hasBlockingStrategy: blockingStrategy,
      blockSize: blockSizeInInterChannelSamples,
      samplerate: sampleRate,
      bitdepth: bitDepth,
      channels: channelAssignment,
      codedNumber: codedValue,
      crc: crc,
      subframes: subframes,
    );
  }

  Future<void> _addToMd5(List<Samples> subframes, int bitDepth) async {
    // 1. Pre-allocate a buffer for a frame's worth of data
    final frameSize =
        subframes.first.length * subframes.length * (bitDepth ~/ 8);
    final frameBuffer = Uint8List(frameSize);
    final byteData = ByteData.view(frameBuffer.buffer);

    int offset = 0;
    for (var i = 0; i < subframes.first.length; i++) {
      for (var j = 0; j < subframes.length; j++) {
        final sample = subframes[j][i];

        // 2. Optimized sample conversion based on bit depth
        if (bitDepth == 16) {
          byteData.setInt16(offset, sample, Endian.little);
          offset += 2;
        } else if (bitDepth == 24) {
          // Assuming your toBytes() handles 24-bit by padding to 32-bit
          byteData.setInt32(offset, sample, Endian.little);
          offset += 3;
        } else if (bitDepth == 8) {
          byteData.setInt8(offset, sample);
          offset += 1;
        } else if (bitDepth == 32) {
          byteData.setInt32(offset, sample, Endian.little);
          offset += 4;
        } else {
          throw Exception("Unsupported bit depth: $bitDepth");
        }
      }
    }

    // 3. Add the entire frame's data to the MD5 input in one go
    md5Input.add(frameBuffer); // Update the digest directly
  }

  /// Check that the decoded samples are correct. We compare the MD5 checksum from the
  /// block Streaminfo with the MD5 checksum of every samples
  bool isCorrect() {
    md5Input.close();

    return areListsEqual(
        result.streamInfoBlock?.md5Signature, output.events.single.bytes);
  }

  bool _isSideChannel(int idSubframe, AudioChannelLayout channel) {
    return switch (channel) {
      AudioChannelLayout.leftSideStereo => idSubframe == 1,
      AudioChannelLayout.rightSideStereo => idSubframe == 0,
      AudioChannelLayout.midSideStereo => idSubframe == 1,
      _ => false,
    };
  }

  Samples _readSubframe(
      Buffer bitReader, int blockSize, int bitdepth, bool isSideChannel) {
    if (bitReader.readBit() == 1) {
      throw Exception("The first bit of a subframe must be set to 0");
    }

    // we want 0xXAAA AAAX
    final subframeType = bitReader.readUnsigned(6);

    final useWastedBits = bitReader.readBit() == 1;

    int wastedBits = 0;
    final samples = Samples(blockSize);

    if (useWastedBits) {
      wastedBits = 1;
      while (bitReader.readBit() == 0) {
        wastedBits++;
      }
    }

    final effectiveBitdepth = bitdepth - wastedBits + (isSideChannel ? 1 : 0);

    if (subframeType == 0) {
      _subframeConstant(
          bitReader, effectiveBitdepth, wastedBits, blockSize, samples);
    } else if (subframeType == 1) {
      _subframeVerbatim(
          bitReader, effectiveBitdepth, wastedBits, blockSize, samples);
    } else if (subframeType >= 8 && subframeType <= 12) {
      _subframeFixed(bitReader, effectiveBitdepth, wastedBits, blockSize,
          samples, subframeType);
    } else if (subframeType >= 32 && subframeType <= 63) {
      _subframeLinear(bitReader, effectiveBitdepth, wastedBits, blockSize,
          samples, subframeType);
    } else {
      throw Exception("Unsupported subframe type: $subframeType");
    }

    return samples;
  }

  void _subframeConstant(Buffer bitReader, int effectiveBitdepth,
      int wastedBits, int blockSize, Samples samples) {
    final sample = bitReader.readSigned(effectiveBitdepth) << wastedBits;

    for (var i = 0; i < blockSize; i++) {
      samples[i] = sample;
    }
  }

  void _subframeVerbatim(Buffer bitReader, int effectiveBitdepth,
      int wastedBits, int blockSize, Samples samples) {
    for (var i = 0; i < blockSize; i++) {
      samples[i] = bitReader.readSigned(effectiveBitdepth) << wastedBits;
    }
  }

  void _subframeFixed(Buffer bitReader, int effectiveBitdepth, int wastedBits,
      int blockSize, Samples samples, int subframeOrder) {
    final order = subframeOrder - 8;

    _subframeVerbatim(bitReader, effectiveBitdepth, wastedBits, order, samples);

    final residualSampleValues = _decodeRiceCode(bitReader, blockSize, order);

    switch (order) {
      case 0:
        for (var i = order; i < blockSize; i++) {
          samples[i] = residualSampleValues[i - order];
        }
        break;
      case 1:
        for (var i = order; i < blockSize; i++) {
          samples[i] = samples[i - 1] + residualSampleValues[i - order];
        }
        break;
      case 2:
        for (var i = order; i < blockSize; i++) {
          samples[i] = 2 * samples[i - 1] -
              samples[i - 2] +
              residualSampleValues[i - order];
        }
        break;
      case 3:
        for (var i = order; i < blockSize; i++) {
          samples[i] = 3 * samples[i - 1] -
              3 * samples[i - 2] +
              samples[i - 3] +
              residualSampleValues[i - order];
        }
        break;
      case 4:
        for (var i = order; i < blockSize; i++) {
          samples[i] = 4 * samples[i - 1] -
              6 * samples[i - 2] +
              4 * samples[i - 3] -
              samples[i - 4] +
              residualSampleValues[i - order];
        }
        break;
    }
  }

  void _subframeLinear(
    Buffer bitReader,
    int effectiveBitdepth,
    int wastedBits,
    int blockSize,
    Samples samples,
    int subframeType,
  ) {
    // we have to use [linearPredictorOrder] previous samples
    final linearPredictorOrder = subframeType - 31;

    _subframeVerbatim(bitReader, effectiveBitdepth, wastedBits,
        linearPredictorOrder, samples);

    final coefficientPrecision = bitReader.readUnsigned(4) + 1;
    final rightShiftNeeded = bitReader.readSigned(5);

    final coefficients = Samples(linearPredictorOrder);

    for (int i = 0; i < linearPredictorOrder; i++) {
      coefficients[i] = bitReader.readSigned(coefficientPrecision);
    }

    final residuals =
        _decodeRiceCode(bitReader, blockSize, linearPredictorOrder);

    computeLinearPredictor(linearPredictorOrder, blockSize, samples,
        coefficients, rightShiftNeeded, residuals);
  }

  Samples _decodeRiceCode(Buffer bitReader, int blockSize, int predictorOrder) {
    final nbResidualValues = blockSize - predictorOrder;
    final riceCodeValue = bitReader.readUnsigned(2);

    int bitToRead = switch (riceCodeValue) {
      0 => 4,
      1 => 5,
      _ => throw Exception("Rice code not autorised : $riceCodeValue"),
    };

    final partitionOrder = bitReader.readUnsigned(4);

    final totalPartitions = 1 << partitionOrder;

    final residualSampleValues = Samples(nbResidualValues);
    int residualId = 0;

    for (int actualPartition = 0;
        actualPartition < totalPartitions;
        actualPartition++) {
      final totalElementsInPartition = (actualPartition == 0)
          ? (blockSize >> partitionOrder) - predictorOrder
          : (blockSize >> partitionOrder);

      final riceParameter = bitReader.readUnsigned(bitToRead);
      bool hasEscaped =
          (riceCodeValue == 0) ? riceParameter == 15 : riceParameter == 31;

      if (hasEscaped) {
        bitReader.readUnsigned(5);
      }

      for (int i = 0; i < totalElementsInPartition; i++) {
        if (hasEscaped) {
          residualSampleValues[residualId++] = bitReader.readSigned(5);
        } else {
          int quotient = 0;

          // Decode the quotient (unary part)
          while (bitReader.readBit() == 0) {
            quotient++;
          }

          int residualSampleValue;
          if (riceParameter == 0) {
            // When Rice parameter is 0, only the quotient determines the value
            residualSampleValue = quotient;
          } else {
            // Decode the remainder if Rice parameter > 0
            final remainder = bitReader.readUnsigned(riceParameter);
            residualSampleValue = (quotient << riceParameter) | remainder;
          }

          // The value is coded:
          // positive -> X * 2
          // negative -> (-2) * X -1
          residualSampleValue = (residualSampleValue & 1 == 0)
              ? (residualSampleValue >> 1)
              : -((residualSampleValue + 1) >> 1);

          residualSampleValues[residualId++] = residualSampleValue;
        }
      }
    }

    return residualSampleValues;
  }

  int _calculateCRC16(List<int> data) {
    int crc = 0; // Initial value

    for (int byte in data) {
      crc ^= (byte << 8); // XOR byte into the high byte of CRC
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^
              0x1021; // Apply polynomial 0x1021 (x^16 + x^12 + x^5 + 1)
        } else {
          crc <<= 1;
        }
      }
    }

    return crc & 0xFFFF; // Ensure 16-bit result
  }

  (int, List<int>) _decodeCodedNumber() {
    int firstByte = bufferedFile.read(1)[0];

    if ((firstByte & 0x80) == 0) {
      // Single-byte value
      return (firstByte, [firstByte]);
    }

    int numberOfContinuationBytes = 0;
    if ((firstByte & 0xFE) == 0xFC) {
      numberOfContinuationBytes = 5;
    } else if ((firstByte & 0xFC) == 0xF8) {
      numberOfContinuationBytes = 4;
    } else if ((firstByte & 0xF8) == 0xF0) {
      numberOfContinuationBytes = 3;
    } else if ((firstByte & 0xF0) == 0xE0) {
      numberOfContinuationBytes = 2;
    } else if ((firstByte & 0xE0) == 0xC0) {
      numberOfContinuationBytes = 1;
    } else {
      throw Exception("Bad decoded number");
    }

    // Corrected masking:
    int value = firstByte & (0x3F >> (numberOfContinuationBytes));
    final readBytes = <int>[firstByte];

    for (int i = 0; i < numberOfContinuationBytes; i++) {
      int continuationByte = bufferedFile.read(1)[0];
      readBytes.add(continuationByte);
      if ((continuationByte & 0xC0) != 0x80) {
        throw Exception("Bad decoded number");
      }
      value = (value << 6) | (continuationByte & 0x3F);
    }

    return (value, readBytes);
  }

  int _decodeBlockSize(int value) {
    if (value < 0 || value > 0xF) {
      throw Exception(
          "Block size value should be between 0 and 15 (4 bits). Current value : $value");
    }

    return switch (value) {
      // reserved
      0 => throw Exception(
          "This block size value is reserved. 0b000 can't be used."),
      1 => 192,
      // original formula => 144 * (2^value)
      2 || 3 || 4 || 5 => 576 << (value - 2),
      6 => -1,
      7 => -1,
      // original formula => 2^value
      _ => 256 << (value - 8),
    };
  }

  int? _decodeSampleRateBit(int value) {
    return switch (value) {
      0 => null,
      1 => 88200,
      2 => 176400,
      3 => 192000,
      4 => 8000,
      5 => 16000,
      6 => 22050,
      7 => 24000,
      8 => 32000,
      9 => 44100,
      10 => 48000,
      11 => 96000,
      _ => throw Exception("Sample rate is not implemented yet")
    };
  }

  AudioChannelLayout _decodeChannel(int value) {
    if (value < 0 || value > 0xF) {
      throw Exception(
          "Channel value should be between 0 and 15 (4 bits). Current value: $value");
    }

    return switch (value) {
      0 => AudioChannelLayout.mono,
      1 => AudioChannelLayout.stereo,
      2 => AudioChannelLayout.threeChannels,
      3 => AudioChannelLayout.quad,
      4 => AudioChannelLayout.fiveChannels,
      5 => AudioChannelLayout.sixChannels,
      6 => AudioChannelLayout.sevenChannels,
      7 => AudioChannelLayout.eightChannels,
      8 => AudioChannelLayout.leftSideStereo,
      9 => AudioChannelLayout.rightSideStereo,
      10 => AudioChannelLayout.midSideStereo,
      _ => throw Exception("This channel value is reserved."),
    };
  }

  int _decodeBitDepth(int value) {
    if (value < 0 || value > 7) {
      throw Exception(
          "Bit depth value should be between 0 and 7 (3 bits). Current value : $value");
    }

    return switch (value) {
      0 => result.streamInfoBlock!.bitsPerSample,
      1 => 8,
      2 => 12,
      3 => throw Exception("Bit depth value is reserved (0b011)"),
      4 => 16,
      5 => 20,
      6 => 24,
      7 => 32,
      _ => throw Exception(
          "Bit depth value should be between 0 and 7 (3 bits). Current value : $value"),
    };
  }

  /// Return true if another frame can be decoded
  bool hasNextFrame() {
    return totalSamples < result.streamInfoBlock!.totalSamples;
  }
}

/// Contains the header of a metadata block
class FlacBlock {
  final bool isLast;
  final int blockType;
  final int length;

  FlacBlock(
      {required this.isLast, required this.blockType, required this.length});
}

/// Contains the data of the StreamInfo metadata block
class StreamInfo {
  final int minBlocksize;
  final int maxBlocksize;
  final int minFramesize;
  final int maxFramesize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int totalSamples;
  final Uint8List md5Signature;

  StreamInfo({
    required this.minBlocksize,
    required this.maxBlocksize,
    required this.minFramesize,
    required this.maxFramesize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.totalSamples,
    required this.md5Signature,
  });

  @override
  String toString() {
    return 'StreamInfo{'
        'minBlocksize: $minBlocksize,\n '
        'maxBlocksize: $maxBlocksize,\n '
        'minFramesize: $minFramesize,\n '
        'maxFramesize: $maxFramesize,\n '
        'sampleRate: $sampleRate,\n '
        'channels: $channels,\n '
        'bitsPerSample: $bitsPerSample,\n '
        'totalSamples: $totalSamples,\n '
        'md5Signature: $md5Signature\n'
        '}';
  }
}

class Seekpoint {
  final int sampleNumber;
  final int? offset;
  final int? numberOfSamples;

  Seekpoint(
      {required this.sampleNumber,
      required this.offset,
      required this.numberOfSamples});
}

/// A Flac file can have 4 different types of channels :
/// Independant : can have between 1 and 8 channels
/// Left-Side : the right channel is calculated by doing left - side
/// Right-Side : the left channel is calculated by doing side + right
/// Mid-Side : the left and right are retreived by doing more complex computation
enum AudioChannelLayout {
  mono(1),
  stereo(2),
  threeChannels(3),
  quad(4),
  fiveChannels(5),
  sixChannels(6),
  sevenChannels(7),
  eightChannels(8),
  leftSideStereo(2),
  rightSideStereo(2),
  midSideStereo(2),
  reserved(-1);

  final int nbChannels;

  const AudioChannelLayout(this.nbChannels);
}

/// Contains the data of the frame.
/// Header and subframes
class FlacFrame {
  final bool hasBitReserved;
  final bool hasBlockingStrategy;
  final int blockSize;
  final int samplerate;
  final int bitdepth;
  final AudioChannelLayout channels;
  final int codedNumber;
  final int crc;
  final List<Samples> subframes;

  FlacFrame({
    required this.hasBitReserved,
    required this.hasBlockingStrategy,
    required this.blockSize,
    required this.samplerate,
    required this.bitdepth,
    required this.channels,
    required this.codedNumber,
    required this.crc,
    required this.subframes,
  });
}

void decorrelateRightSide(Samples rightChannel, Samples sideChannel) {
  for (int i = 0; i < rightChannel.length; i++) {
    sideChannel[i] = rightChannel[i] + sideChannel[i]; // L = R + S
  }
}

void decorrelateLeftSide(Samples leftChannel, Samples sideChannel) {
  for (int i = 0; i < leftChannel.length; i++) {
    sideChannel[i] -= leftChannel[i]; // R = S - L
  }
}

void decorrelateMidSide(Samples midChannel, Samples sideChannel) {
  for (var i = 0; i < midChannel.length; i++) {
    final m = midChannel[i];
    final s = sideChannel[i];
    final l = (m + s) >> 2;
    final r = l + s;
    midChannel[i] = l;
    sideChannel[i] = r;
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class WavEncoder {
  final int sampleRate;
  final int numChannels;
  final int bitDepth;

  WavEncoder({
    required this.sampleRate,
    required this.numChannels,
    required this.bitDepth,
  }) {
    if (bitDepth % 8 != 0) {
      throw ArgumentError('Bit depth must be a multiple of 8');
    }
  }

  void encode(File file, List<int> samples) {
    final writer = file.openSync(mode: FileMode.writeOnly);

    _writeHeader(writer);
    _writeFmtChunk(writer);
    _writeDataChunk(writer, samples);

    // Update the file size and data chunk size
    _updateHeaderAndChunkSizes(writer, samples);

    writer.closeSync();
  }

  void _writeHeader(RandomAccessFile writer) {
    writer.writeStringSync("RIFF", encoding: ascii);
    writer.writeFromSync([0, 0, 0, 0]); // Placeholder for file size
    writer.writeStringSync("WAVE", encoding: ascii);
  }

  void _writeFmtChunk(RandomAccessFile writer) {
    writer.writeStringSync("fmt ", encoding: ascii);

    // TODO : I didn't find why the chunk size is 16. What does it mean?
    writer.writeFromSync(_intToLittleEndian(16, 4)); // Chunk size
    writer.writeFromSync(_intToLittleEndian(1, 2)); // Audio format (PCM)
    writer.writeFromSync(_intToLittleEndian(numChannels, 2));
    writer.writeFromSync(_intToLittleEndian(sampleRate, 4));
    final byteRate = sampleRate * numChannels * (bitDepth ~/ 8);
    writer.writeFromSync(_intToLittleEndian(byteRate, 4));
    final blockAlign = numChannels * (bitDepth ~/ 8);
    writer.writeFromSync(_intToLittleEndian(blockAlign, 2));
    writer.writeFromSync(_intToLittleEndian(bitDepth, 2));
  }

  void _writeDataChunk(RandomAccessFile writer, List<int> samples) {
    writer.writeStringSync("data", encoding: ascii);
    writer.writeFromSync([0, 0, 0, 0]); // Placeholder for data size

    final bytesPerSample = bitDepth ~/ 8;

    final samplesData = <int>[];

    for (final sample in samples) {
      // Handle bit depth and clipping
      int clippedSample = _clipSample(sample, bitDepth);

      // Write sample data in little-endian format
      for (int i = 0; i < bytesPerSample; i++) {
        samplesData.add((clippedSample >> (i * 8)) & 0xFF);
      }
    }

    writer.writeFromSync(samplesData);
  }

  void _updateHeaderAndChunkSizes(RandomAccessFile writer, List<int> samples) {
    final fileSize = writer.lengthSync();
    final dataSize = samples.length * (bitDepth ~/ 8);

    writer.setPositionSync(4); // RIFF chunk size
    writer.writeFromSync(_intToLittleEndian(fileSize - 8, 4));

    writer.setPositionSync(40); // data chunk size
    writer.writeFromSync(_intToLittleEndian(dataSize, 4));
  }

  Uint8List _intToLittleEndian(int value, int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    return bytes;
  }

  int _clipSample(int sample, int bitDepth) {
    if (bitDepth == 8) {
      // 8-bit samples are unsigned
      if (sample < 0) return 0;
      if (sample > 255) return 255;
      return sample;
    } else {
      // Other bit depths are signed
      final minVal = -(1 << (bitDepth - 1));
      final maxVal = (1 << (bitDepth - 1)) - 1;
      if (sample < minVal) return minVal;
      if (sample > maxVal) return maxVal;
      return sample;
    }
  }
}

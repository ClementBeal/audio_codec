import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class WavEncoder {
  final int sampleRate;
  final int numChannels;
  final int bitDepth;
  final int _bytesPerSample;
  final int _blockAlign;
  final int _byteRate;

  // Pre-calculate constants in constructor
  WavEncoder({
    required this.sampleRate,
    required this.numChannels,
    required this.bitDepth,
  })  : _bytesPerSample = bitDepth ~/ 8,
        _blockAlign = (bitDepth ~/ 8) * numChannels,
        _byteRate = sampleRate * numChannels * (bitDepth ~/ 8) {
    if (bitDepth % 8 != 0) {
      throw ArgumentError('Bit depth must be a multiple of 8');
    }
  }

  static const _riffHeader = [82, 73, 70, 70]; // "RIFF" in ASCII
  static const _waveHeader = [87, 65, 86, 69]; // "WAVE" in ASCII
  static const _fmtHeader = [102, 109, 116, 32]; // "fmt_" in ASCII
  static const _dataHeader = [100, 97, 116, 97]; // "data" in ASCII
  static const _fmtChunkSize = 16;
  static const _pcmAudioFormat = 1;

  void encode(File file, List<int> samples) {
    final writer = file.openSync(mode: FileMode.writeOnly);
    final dataSize = samples.length * _bytesPerSample;
    final fileSize = 44 + dataSize; // Total size = header (44 bytes) + data

    // Write all headers in one go
    _writeHeaders(writer, fileSize - 8, dataSize);

    // Process and write samples more efficiently
    _writeOptimizedData(writer, samples);

    writer.closeSync();
  }

  void _writeHeaders(RandomAccessFile writer, int fileSize, int dataSize) {
    // Create a single buffer for all headers
    final headerBuffer = Uint8List(44);
    var offset = 0;

    // RIFF header
    headerBuffer.setAll(offset, _riffHeader);
    offset += 4;
    headerBuffer.setAll(offset, _intToLittleEndian(fileSize, 4));
    offset += 4;
    headerBuffer.setAll(offset, _waveHeader);
    offset += 4;

    // fmt chunk
    headerBuffer.setAll(offset, _fmtHeader);
    offset += 4;
    headerBuffer.setAll(offset, _intToLittleEndian(_fmtChunkSize, 4));
    offset += 4;
    headerBuffer.setAll(offset, _intToLittleEndian(_pcmAudioFormat, 2));
    offset += 2;
    headerBuffer.setAll(offset, _intToLittleEndian(numChannels, 2));
    offset += 2;
    headerBuffer.setAll(offset, _intToLittleEndian(sampleRate, 4));
    offset += 4;
    headerBuffer.setAll(offset, _intToLittleEndian(_byteRate, 4));
    offset += 4;
    headerBuffer.setAll(offset, _intToLittleEndian(_blockAlign, 2));
    offset += 2;
    headerBuffer.setAll(offset, _intToLittleEndian(bitDepth, 2));
    offset += 2;

    // data chunk header
    headerBuffer.setAll(offset, _dataHeader);
    offset += 4;
    headerBuffer.setAll(offset, _intToLittleEndian(dataSize, 4));

    // Write entire header at once
    writer.writeFromSync(headerBuffer);
  }

  void _writeOptimizedData(RandomAccessFile writer, List<int> samples) {
    if (_bytesPerSample == 1) {
      writer.writeFromSync(Uint8ClampedList.fromList(samples));
      return;
    }

    // For other bit depths, use a pre-allocated buffer
    final bufferSize = samples.length * _bytesPerSample;
    final buffer = Uint8List(bufferSize);
    final minVal = -(1 << (bitDepth - 1));
    final maxVal = (1 << (bitDepth - 1)) - 1;

    var bufferIndex = 0;
    for (final sample in samples) {
      // Inline sample clipping
      final clippedSample =
          sample < minVal ? minVal : (sample > maxVal ? maxVal : sample);

      // Unroll the byte writing loop
      for (var i = 0; i < _bytesPerSample; i++) {
        buffer[bufferIndex++] = (clippedSample >> (i * 8)) & 0xFF;
      }
    }

    writer.writeFromSync(buffer);
  }

  Uint8List _intToLittleEndian(int value, int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    return bytes;
  }
}

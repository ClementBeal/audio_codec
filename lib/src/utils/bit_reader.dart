import 'package:audio_codec/src/utils/buffer.dart';

class BitReader {
  final Buffer _file;
  int _bitBuffer = 0;
  int _bitCount = 0;

  BitReader(this._file);

  /// Reads [bitCount] bits and returns an unsigned integer.
  int readUnsigned(int bitCount) {
    if (bitCount < 1 || bitCount > 32) {
      throw ArgumentError('bitCount must be between 1 and 32');
    }

    _fillBuffer(bitCount);

    final int value = _bitBuffer >> (_bitCount - bitCount);
    _bitBuffer &= (1 << (_bitCount - bitCount)) - 1;
    _bitCount -= bitCount;
    return value;
  }

  /// Reads [bitCount] bits and returns a signed integer.
  int readSigned(int bitCount) {
    if (bitCount < 1 || bitCount > 32) {
      throw ArgumentError('bitCount must be between 1 and 32');
    }

    final int unsigned = readUnsigned(bitCount);
    final int signBit = 1 << (bitCount - 1);
    return (unsigned & signBit) != 0 ? unsigned - (1 << bitCount) : unsigned;
  }

  /// Ensures the buffer has at least [bitCount] bits available.
  void _fillBuffer(int bitCount) {
    while (_bitCount < bitCount) {
      final int nextByte = _file.read(1)[0];
      _bitBuffer = (_bitBuffer << 8) | nextByte;
      _bitCount += 8;
    }
  }
}

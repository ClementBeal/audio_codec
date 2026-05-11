import 'dart:typed_data';

/// Helper to write bit-level fields into a byte buffer.
class BitWriter {
  final BytesBuilder _bytes;
  int _currentByte = 0;
  int _nextBitIndex = 7;

  BitWriter(this._bytes);

  void writeBits(int value, int bitCount) {
    for (int i = bitCount - 1; i >= 0; i--) {
      final bit = (value >> i) & 0x1;
      _currentByte |= bit << _nextBitIndex;
      _nextBitIndex--;

      if (_nextBitIndex < 0) {
        _bytes.addByte(_currentByte & 0xFF);
        _currentByte = 0;
        _nextBitIndex = 7;
      }
    }
  }

  void writeSigned(int value, int bitCount) {
    final mask = (1 << bitCount) - 1;
    writeBits(value & mask, bitCount);
  }

  void writeUnaryZeroCount(int zeroCount) {
    for (int i = 0; i < zeroCount; i++) {
      writeBits(0, 1);
    }
    writeBits(1, 1);
  }

  void alignToByte() {
    if (_nextBitIndex == 7) {
      return;
    }

    _bytes.addByte(_currentByte & 0xFF);
    _currentByte = 0;
    _nextBitIndex = 7;
  }
}

import 'dart:typed_data';

class BitWriter {
  // The accumulator stores bits temporarily (up to 64 bits on native Dart).
  int _accumulator = 0;
  int _bitsCount = 0;

  // FLAC frame writing is a hot path. A single growable byte buffer avoids the
  // repeated BytesBuilder chunks and lets the encoder compute CRC16 over the
  // already-written bytes before appending the footer.
  Uint8List _buffer;
  int _length = 0;

  BitWriter([int initialCapacity = 8192])
      : _buffer = Uint8List(initialCapacity);

  int get length => _length;

  Uint8List get rawBuffer => _buffer;

  void addByte(int value) {
    _writeByte(value);
  }

  void addBytes(List<int> values) {
    final count = values.length;
    if (count == 0) return;

    _ensureCapacity(count);
    _buffer.setRange(_length, _length + count, values);
    _length += count;
  }

  Uint8List toBytes() {
    final output = Uint8List(_length);
    output.setRange(0, _length, _buffer);
    return output;
  }

  void writeBits(int value, int bitCount) {
    if (bitCount == 0) return;

    // Mask the value to ensure no high "garbage" bits leak in.
    final mask = (1 << bitCount) - 1;
    final cleanValue = value & mask;

    // Push new bits into the accumulator.
    _accumulator = (_accumulator << bitCount) | cleanValue;
    _bitsCount += bitCount;

    // Emit bytes while at least 8 bits are available.
    while (_bitsCount >= 8) {
      _bitsCount -= 8;
      // Extract the highest byte.
      final byte = (_accumulator >> _bitsCount) & 0xFF;
      _writeByte(byte);
    }
  }

  void writeSigned(int value, int bitCount) {
    writeBits(value,
        bitCount); // writeBits already masks bits, so signed works directly.
  }

  void writeUnaryZeroCount(int zeroCount) {
    int remaining = zeroCount;

    // Add zeros in chunks instead of writing one by one.
    // Limited to 32 to avoid overflowing the 64-bit accumulator.
    while (remaining > 0) {
      int chunk = remaining > 32 ? 32 : remaining;

      // Inserting "chunk" zeros is just a left shift on the accumulator.
      _accumulator <<= chunk;
      _bitsCount += chunk;

      while (_bitsCount >= 8) {
        _bitsCount -= 8;
        _writeByte((_accumulator >> _bitsCount) & 0xFF);
      }

      remaining -= chunk;
    }

    // Write the terminating "1" bit.
    writeBits(1, 1);
  }

  void alignToByte() {
    // If bits remain pending, left-pad with zeros until next byte boundary.
    if (_bitsCount > 0) {
      int shift = 8 - _bitsCount;
      _accumulator <<= shift;

      _writeByte(_accumulator & 0xFF);

      _bitsCount = 0;
      _accumulator = 0;
    }
  }

  void _writeByte(int value) {
    _ensureCapacity(1);
    _buffer[_length++] = value & 0xFF;
  }

  void _ensureCapacity(int additionalBytes) {
    final requiredLength = _length + additionalBytes;
    if (requiredLength <= _buffer.length) {
      return;
    }

    var newCapacity = _buffer.length * 2;
    while (newCapacity < requiredLength) {
      newCapacity *= 2;
    }

    final next = Uint8List(newCapacity);
    next.setRange(0, _length, _buffer);
    _buffer = next;
  }
}

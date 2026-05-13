import 'dart:typed_data';

class BitWriter {
  final BytesBuilder _bytes;

  // The accumulator stores bits temporarily (up to 64 bits on native Dart).
  int _accumulator = 0;
  int _bitsCount = 0;

  // Fast local buffer to avoid calling BytesBuilder for every single byte.
  final Uint8List _buffer = Uint8List(8192); // 8 KB
  int _bufferPos = 0;

  BitWriter(this._bytes);

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
      _buffer[_bufferPos++] = byte;

      // Flush to BytesBuilder when the local buffer is full.
      if (_bufferPos == _buffer.length) {
        _flushBuffer();
      }
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
        _buffer[_bufferPos++] = (_accumulator >> _bitsCount) & 0xFF;
        if (_bufferPos == _buffer.length) _flushBuffer();
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

      _buffer[_bufferPos++] = _accumulator & 0xFF;
      if (_bufferPos == _buffer.length) _flushBuffer();

      _bitsCount = 0;
      _accumulator = 0;
    }

    // Flush any remaining buffered bytes at the end of the frame.
    if (_bufferPos > 0) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    // Copy before add: _buffer is reused and mutated after flush.
    // With BytesBuilder(copy: false), passing a view would corrupt
    // previously appended bytes.
    final chunk = Uint8List(_bufferPos);
    chunk.setRange(0, _bufferPos, _buffer);
    _bytes.add(chunk);
    _bufferPos = 0;
  }
}

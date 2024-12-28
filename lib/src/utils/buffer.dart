import 'dart:io';
import 'dart:typed_data';

/// A buffered file that minimize the IO
class Buffer {
  final RandomAccessFile randomAccessFile;

  /// Contains the data read from the [randomAccessFile]
  late final Uint8List _buffer;

  /// The position in the [_buffer]
  /// It helps to know which bytes can be extracted and
  /// when we should refill the buffer
  int _cursor = 0;

  /// Track how many bytes are actually in the buffer
  int _bufferedBytes = 0;

  /// The buffer size. We read [bufferedFile] bytes everytime
  /// that we refill the buffer
  static final int bufferedFile = 16384;

  /// The position of the cursor inside the byte itself
  /// if the value is 2: it will be here: 0b00000000
  ///                                         +
  ///                                        /|\
  ///                                         |
  /// The max value is 7 and the min 0
  int _bitCount = 7;

  int get cursor => _cursor;
  int get bufferSize => bufferedFile;

  Buffer({required this.randomAccessFile}) {
    _buffer = Uint8List(bufferedFile);
    _fill();
  }

  /// Refill the [_buffer] with maximum [bufferedFile] bytes
  /// Reset the [_cursor] on 0
  void _fill() {
    _bufferedBytes = randomAccessFile.readIntoSync(_buffer);
    _cursor = 0;
  }

  /// Read [size] bytes from the buffer
  Uint8List read(int size) {
    // if we read something big (~100kb), we can read it directly from file
    // it makes the read faster
    // no need to use the buffer
    if (size > bufferedFile) {
      final result = Uint8List(size);
      final remaining = _bufferedBytes - _cursor;

      if (remaining > 0) {
        result.setRange(0, remaining, _buffer, _cursor);
      }

      randomAccessFile.readIntoSync(result, remaining);
      _fill();

      return result;
    }

    // If we have enough data in the buffer
    if (size <= _bufferedBytes - _cursor) {
      final result = Uint8List(size);

      for (int i = 0; i < size; i++) {
        result[i] = _buffer[_cursor + i];
      }

      _cursor += size;
      return result;
    } else {
      // Data exceeds remaining buffer, needs refill
      final result = Uint8List(size);
      int remaining = _bufferedBytes - _cursor;
      // Copy remaining data from the buffer

      for (var i = 0; i < remaining; i++) {
        result[i] = _buffer[_cursor + i];
      }

      // Adjust the cursor. Stores the total bytes we have
      // transfer to the result buffer
      int filled = remaining;

      // Continue filling `result` with new buffer data
      while (filled < size) {
        _fill();

        int toCopy = size - filled;

        if (toCopy > _bufferedBytes) {
          toCopy = _bufferedBytes;
        }

        for (var i = filled; i < filled + toCopy; i++) {
          result[i] = _buffer[i - filled];
        }

        filled += toCopy;
        _cursor = toCopy;
      }

      return result;
    }
  }

  /// Move the file cursor to the new [position]
  /// Refill the buffer
  void setPositionSync(int position) {
    randomAccessFile.setPositionSync(position);
    _fill();
  }

  /// Skip [length] bytes in the buffer
  /// If [length] is greater than the buffer, we jump to the new position
  /// and refill the buffer
  void skip(int length) {
    // Calculate how many bytes we can skip in the current buffer
    final remainingInBuffer = _bufferedBytes - _cursor;

    if (length <= remainingInBuffer) {
      // If we can skip within the current buffer, just move the cursor
      _cursor += length;
    } else {
      // Calculate the actual file position we need to skip to
      int currentPosition = randomAccessFile.positionSync() - remainingInBuffer;
      // Skip to the new position
      randomAccessFile.setPositionSync(currentPosition + length);
      // Refill the buffer at the new position
      _fill();
    }
  }

  /// Reads a single bit and returns it as an unsigned integer (0 or 1).
  int readBit() {
    final int bit = (_buffer[_cursor] >> _bitCount) & 1;
    _bitCount -= 1;
    _updateBitCursor();

    return bit;
  }

  void _updateBitCursor() {
    if (_bitCount < 0) {
      _bitCount = 7;
      _cursor++;
      if (_cursor >= _bufferedBytes) {
        _fill();
      }
    }
  }

  int _readBits(int bitCount) {
    int value = 0;
    int bitsRemaining = bitCount;

    while (bitsRemaining > 0) {
      // If we need to refill the buffer
      if (_cursor >= _bufferedBytes) {
        _fill();
      }

      // Calculate how many bits we can read from current byte
      int bitsToRead =
          bitsRemaining < (_bitCount + 1) ? bitsRemaining : (_bitCount + 1);

      // Create a mask for the bits we want to read
      int mask = ((1 << bitsToRead) - 1) << (_bitCount + 1 - bitsToRead);

      // Extract the bits and shift them to their correct position
      int bits = (_buffer[_cursor] & mask) >> (_bitCount + 1 - bitsToRead);

      // Add these bits to our result
      value = (value << bitsToRead) | bits;

      // Update our counters
      _bitCount -= bitsToRead;
      bitsRemaining -= bitsToRead;

      _updateBitCursor();
    }

    return value;
  }

  /// Reads [bitCount] bits and returns an unsigned integer.
  int readUnsigned(int bitCount) {
    return _readBits(bitCount);
  }

  /// Reads [bitCount] bits and returns a signed integer.
  int readSigned(int bitCount) {
    return _readBits(bitCount).toSigned(bitCount);
  }

  void align() {
    if (_bitCount < 7) {
      _bitCount = -1;
      _updateBitCursor();
    }
  }
}

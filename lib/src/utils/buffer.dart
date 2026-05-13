import 'dart:io';
import 'dart:typed_data';

typedef NextChunk = Uint8List? Function();

/// A buffered file that minimize the IO
class Buffer {
  final RandomAccessFile? _randomAccessFile;
  final Uint8List? _sourceBytes;
  final NextChunk? _nextChunk;
  int _sourceOffset = 0;
  Uint8List _chunkBuffer = Uint8List(0);
  int _chunkBufferCursor = 0;

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

  Buffer({required RandomAccessFile randomAccessFile})
      : _randomAccessFile = randomAccessFile,
        _sourceBytes = null,
        _nextChunk = null {
    _buffer = Uint8List(bufferedFile);
    _fill();
  }

  Buffer.fromBytes(Uint8List bytes)
      : _randomAccessFile = null,
        _sourceBytes = bytes,
        _nextChunk = null {
    _buffer = Uint8List(bufferedFile);
    _fill();
  }

  Buffer.fromChunkSource(NextChunk nextChunk)
      : _randomAccessFile = null,
        _sourceBytes = null,
        _nextChunk = nextChunk {
    _buffer = Uint8List(bufferedFile);
    _fill();
  }

  RandomAccessFile get randomAccessFile {
    if (_randomAccessFile == null) {
      throw StateError('This buffer is memory-backed and has no file source.');
    }
    return _randomAccessFile;
  }

  int get bufferedBytes => _bufferedBytes;

  /// Refill the [_buffer] with maximum [bufferedFile] bytes
  /// Reset the [_cursor] on 0
  bool _fill() {
    if (_randomAccessFile != null) {
      _bufferedBytes = _randomAccessFile.readIntoSync(_buffer);
      _cursor = 0;
      return _bufferedBytes > 0;
    }

    if (_sourceBytes != null) {
      final bytes = _sourceBytes;
      if (_sourceOffset >= bytes.length) {
        _bufferedBytes = 0;
        _cursor = 0;
        return false;
      }

      final remaining = bytes.length - _sourceOffset;
      final toCopy = remaining < bufferedFile ? remaining : bufferedFile;
      _buffer.setRange(0, toCopy, bytes, _sourceOffset);
      _sourceOffset += toCopy;
      _bufferedBytes = toCopy;
      _cursor = 0;
      return _bufferedBytes > 0;
    }

    final nextChunk = _nextChunk;
    if (nextChunk == null) {
      _bufferedBytes = 0;
      _cursor = 0;
      return false;
    }

    int written = 0;
    while (written < bufferedFile) {
      if (_chunkBufferCursor >= _chunkBuffer.length) {
        final chunk = nextChunk();
        if (chunk == null) {
          break;
        }
        if (chunk.isEmpty) {
          continue;
        }
        _chunkBuffer = chunk;
        _chunkBufferCursor = 0;
      }

      int available = _chunkBuffer.length - _chunkBufferCursor;
      int toCopy = bufferedFile - written;
      if (toCopy > available) {
        toCopy = available;
      }

      _buffer.setRange(
        written,
        written + toCopy,
        _chunkBuffer,
        _chunkBufferCursor,
      );
      written += toCopy;
      _chunkBufferCursor += toCopy;
    }

    _bufferedBytes = written;
    _cursor = 0;
    return _bufferedBytes > 0;
  }

  /// Read [size] bytes from the buffer
  Uint8List read(int size) {
    // if we read something big (~100kb), we can read it directly from file
    // it makes the read faster
    // no need to use the buffer
    if (size > bufferedFile && _randomAccessFile != null) {
      final result = Uint8List(size);
      final remaining = _bufferedBytes - _cursor;

      if (remaining > 0) {
        result.setAll(0, _buffer.sublist(_cursor, _cursor + remaining));
      }

      _randomAccessFile.readIntoSync(result, remaining);
      _fill();

      return result;
    }

    // If we have enough data in the buffer
    if (size <= _bufferedBytes - _cursor) {
      final result = Uint8List(size);
      result.setRange(0, size, _buffer, _cursor);

      _cursor += size;
      return result;
    } else {
      // Data exceeds remaining buffer, needs refill
      final result = Uint8List(size);
      int remaining = _bufferedBytes - _cursor;
      // Copy remaining data from the buffer
      if (remaining > 0) {
        result.setRange(0, remaining, _buffer, _cursor);
      }

      // Adjust the cursor. Stores the total bytes we have
      // transfer to the result buffer
      int filled = remaining;

      // Continue filling `result` with new buffer data
      while (filled < size) {
        if (!_fill()) break;

        int toCopy = size - filled;

        if (toCopy > _bufferedBytes) {
          toCopy = _bufferedBytes;
        }

        result.setRange(filled, filled + toCopy, _buffer);

        filled += toCopy;
        _cursor = toCopy;
      }

      return result;
    }
  }

  /// Move the file cursor to the new [position]
  /// Refill the buffer
  void setPositionSync(int position) {
    if (_randomAccessFile != null) {
      _randomAccessFile.setPositionSync(position);
      _fill();
      return;
    }

    if (_sourceBytes != null) {
      final bytesLength = _sourceBytes.length;
      if (position < 0 || position > bytesLength) {
        throw RangeError.range(position, 0, bytesLength, 'position');
      }
      _sourceOffset = position;
      _fill();
      return;
    }

    throw UnsupportedError(
      'setPositionSync is not supported for chunked streaming source.',
    );
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
      if (_randomAccessFile != null) {
        // Calculate the actual file position we need to skip to
        int currentPosition =
            _randomAccessFile.positionSync() - remainingInBuffer;
        // Skip to the new position
        _randomAccessFile.setPositionSync(currentPosition + length);
        // Refill the buffer at the new position/source offset
        _fill();
        return;
      }

      if (_sourceBytes != null) {
        final int bytesLength = _sourceBytes.length;
        final int skipOutsideBuffer = length - remainingInBuffer;
        int nextSourceOffset = _sourceOffset + skipOutsideBuffer;
        if (nextSourceOffset > bytesLength) {
          nextSourceOffset = bytesLength;
        }
        _sourceOffset = nextSourceOffset;
        // Refill the buffer at the new position/source offset
        _fill();
        return;
      }

      int remainingToSkip = length - remainingInBuffer;
      _cursor = _bufferedBytes;

      while (remainingToSkip > 0) {
        if (!_fill()) {
          _cursor = _bufferedBytes;
          return;
        }

        if (remainingToSkip <= _bufferedBytes) {
          _cursor = remainingToSkip;
          return;
        }
        remainingToSkip -= _bufferedBytes;
        _cursor = _bufferedBytes;
      }
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

  /// Reads a unary value used by Rice coding:
  /// counts consecutive `0` bits until the first `1` bit (which is consumed).
  int readUnaryZeroCount() {
    int zeroCount = 0;

    while (true) {
      if (_cursor >= _bufferedBytes && !_fill()) {
        throw StateError('Unexpected end of buffer while reading unary code');
      }

      final currentByte = _buffer[_cursor];
      final availableBits = _bitCount + 1;
      final mask = (1 << availableBits) - 1;
      final remainingBits = currentByte & mask;

      if (remainingBits == 0) {
        zeroCount += availableBits;
        _bitCount = -1;
        _updateBitCursor();
        continue;
      }

      // Highest set bit inside the remaining range gives the first `1` we will read.
      final highestSetBit = remainingBits.bitLength - 1;
      final zerosInThisByte = _bitCount - highestSetBit;
      zeroCount += zerosInThisByte;

      // Consume zeros + terminating `1`.
      _bitCount -= (zerosInThisByte + 1);
      _updateBitCursor();
      return zeroCount;
    }
  }

  void align() {
    if (_bitCount < 7) {
      _bitCount = -1;
      _updateBitCursor();
    }
  }
}

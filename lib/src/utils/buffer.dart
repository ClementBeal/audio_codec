import 'dart:io';
import 'dart:typed_data';

/// A buffered file that minimize the IO
class Buffer {
  final RandomAccessFile randomAccessFile;
  final Uint8List _buffer;
  int _cursor = 0;
  int _bufferedBytes = 0; // Track how many bytes are actually in the buffer
  static final int _bufferSize = 16384;
  late final int filelength;
  int _positionInFile = 0;

  Buffer({required this.randomAccessFile}) : _buffer = Uint8List(_bufferSize) {
    filelength = randomAccessFile.lengthSync();
    _fill();
  }

  void _fill() {
    _bufferedBytes = randomAccessFile.readIntoSync(_buffer);
    _positionInFile += _bufferSize;
    _cursor = 0;
  }

  /// Return the position of where is pointing the buffer's cursor
  int cursorPosition() {
    return randomAccessFile.positionSync() - (_bufferSize - _cursor);
  }

  /// Read [size] bytes from the buffer
  Uint8List read(int size) {
    // if we read something big (~100kb), we can read it directly from file
    // it makes the read faster
    // no need to use the buffer
    if (size > _bufferSize) {
      final result = Uint8List(size);
      final remaining = _bufferedBytes - _cursor;
      if (remaining > 0) {
        result.setRange(0, remaining, _buffer, _cursor);
      }
      randomAccessFile.readIntoSync(result, remaining);
      _positionInFile = randomAccessFile.positionSync();
      _fill();
      return result;
    }

    if (size <= _bufferedBytes - _cursor) {
      // Data fits within the current buffer
      final result = _buffer.sublist(_cursor, _cursor + size);
      _cursor += size;
      return result;
    } else {
      // Data exceeds remaining buffer, needs refill
      final result = Uint8List(size);
      int remaining = _bufferedBytes - _cursor;
      // Copy remaining data from the buffer
      result.setRange(0, remaining, _buffer, _cursor);

      // Refill the buffer and adjust the cursor
      _fill();
      int filled = remaining;

      // Continue filling `result` with new buffer data
      while (filled < size) {
        int toCopy = size - filled;
        if (toCopy > _bufferedBytes) {
          toCopy = _bufferedBytes;
        }
        result.setRange(filled, filled + toCopy, _buffer, 0);
        filled += toCopy;
        _cursor = toCopy;

        // Fill buffer again if more data is needed
        if (filled < size) {
          _fill();
        }
      }
      return result;
    }
  }

  /// Move the file cursor to the new [position]
  /// Refill the buffer
  void setPositionSync(int position) {
    randomAccessFile.setPositionSync(position);
    _positionInFile = position;
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
      _positionInFile = currentPosition + length;
      // Refill the buffer at the new position
      _fill();
    }
  }

  /// Check if the buffer cursor has reached the end of file
  bool hasMoreData() {
    return _positionInFile < filelength;
  }
}

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

  /// The buffer size. We read [_bufferSize] bytes everytime
  /// that we refill the buffer
  static final int _bufferSize = 16384;

  Buffer({required this.randomAccessFile}) {
    _buffer = Uint8List(_bufferSize);
    _fill();
  }

  /// Refill the [_buffer] with maximum [_bufferSize] bytes
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
    if (size > _bufferSize) {
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
      // Data fits within the current buffer
      final result = Uint8List(size);

      for (var i = 0; i < size; i++) {
        result[i] = _buffer[_cursor + i];
      }

      // _buffer.sublist(_cursor, _cursor + size);
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
}

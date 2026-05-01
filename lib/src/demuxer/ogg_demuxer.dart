import 'dart:io';
import 'dart:typed_data';

class OggDemuxer {
  final RandomAccessFile source;

  OggDemuxer({required this.source});

  /// Read the next OGG page from [source].
  OggPage readPage() {
    // Each OGG page starts with the 4-byte capture pattern "OggS".
    final capturePattern = source.readSync(4);
    if (capturePattern.isEmpty) {
      throw StateError('EOF reached before reading a new OGG page.');
    }

    if (capturePattern.length != 4 ||
        capturePattern[0] != 0x4F ||
        capturePattern[1] != 0x67 ||
        capturePattern[2] != 0x67 ||
        capturePattern[3] != 0x53) {
      throw const FormatException('Invalid OGG capture pattern.');
    }

    // After the 4-byte "OggS" capture pattern, the OGG page header has 23 fixed bytes:
    // bytes 00..07: A B C C | C C C C
    // bytes 08..15: C C D D | D D E E
    // bytes 16..22: E E F F | F F G
    // A: stream structure version
    // B: header type flag
    // C: granule position (little-endian uint64)
    // D: bitstream serial number (little-endian uint32)
    // E: page sequence number (little-endian uint32)
    // F: checksum (little-endian uint32)
    // G: page segments count
    final fixedHeader = _readExact(23, label: 'OGG fixed header');
    final int headerType = fixedHeader[1];
    _validateHeaderType(headerType);

    // The last fixed-header byte (G) tells how many lacing values follow.
    // This "segment table" has 1 byte per lacing value, each byte in [0..255].
    // Summing all lacing values gives the total payload bytes for this page.
    // A value of 255 means the packet continues in the next segment/page.
    final pageSegments = fixedHeader[22];
    final segmentTable = _readExact(pageSegments, label: 'OGG segment table');

    int payloadLength = 0;
    for (final segmentSize in segmentTable) {
      payloadLength += segmentSize;
    }

    final payload = _readExact(payloadLength, label: 'OGG payload');
    final headerBytes = Uint8List.fromList([
      ...capturePattern,
      ...fixedHeader,
      ...segmentTable,
    ]);

    final byteData = fixedHeader.buffer.asByteData(
      fixedHeader.offsetInBytes,
      fixedHeader.lengthInBytes,
    );

    return OggPage(
      streamStructureVersion: fixedHeader[0],
      headerType: headerType,
      granulePosition: byteData.getUint64(2, Endian.little),
      bitstreamSerialNumber: byteData.getUint32(10, Endian.little),
      pageSequenceNumber: byteData.getUint32(14, Endian.little),
      checksum: byteData.getUint32(18, Endian.little),
      pageSegments: pageSegments,
      segmentTable: segmentTable,
      payload: payload,
      headerBytes: headerBytes,
    );
  }

  /// Read exactly [length] bytes.
  ///
  /// [label] is used only to produce clearer error messages when EOF happens.
  /// Example: "Unexpected EOF while reading OGG fixed header."
  Uint8List _readExact(int length, {required String label}) {
    final bytes = source.readSync(length);
    if (bytes.length != length) {
      throw FormatException('Unexpected EOF while reading $label.');
    }
    return bytes;
  }

  void _validateHeaderType(int rawHeaderType) {
    const int validBitsMask = 0x07;
    final int unknownBits = rawHeaderType & ~validBitsMask;
    if (unknownBits != 0) {
      throw FormatException(
        'Invalid OGG header type flags: 0x${rawHeaderType.toRadixString(16)}',
      );
    }
  }
}

class OggPage {
  final int streamStructureVersion;
  final int headerType;
  final int granulePosition;
  final int bitstreamSerialNumber;
  final int pageSequenceNumber;
  final int checksum;
  final int pageSegments;
  final Uint8List segmentTable;
  final Uint8List payload;
  final Uint8List headerBytes;

  OggPage({
    required this.streamStructureVersion,
    required this.headerType,
    required this.granulePosition,
    required this.bitstreamSerialNumber,
    required this.pageSequenceNumber,
    required this.checksum,
    required this.pageSegments,
    required this.segmentTable,
    required this.payload,
    required this.headerBytes,
  });

  /// True when the first packet in this page is a continuation
  /// of a packet that started in the previous page.
  bool get isContinuation => (headerType & 0x01) != 0;

  /// True when this page is marked as the beginning of the logical stream.
  bool get isBeginningOfStream => (headerType & 0x02) != 0;

  /// True when this page is marked as the end of the logical stream.
  bool get isEndOfStream => (headerType & 0x04) != 0;
}

import 'dart:io';
import 'dart:typed_data';

enum OggCodec {
  flac,
  vorbis,
  opus,
  speex,
}

class OggEncoderConfig {
  final OggCodec codec;
  final int bitstreamSerialNumber;

  const OggEncoderConfig({
    this.codec = OggCodec.flac,
    this.bitstreamSerialNumber = 1,
  });
}

class OggEncoder {
  static const int _oggHeaderSize = 27;
  static const int _oggMaxPageSegments = 255;
  static const int _oggMaxSegmentLength = 255;

  final OggEncoderConfig config;

  OggEncoder({this.config = const OggEncoderConfig()});

  /// Encodes [codecBytes] in an OGG container according to [config.codec].
  ///
  /// For now, only [OggCodec.flac] is supported and [codecBytes] must be a
  /// native FLAC stream (starting with "fLaC").
  Uint8List encode(Uint8List codecBytes) {
    switch (config.codec) {
      case OggCodec.flac:
        return _encodeOggFlac(codecBytes);
      case OggCodec.vorbis:
      case OggCodec.opus:
      case OggCodec.speex:
        throw UnsupportedError(
          'OGG ${config.codec.name} encoding is not supported yet. '
          'Only OGG-FLAC is available.',
        );
    }
  }

  void encodeToFile(File target, Uint8List codecBytes) {
    target.writeAsBytesSync(encode(codecBytes));
  }

  Uint8List _encodeOggFlac(Uint8List flacBytes) {
    final packetBuilder = BytesBuilder(copy: false)
      ..add(const [
        0x7F,
        0x46,
        0x4C,
        0x41,
        0x43,
        0x01,
        0x00,
        0x00,
        0x00,
      ])
      ..add(flacBytes);

    final packet = packetBuilder.takeBytes();
    final pages = BytesBuilder(copy: false);

    int packetOffset = 0;
    int pageSequenceNumber = 0;
    bool continuedPacket = false;

    while (true) {
      final lacingValues = <int>[];
      int payloadLength = 0;

      while (lacingValues.length < _oggMaxPageSegments &&
          packetOffset + payloadLength < packet.length) {
        final remaining = packet.length - packetOffset - payloadLength;
        final segmentLength =
            remaining > _oggMaxSegmentLength ? _oggMaxSegmentLength : remaining;

        lacingValues.add(segmentLength);
        payloadLength += segmentLength;

        if (segmentLength < _oggMaxSegmentLength) {
          break;
        }
      }

      final packetExhausted = packetOffset + payloadLength == packet.length;
      if (packetExhausted &&
          lacingValues.isNotEmpty &&
          lacingValues.last == _oggMaxSegmentLength &&
          lacingValues.length < _oggMaxPageSegments) {
        // Exact 255-byte multiple: explicit zero-length segment closes packet.
        lacingValues.add(0);
      }

      final packetFinished = lacingValues.isNotEmpty && lacingValues.last < 255;
      final page = _buildFirstPageHeader(
        pageSequenceNumber: pageSequenceNumber,
        continuedPacket: continuedPacket,
        packetFinished: packetFinished,
        segmentCount: lacingValues.length,
        payloadLength: payloadLength,
      );

      int segmentOffset = _oggHeaderSize;
      for (final value in lacingValues) {
        page[segmentOffset++] = value;
      }

      if (payloadLength > 0) {
        page.setRange(
          segmentOffset,
          segmentOffset + payloadLength,
          packet.sublist(packetOffset, packetOffset + payloadLength),
        );
      }

      final pageView = ByteData.sublistView(page);
      final checksum = _computeOggCrc32(page);
      pageView.setUint32(22, checksum, Endian.little);
      pages.add(page);

      packetOffset += payloadLength;
      pageSequenceNumber++;

      if (packetFinished) {
        break;
      }

      continuedPacket = true;
    }

    return pages.takeBytes();
  }

  Uint8List _buildFirstPageHeader({
    required int pageSequenceNumber,
    required bool continuedPacket,
    required bool packetFinished,
    required int segmentCount,
    required int payloadLength,
  }) {
    final headerType = _resolveHeaderType(
      pageSequenceNumber: pageSequenceNumber,
      continuedPacket: continuedPacket,
      packetFinished: packetFinished,
    );

    final bytes = Uint8List(_oggHeaderSize + segmentCount + payloadLength);
    final view = ByteData.sublistView(bytes);

    // Capture pattern: "OggS".
    bytes[0] = 0x4F;
    bytes[1] = 0x67;
    bytes[2] = 0x67;
    bytes[3] = 0x53;

    // stream_structure_version = 0.
    bytes[4] = 0;

    bytes[5] = headerType;

    // granule_position = 0 for header/data split not yet tracked.
    view.setUint64(6, 0, Endian.little);

    view.setUint32(14, config.bitstreamSerialNumber, Endian.little);
    view.setUint32(18, pageSequenceNumber, Endian.little);

    // CRC field stays 0 while calculating checksum.
    view.setUint32(22, 0, Endian.little);

    bytes[26] = segmentCount;

    return bytes;
  }

  int _resolveHeaderType({
    required int pageSequenceNumber,
    required bool continuedPacket,
    required bool packetFinished,
  }) {
    int headerType = 0;

    if (pageSequenceNumber == 0) {
      headerType |= 0x02; // BOS
    }
    if (continuedPacket) {
      headerType |= 0x01; // continued packet
    }
    if (packetFinished) {
      headerType |= 0x04; // EOS
    }

    return headerType;
  }

  int _computeOggCrc32(Uint8List data) {
    int crc = 0;

    for (final byte in data) {
      crc ^= (byte << 24) & 0xFFFFFFFF;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x80000000) != 0) {
          crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF;
        } else {
          crc = (crc << 1) & 0xFFFFFFFF;
        }
      }
    }

    return crc;
  }
}

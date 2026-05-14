import 'dart:io';
import 'dart:typed_data';

class OggEncoder {
  final int bitstreamSerialNumber;

  OggEncoder({this.bitstreamSerialNumber = 1});

  /// Build a minimal valid OGG bitstream with a single empty page.
  ///
  /// The page is both BOS and EOS and contains no packets.
  Uint8List encode() {
    final bytes = _buildFirstPageHeader();
    final view = ByteData.sublistView(bytes);
    final checksum = _computeOggCrc32(bytes);
    view.setUint32(22, checksum, Endian.little);
    return bytes;
  }

  void encodeToFile(File target) {
    target.writeAsBytesSync(encode());
  }

  Uint8List _buildFirstPageHeader() {
    final bytes = Uint8List(27);
    final view = ByteData.sublistView(bytes);

    // Capture pattern: "OggS".
    bytes[0] = 0x4F;
    bytes[1] = 0x67;
    bytes[2] = 0x67;
    bytes[3] = 0x53;

    // stream_structure_version = 0.
    bytes[4] = 0;

    // header_type = BOS (0x02) | EOS (0x04).
    bytes[5] = 0x06;

    // granule_position = 0 (empty stream).
    view.setUint64(6, 0, Endian.little);

    // logical bitstream serial number.
    view.setUint32(14, bitstreamSerialNumber, Endian.little);

    // page sequence number.
    view.setUint32(18, 0, Endian.little);

    // CRC field stays 0 while calculating checksum.
    view.setUint32(22, 0, Endian.little);

    // page_segments = 0 => no segment table, no payload.
    bytes[26] = 0;

    return bytes;
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

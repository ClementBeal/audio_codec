import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/utils/crc/crc8.dart';

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
  static const int _maxSegments = 255;
  static const int _maxSegmentSize = 255;
  static const int _unsetGranule = 0xFFFFFFFFFFFFFFFF;

  static const List<int> _flacMagic = <int>[0x66, 0x4C, 0x61, 0x43];
  static const int _streamInfoType = 0;
  static const int _vorbisCommentType = 4;

  final OggEncoderConfig config;

  OggEncoder({this.config = const OggEncoderConfig()});

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
    final parsed = _parseNativeFlac(flacBytes);
    final headerPackets = _buildHeaderPackets(parsed.metadataBlocks);

    final identificationPacket = _buildIdentificationPacket(
      _setLastFlag(parsed.streamInfoBlock, false),
      headerPackets.length,
    );

    final packets = <Uint8List>[identificationPacket, ...headerPackets];
    final granules = List<int>.filled(packets.length, 0, growable: true);

    for (final frame in parsed.audioFrames) {
      packets.add(frame.bytes);
      granules.add(frame.granulePosition);
    }

    return _muxPackets(
      packets,
      granules,
      headerPacketCount: 1 + headerPackets.length,
    );
  }

  _ParsedNativeFlac _parseNativeFlac(Uint8List flacBytes) {
    if (flacBytes.length < 8 || !_hasPrefix(flacBytes, _flacMagic)) {
      throw const FormatException('Expected a native FLAC stream (fLaC).');
    }

    int offset = 4;
    Uint8List? streamInfo;
    final metadataBlocks = <Uint8List>[];

    while (true) {
      if (offset + 4 > flacBytes.length) {
        throw const FormatException('Truncated FLAC metadata header.');
      }

      final isLast = (flacBytes[offset] & 0x80) != 0;
      final blockType = flacBytes[offset] & 0x7F;
      final blockLength = (flacBytes[offset + 1] << 16) |
          (flacBytes[offset + 2] << 8) |
          flacBytes[offset + 3];
      final blockEnd = offset + 4 + blockLength;

      if (blockEnd > flacBytes.length) {
        throw const FormatException('Truncated FLAC metadata block.');
      }

      final block = Uint8List.fromList(flacBytes.sublist(offset, blockEnd));
      if (streamInfo == null) {
        if (blockType != _streamInfoType) {
          throw const FormatException(
              'First FLAC metadata block must be STREAMINFO.');
        }
        streamInfo = block;
      } else {
        metadataBlocks.add(block);
      }

      offset = blockEnd;
      if (isLast) {
        break;
      }
    }

    final audioPayload = Uint8List.sublistView(flacBytes, offset);

    return _ParsedNativeFlac(
      streamInfoBlock: streamInfo,
      metadataBlocks: metadataBlocks,
      audioFrames: _splitFrames(audioPayload),
    );
  }

  List<_FlacAudioFramePacket> _splitFrames(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const <_FlacAudioFramePacket>[];
    }

    if (_tryParseFrameHeader(bytes, 0) == null) {
      throw const FormatException('Could not parse first FLAC frame header.');
    }

    final frames = <_FlacAudioFramePacket>[];
    int start = 0;
    int granule = 0;

    while (start < bytes.length) {
      final header = _tryParseFrameHeader(bytes, start);
      if (header == null) {
        throw FormatException('Invalid FLAC frame at offset $start.');
      }

      final nextStart = _findNextFrameStart(
        bytes,
        start + header.headerLength + 2,
      );
      final end = nextStart == -1 ? bytes.length : nextStart;

      granule += header.blockSize;
      frames.add(
        _FlacAudioFramePacket(
          bytes: Uint8List.fromList(bytes.sublist(start, end)),
          granulePosition: granule,
        ),
      );

      if (nextStart == -1) {
        break;
      }
      start = nextStart;
    }

    return frames;
  }

  int _findNextFrameStart(Uint8List bytes, int from) {
    if (from < 0) {
      from = 0;
    }

    for (int i = from; i + 1 < bytes.length; i++) {
      if (bytes[i] != 0xFF) {
        continue;
      }
      if ((bytes[i + 1] & 0xFE) != 0xF8) {
        continue;
      }
      if (_tryParseFrameHeader(bytes, i) != null) {
        return i;
      }
    }

    return -1;
  }

  _FlacFrameHeader? _tryParseFrameHeader(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 5 >= bytes.length) {
      return null;
    }

    final b0 = bytes[offset];
    final b1 = bytes[offset + 1];
    final b2 = bytes[offset + 2];
    final b3 = bytes[offset + 3];

    if (b0 != 0xFF || (b1 & 0xFE) != 0xF8) {
      return null;
    }
    if (((b1 >> 1) & 0x01) != 0) {
      return null;
    }
    if ((b3 & 0x01) != 0) {
      return null;
    }

    final codedNumberLength = _utf8IntLength(bytes, offset + 4);
    if (codedNumberLength == null) {
      return null;
    }

    final blockSizeCode = (b2 >> 4) & 0x0F;
    final sampleRateCode = b2 & 0x0F;
    final blockSize =
        _decodeBlockSize(blockSizeCode, bytes, offset + 4 + codedNumberLength);
    if (blockSize == null) {
      return null;
    }

    int cursor = offset + 4 + codedNumberLength + blockSize.extraBytes;
    if (sampleRateCode == 12) {
      cursor += 1;
    } else if (sampleRateCode == 13 || sampleRateCode == 14) {
      cursor += 2;
    }

    if (cursor >= bytes.length) {
      return null;
    }

    final crc = bytes[cursor];
    final computed = calculateCRC8(bytes.sublist(offset, cursor));
    if (crc != computed) {
      return null;
    }

    return _FlacFrameHeader(
      blockSize: blockSize.samples,
      headerLength: cursor - offset + 1,
    );
  }

  _DecodedBlockSize? _decodeBlockSize(int code, Uint8List bytes, int cursor) {
    if (code == 0) {
      return null;
    }
    if (code == 1) {
      return const _DecodedBlockSize(samples: 192, extraBytes: 0);
    }
    if (code >= 2 && code <= 5) {
      return _DecodedBlockSize(samples: 576 << (code - 2), extraBytes: 0);
    }
    if (code == 6) {
      if (cursor >= bytes.length) {
        return null;
      }
      return _DecodedBlockSize(samples: bytes[cursor] + 1, extraBytes: 1);
    }
    if (code == 7) {
      if (cursor + 1 >= bytes.length) {
        return null;
      }
      final samples = ((bytes[cursor] << 8) | bytes[cursor + 1]) + 1;
      return _DecodedBlockSize(samples: samples, extraBytes: 2);
    }

    return _DecodedBlockSize(samples: 256 << (code - 8), extraBytes: 0);
  }

  int? _utf8IntLength(Uint8List bytes, int offset) {
    if (offset < 0 || offset >= bytes.length) {
      return null;
    }

    final b = bytes[offset];
    int len;

    if ((b & 0x80) == 0) {
      len = 1;
    } else if ((b & 0xE0) == 0xC0) {
      len = 2;
    } else if ((b & 0xF0) == 0xE0) {
      len = 3;
    } else if ((b & 0xF8) == 0xF0) {
      len = 4;
    } else if ((b & 0xFC) == 0xF8) {
      len = 5;
    } else if ((b & 0xFE) == 0xFC) {
      len = 6;
    } else if (b == 0xFE) {
      len = 7;
    } else {
      return null;
    }

    if (offset + len > bytes.length) {
      return null;
    }

    for (int i = 1; i < len; i++) {
      if ((bytes[offset + i] & 0xC0) != 0x80) {
        return null;
      }
    }

    return len;
  }

  List<Uint8List> _buildHeaderPackets(List<Uint8List> metadataBlocks) {
    final headers = <Uint8List>[];

    int vorbisIndex = -1;
    for (int i = 0; i < metadataBlocks.length; i++) {
      if (_blockType(metadataBlocks[i]) == _vorbisCommentType) {
        vorbisIndex = i;
        break;
      }
    }

    if (vorbisIndex == -1) {
      headers.add(_buildEmptyVorbisComment());
      headers.addAll(metadataBlocks);
    } else {
      headers.add(metadataBlocks[vorbisIndex]);
      for (int i = 0; i < metadataBlocks.length; i++) {
        if (i != vorbisIndex) {
          headers.add(metadataBlocks[i]);
        }
      }
    }

    for (int i = 0; i < headers.length; i++) {
      headers[i] = _setLastFlag(headers[i], i == headers.length - 1);
    }

    return headers;
  }

  Uint8List _buildIdentificationPacket(
      Uint8List streamInfoBlock, int extraHeaderPackets) {
    final headerPacketCount = extraHeaderPackets;
    if (headerPacketCount < 0 || headerPacketCount > 0xFFFF) {
      throw RangeError.range(headerPacketCount, 0, 0xFFFF, 'headerPacketCount');
    }

    final packet = BytesBuilder(copy: false)
      ..add(const <int>[0x7F, 0x46, 0x4C, 0x41, 0x43, 0x01, 0x00])
      ..add(<int>[(headerPacketCount >> 8) & 0xFF, headerPacketCount & 0xFF])
      ..add(_flacMagic)
      ..add(streamInfoBlock);

    return packet.takeBytes();
  }

  Uint8List _buildEmptyVorbisComment() {
    const vendor = 'audio_codec';
    final vendorBytes = utf8.encode(vendor);

    final payloadLength = 4 + vendorBytes.length + 4;
    final payload = Uint8List(payloadLength);

    _writeUint32LE(payload, 0, vendorBytes.length);
    payload.setRange(4, 4 + vendorBytes.length, vendorBytes);
    _writeUint32LE(payload, 4 + vendorBytes.length, 0);

    final block = Uint8List(4 + payloadLength);
    block[0] = _vorbisCommentType;
    block[1] = (payloadLength >> 16) & 0xFF;
    block[2] = (payloadLength >> 8) & 0xFF;
    block[3] = payloadLength & 0xFF;
    block.setRange(4, block.length, payload);

    return block;
  }

  Uint8List _muxPackets(
    List<Uint8List> packets,
    List<int> granules, {
    required int headerPacketCount,
  }) {
    if (packets.isEmpty || packets.length != granules.length) {
      throw const FormatException('Invalid packet/granule inputs.');
    }

    final out = BytesBuilder(copy: false);
    int sequence = 0;

    for (int packetIndex = 0; packetIndex < packets.length; packetIndex++) {
      final packet = packets[packetIndex];
      final isHeader = packetIndex < headerPacketCount;
      final isLastPacket = packetIndex == packets.length - 1;

      int offset = 0;
      bool continuation = false;

      while (true) {
        final laces = <int>[];
        int payloadLength = 0;

        while (laces.length < _maxSegments &&
            offset + payloadLength < packet.length) {
          final remaining = packet.length - offset - payloadLength;
          final segment =
              remaining > _maxSegmentSize ? _maxSegmentSize : remaining;
          laces.add(segment);
          payloadLength += segment;
          if (segment < _maxSegmentSize) {
            break;
          }
        }

        final packetExhausted = offset + payloadLength == packet.length;
        if (packetExhausted &&
            laces.isNotEmpty &&
            laces.last == _maxSegmentSize &&
            laces.length < _maxSegments) {
          laces.add(0);
        }

        final packetFinished = laces.isNotEmpty && laces.last < _maxSegmentSize;
        final granule = isHeader
            ? 0
            : (packetFinished ? granules[packetIndex] : _unsetGranule);

        final page = _newPage(
          sequence: sequence,
          granule: granule,
          lacingCount: laces.length,
          payloadLength: payloadLength,
          bos: sequence == 0,
          eos: isLastPacket && packetFinished,
          continuation: continuation,
        );

        int writeAt = _oggHeaderSize;
        for (final lace in laces) {
          page[writeAt++] = lace;
        }

        if (payloadLength > 0) {
          page.setRange(
            writeAt,
            writeAt + payloadLength,
            packet.sublist(offset, offset + payloadLength),
          );
        }

        final pageView = ByteData.sublistView(page);
        pageView.setUint32(22, _oggCrc32(page), Endian.little);
        out.add(page);

        sequence++;
        offset += payloadLength;

        if (packetFinished) {
          break;
        }
        continuation = true;
      }
    }

    return out.takeBytes();
  }

  Uint8List _newPage({
    required int sequence,
    required int granule,
    required int lacingCount,
    required int payloadLength,
    required bool bos,
    required bool eos,
    required bool continuation,
  }) {
    int headerType = 0;
    if (continuation) {
      headerType |= 0x01;
    }
    if (bos) {
      headerType |= 0x02;
    }
    if (eos) {
      headerType |= 0x04;
    }

    final page = Uint8List(_oggHeaderSize + lacingCount + payloadLength);
    final view = ByteData.sublistView(page);

    page[0] = 0x4F;
    page[1] = 0x67;
    page[2] = 0x67;
    page[3] = 0x53;
    page[4] = 0;
    page[5] = headerType;
    view.setUint64(6, granule, Endian.little);
    view.setUint32(14, config.bitstreamSerialNumber, Endian.little);
    view.setUint32(18, sequence, Endian.little);
    view.setUint32(22, 0, Endian.little);
    page[26] = lacingCount;

    return page;
  }

  Uint8List _setLastFlag(Uint8List block, bool isLast) {
    if (block.length < 4) {
      throw const FormatException('Invalid FLAC metadata block length.');
    }
    final copy = Uint8List.fromList(block);
    copy[0] = (copy[0] & 0x7F) | (isLast ? 0x80 : 0x00);
    return copy;
  }

  int _blockType(Uint8List block) {
    if (block.isEmpty) {
      throw const FormatException('Invalid FLAC metadata block.');
    }
    return block[0] & 0x7F;
  }

  bool _hasPrefix(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) {
      return false;
    }
    for (int i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  int _oggCrc32(Uint8List data) {
    int crc = 0;
    for (final byte in data) {
      crc ^= (byte << 24) & 0xFFFFFFFF;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 0x80000000) != 0
            ? ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            : (crc << 1) & 0xFFFFFFFF;
      }
    }
    return crc;
  }

  void _writeUint32LE(Uint8List bytes, int offset, int value) {
    bytes[offset] = value & 0xFF;
    bytes[offset + 1] = (value >> 8) & 0xFF;
    bytes[offset + 2] = (value >> 16) & 0xFF;
    bytes[offset + 3] = (value >> 24) & 0xFF;
  }
}

class _ParsedNativeFlac {
  final Uint8List streamInfoBlock;
  final List<Uint8List> metadataBlocks;
  final List<_FlacAudioFramePacket> audioFrames;

  const _ParsedNativeFlac({
    required this.streamInfoBlock,
    required this.metadataBlocks,
    required this.audioFrames,
  });
}

class _FlacAudioFramePacket {
  final Uint8List bytes;
  final int granulePosition;

  const _FlacAudioFramePacket({
    required this.bytes,
    required this.granulePosition,
  });
}

class _FlacFrameHeader {
  final int blockSize;
  final int headerLength;

  const _FlacFrameHeader({
    required this.blockSize,
    required this.headerLength,
  });
}

class _DecodedBlockSize {
  final int samples;
  final int extraBytes;

  const _DecodedBlockSize({
    required this.samples,
    required this.extraBytes,
  });
}

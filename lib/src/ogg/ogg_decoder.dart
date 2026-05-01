import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/demuxer/ogg_demuxer.dart';
import 'package:audio_codec/src/utils/buffer.dart';

enum OggAudioCodec {
  flac,
  vorbis,
  opus,
  speex,
  unknown,
}

class OggDecoder {
  final File track;

  late final RandomAccessFile source;
  late final Buffer bufferedSource;
  late final OggDemuxer demuxer;

  final List<Uint8List> _pendingPackets = <Uint8List>[];
  final BytesBuilder _packetInProgress = BytesBuilder(copy: false);

  OggAudioCodec? audioCodec;

  OggDecoder({required this.track}) {
    source = track.openSync();
    bufferedSource = Buffer(randomAccessFile: source);
    demuxer = OggDemuxer(source: bufferedSource.randomAccessFile);
  }

  /// Start decoding by reading the OGG identification packet
  /// and checking which audio codec is embedded in the stream.
  ///
  /// For now, only OGG-FLAC is supported.
  void decode() {
    bufferedSource.setPositionSync(0);
    _pendingPackets.clear();
    _packetInProgress.takeBytes();

    final Uint8List identificationPacket = _readNextPacket();
    audioCodec = _detectCodec(identificationPacket);

    if (audioCodec != OggAudioCodec.flac) {
      throw UnsupportedError(
        'Unsupported OGG audio codec: ${audioCodec!.name}. '
        'Only FLAC is supported for now.',
      );
    }
  }

  void close() {
    source.closeSync();
  }

  Uint8List _readNextPacket() {
    while (_pendingPackets.isEmpty) {
      final OggPage page = demuxer.readPage();
      _appendPacketsFromPage(page);
    }

    return _pendingPackets.removeAt(0);
  }

  void _appendPacketsFromPage(OggPage page) {
    int payloadOffset = 0;

    for (final int segmentLength in page.segmentTable) {
      if (segmentLength > 0) {
        _packetInProgress.add(
          Uint8List.sublistView(
            page.payload,
            payloadOffset,
            payloadOffset + segmentLength,
          ),
        );
      }

      payloadOffset += segmentLength;

      // In OGG lacing, a value < 255 means "packet ends here".
      if (segmentLength < 255) {
        _pendingPackets.add(_packetInProgress.takeBytes());
      }
    }

    if (payloadOffset != page.payload.length) {
      throw const FormatException('OGG payload length mismatch.');
    }
  }

  OggAudioCodec _detectCodec(Uint8List identificationPacket) {
    if (_startsWith(identificationPacket, _oggFlacSignature)) {
      return OggAudioCodec.flac;
    }

    if (_startsWith(identificationPacket, _oggVorbisSignature)) {
      return OggAudioCodec.vorbis;
    }

    if (_startsWith(identificationPacket, _oggOpusSignature)) {
      return OggAudioCodec.opus;
    }

    if (_startsWith(identificationPacket, _oggSpeexSignature)) {
      return OggAudioCodec.speex;
    }

    return OggAudioCodec.unknown;
  }

  bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) {
      return false;
    }

    for (int index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }
}

// OGG-FLAC identification packet starts with 0x7F then ASCII "FLAC".
const List<int> _oggFlacSignature = <int>[0x7F, 0x46, 0x4C, 0x41, 0x43];
// OGG-Vorbis identification packet starts with 0x01 then ASCII "vorbis".
const List<int> _oggVorbisSignature = <int>[
  0x01,
  0x76,
  0x6F,
  0x72,
  0x62,
  0x69,
  0x73,
];
// OGG-Opus identification packet starts with ASCII "OpusHead".
const List<int> _oggOpusSignature = <int>[
  0x4F,
  0x70,
  0x75,
  0x73,
  0x48,
  0x65,
  0x61,
  0x64,
];
// OGG-Speex identification packet starts with ASCII "Speex   " (3 spaces).
const List<int> _oggSpeexSignature = <int>[
  0x53,
  0x70,
  0x65,
  0x65,
  0x78,
  0x20,
  0x20,
  0x20,
];

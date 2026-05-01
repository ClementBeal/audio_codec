import 'dart:io';
import 'dart:typed_data';

import 'package:audio_codec/src/demuxer/ogg_demuxer.dart';
import 'package:audio_codec/src/flac/flac_decoder.dart';
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
  Directory? _temporaryDecodeDirectory;

  final List<Uint8List> _pendingPackets = <Uint8List>[];
  final BytesBuilder _packetInProgress = BytesBuilder(copy: false);

  OggAudioCodec? audioCodec;
  FlacDecoder? flacDecoder;

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
    final List<Uint8List> packets = _readAllPackets();
    if (packets.isEmpty) {
      throw const FormatException('Empty OGG stream: no packet found.');
    }

    final Uint8List identificationPacket = packets.first;
    audioCodec = _detectCodec(identificationPacket);

    if (audioCodec != OggAudioCodec.flac) {
      throw UnsupportedError(
        'Unsupported OGG audio codec: ${audioCodec!.name}. '
        'Only FLAC is supported for now.',
      );
    }

    final Uint8List nativeFlacStream = _buildNativeFlacStream(packets);
    _prepareFlacDecoder(nativeFlacStream);

    try {
      flacDecoder!.decode();
    } catch (_) {
      _disposeFlacDecoderArtifacts();
      rethrow;
    }
  }

  void close() {
    _disposeFlacDecoderArtifacts();
    source.closeSync();
  }

  List<Uint8List> _readAllPackets() {
    bufferedSource.setPositionSync(0);
    source.setPositionSync(0);
    _pendingPackets.clear();
    _packetInProgress.takeBytes();

    final List<Uint8List> packets = <Uint8List>[];
    bool hasReachedEndOfStream = false;

    while (!hasReachedEndOfStream) {
      final OggPage page = demuxer.readPage();
      _appendPacketsFromPage(page);
      hasReachedEndOfStream = page.isEndOfStream;

      while (_pendingPackets.isNotEmpty) {
        packets.add(_pendingPackets.removeAt(0));
      }
    }

    if (_packetInProgress.length != 0) {
      throw const FormatException('Truncated OGG packet at end of stream.');
    }

    return packets;
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

  Uint8List _buildNativeFlacStream(List<Uint8List> packets) {
    final Uint8List identificationPacket = packets.first;

    if (identificationPacket.length <= _oggFlacMappingHeaderLength) {
      throw const FormatException('Invalid OGG-FLAC identification packet.');
    }

    if (!_startsWithAt(
      identificationPacket,
      _nativeFlacMagic,
      _oggFlacMappingHeaderLength,
    )) {
      throw const FormatException(
        'OGG-FLAC identification packet does not contain native "fLaC" magic.',
      );
    }

    final BytesBuilder flacStream = BytesBuilder(copy: false);
    flacStream.add(
      Uint8List.sublistView(
        identificationPacket,
        _oggFlacMappingHeaderLength,
      ),
    );

    for (int packetIndex = 1; packetIndex < packets.length; packetIndex++) {
      flacStream.add(packets[packetIndex]);
    }

    return flacStream.takeBytes();
  }

  void _prepareFlacDecoder(Uint8List nativeFlacStream) {
    _disposeFlacDecoderArtifacts();

    _temporaryDecodeDirectory =
        Directory.systemTemp.createTempSync('audio_codec_ogg_flac_');
    final String flacFilePath =
        '${_temporaryDecodeDirectory!.path}${Platform.pathSeparator}stream.flac';
    final File flacFile = File(flacFilePath);

    flacFile.writeAsBytesSync(nativeFlacStream, flush: true);
    flacDecoder = FlacDecoder.fromFile(flacFile);
  }

  void _disposeFlacDecoderArtifacts() {
    if (flacDecoder != null) {
      flacDecoder!.close();
      flacDecoder = null;
    }

    if (_temporaryDecodeDirectory != null) {
      if (_temporaryDecodeDirectory!.existsSync()) {
        _temporaryDecodeDirectory!.deleteSync(recursive: true);
      }
      _temporaryDecodeDirectory = null;
    }
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

  bool _startsWithAt(Uint8List bytes, List<int> prefix, int offset) {
    if (offset < 0) {
      return false;
    }
    if (bytes.length < offset + prefix.length) {
      return false;
    }

    for (int index = 0; index < prefix.length; index++) {
      if (bytes[offset + index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }
}

// OGG-FLAC mapping header length before native FLAC data:
// 0x7F + "FLAC" + major/minor version + header-packets count.
const int _oggFlacMappingHeaderLength = 9;

// OGG-FLAC identification packet starts with 0x7F then ASCII "FLAC".
const List<int> _oggFlacSignature = <int>[0x7F, 0x46, 0x4C, 0x41, 0x43];
// Native FLAC stream starts with ASCII "fLaC".
const List<int> _nativeFlacMagic = <int>[0x66, 0x4C, 0x61, 0x43];
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

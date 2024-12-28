import 'dart:io';
import 'dart:typed_data';
import 'package:audio_codec/src/utils/buffer.dart';
import 'package:test/test.dart';

void main() {
  group('Buffer', () {
    late Directory tempDir;
    late File tempFile;
    late Buffer buffer;

    setUp(() async {
      // Create a temporary directory and file for testing
      tempDir = await Directory.systemTemp.createTemp('buffer_test');
      tempFile = File('${tempDir.path}/test_file.bin');
    });

    tearDown(() async {
      // Clean up the temporary directory and file
      await tempDir.delete(recursive: true);
    });

    test('read - basic read within buffer', () async {
      // Write some data to the temporary file
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      final readData = buffer.read(4);
      expect(readData, equals([1, 2, 3, 4]));
      expect(buffer.cursor, equals(4));
    });

    test('read - read across buffer boundary', () async {
      final data = Uint8List.fromList(List.generate(20000, (i) => i % 256));
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      final readData = buffer.read(18000);
      expect(readData, equals(data.sublist(0, 18000)));
    });

    test('read - large read exceeding buffer size', () async {
      final data = Uint8List.fromList(List.generate(35000, (i) => i % 256));
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      final readData = buffer.read(35000);
      expect(readData, equals(data));
      expect(buffer.cursor, equals(0)); // Cursor should reset after _fill()
    });

    test('setPositionSync - move to a specific position', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      buffer.setPositionSync(4);
      final readData = buffer.read(4);
      expect(readData, equals([5, 6, 7, 8]));
    });

    test('skip - skip within buffer', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      buffer.skip(4);
      final readData = buffer.read(4);
      expect(readData, equals([5, 6, 7, 8]));
    });

    test('skip - skip across buffer boundary', () async {
      final data = Uint8List.fromList(List.generate(20000, (i) => i % 256));
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      buffer.skip(18000);
      final readData = buffer.read(2000);
      expect(readData, equals(data.sublist(18000)));
    });

    test('readBit - read individual bits', () async {
      // 01101000 00011001 01101000
      final data = Uint8List.fromList([0x68, 0x19, 0x68]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(1));
      expect(buffer.readBit(), equals(1));
      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(1));
      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(0));

      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(1));
      expect(buffer.readBit(), equals(1));
      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(0));
      expect(buffer.readBit(), equals(1));

      expect(buffer.readBit(), equals(0));
    });

    test('readUnsigned - read multiple bits as unsigned integer', () async {
      // 01101000 11010001 01101000
      final data = Uint8List.fromList([0x68, 0xD1, 0x68]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      // 01101 000110 10001011 01000
      expect(buffer.readUnsigned(5), equals(13)); // 01101
      expect(buffer.readUnsigned(6), equals(6)); // 000001
      expect(buffer.readUnsigned(8), equals(139)); // 10001011
      expect(buffer.readUnsigned(5), equals(8)); // 01000
    });

    test('readUnsigned - read across byte boundaries', () async {
      // 11001010 01101000 11101000
      final data = Uint8List.fromList([0xCA, 0x68, 0xE8]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      expect(buffer.readUnsigned(12), equals(0xCA6));
      expect(buffer.readUnsigned(12), equals(0x8E8));
    });

    test('readSigned - read multiple bits as signed integer', () async {
      // 01101000 11010001 01101000
      final data = Uint8List.fromList([0x68, 0xD1, 0x68]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      // 01101 000110 10001011 01000
      expect(buffer.readSigned(5), equals(13)); // 01101
      expect(buffer.readSigned(6), equals(6)); // 000110
      expect(buffer.readSigned(8), equals(-117)); // 10001011
      expect(buffer.readSigned(5), equals(8)); // 01000
    });

    test('readUnsigned and readSigned - read across buffer boundaries',
        () async {
      final data = Uint8List.fromList(List.generate(20000, (i) => i % 256));
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      expect(buffer.readUnsigned(12), equals(0x001));
      expect(buffer.readUnsigned(10), equals(0x202));

      buffer.setPositionSync(0);

      expect(buffer.readSigned(12), equals(1));
      expect(buffer.readSigned(10), equals(258));
    });

    test('setPositionSync - sets position correctly after read', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      buffer.read(2); // Read first 2 bytes
      buffer.setPositionSync(5); // Move to position 5
      final readData = buffer.read(3);

      expect(readData, equals([6, 7, 8]));
    });

    test('skip - skips correctly after read', () async {
      final data = Uint8List.fromList(
          [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      buffer.read(3); // Read first 3 bytes
      buffer.skip(4); // Skip next 4 bytes
      final readData = buffer.read(5);

      expect(readData, equals([8, 9, 10, 11, 12]));
    });

    test('read - reads correctly after skip', () async {
      final data = Uint8List.fromList(
          [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
      await tempFile.writeAsBytes(data);

      buffer = Buffer(randomAccessFile: await tempFile.open());

      buffer.skip(5); // Skip first 5 bytes
      final readData = buffer.read(6); // Read next 6 bytes

      expect(readData, equals([6, 7, 8, 9, 10, 11]));
    });
  });
}

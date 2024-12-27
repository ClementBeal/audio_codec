import 'dart:io';

class PcmEncoder {
  void encode(File file, List<List<int>> channels, int bitdepth) {
    final writer = file.openSync(mode: FileMode.writeOnly);

    int channelDataLength = channels.first.length;

    for (int dataId = 0; dataId < channelDataLength; dataId++) {
      for (int channelId = 0; channelId < channels.length; channelId++) {
        if (bitdepth == 8) {
          writer.writeByteSync(0);
        } else if (bitdepth == 16) {
          writer.writeByteSync(0);
        } else if (bitdepth == 24) {
          writer.writeByteSync(0);
        } else if (bitdepth == 32) {
          writer.writeByteSync(0);
        }
      }
    }

    writer.flushSync();
    writer.closeSync();
  }
}

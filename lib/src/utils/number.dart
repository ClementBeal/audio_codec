extension Int32ToBytes on int {
  /// Tranform an integer into a 16LE integer
  List<int> toBytes(int bitDepth) {
    if (0 < bitDepth && bitDepth <= 8) {
      return [this & 0xFF];
    }

    // Assuming 16-bit little-endian
    return [
      this & 0xFF,
      (this >> 8) & 0xFF,
    ];
  }
}

/// Compare that [list1] and [list2] are stricly equals
bool areListsEqual(List<int>? list1, List<int>? list2) {
  if (list1 == null && list2 == null) return true;
  if (list1 == null || list2 == null) return false;
  if (list1.length != list2.length) return false;

  for (int i = 0; i < list1.length; i++) {
    if (list1[i] != list2[i]) return false;
  }

  return true;
}

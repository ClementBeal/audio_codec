import 'package:audio_codec/src/flac/flac_decoder.dart';

void computeLinearPredictor(
    int linearPredictorOrder,
    int blockSize,
    Samples samples,
    Samples coefficients,
    int rightShiftNeeded,
    Samples residuals) {
  for (int i = linearPredictorOrder; i < blockSize; i++) {
    for (int j = 0; j < linearPredictorOrder; j++) {
      samples[i] += coefficients[j] * samples[i - 1 - j];
    }

    samples[i] =
        (samples[i] >> rightShiftNeeded) + residuals[i - linearPredictorOrder];
  }
}

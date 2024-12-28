import 'dart:io';

const nbWarmup = 2;
const nbRuns = 20;
const exeName = "audio_codec.exe";

void main(List<String> args) {
  Process.runSync("dart", ["compile", "exe", "-o", exeName, "bin/main.dart"]);

  runFlacBenchmark();
}
// subprocess.check_call(['hyperfine', '-m', '20', f'{ffmpeg} -threads 1 -benchmark -v 0 -i {filepath} -f null -', f'{symphonia} --decode-only {filepath}'])

void runBenchmark(String title, String filepath) {
  print("------- $title -------\n");

  final result = Process.runSync("hyperfine", [
    "--warmup",
    "$nbWarmup",
    '--runs',
    '$nbRuns',
    "ffmpeg -y -threads 1 -v 0 -benchmark  -i '$filepath' -f null -",
    "./$exeName '$filepath' a.wav",
  ]);

  if (result.exitCode != 0) {
    print("Error running hyperfine:");
    print("Exit code: ${result.exitCode}");
    print("Stderr: ${result.stderr}");
  } else {
    print(result.stdout);
  }
}

void runFlacBenchmark() {
  final file =
      r"/media/clement/Stockage/Musics/music/2018 - A 20 Something Fuck/02. You Say.flac";

  runBenchmark("Flac", file);
}

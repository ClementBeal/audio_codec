import 'dart:io';
import 'package:path/path.dart' as p;

const nbWarmup = 2;
const nbRuns = 20;
const exeName = "audio_codec.exe";

void main(List<String> args) {
  Process.runSync("dart", ["compile", "exe", "-o", exeName, "bin/main.dart"]);

  // runFlacBenchmark();
  runPCMBenchmark();
}

void runBenchmark(String title, String filepath,
    [List<String>? ffmpegArguments, List<String>? dartArguments]) {
  print("------- $title -------\n");

  print(
      "ffmpeg -y -threads 1 -v 0 -benchmark ${ffmpegArguments?.join(" ") ?? ''} -i '$filepath' -f null -");

  final result = Process.runSync(
    "hyperfine",
    [
      "--warmup",
      "$nbWarmup",
      '--runs',
      '$nbRuns',
      "ffmpeg -y -threads 1 -v 0 -benchmark ${ffmpegArguments?.join(" ") ?? ''} -i '$filepath' -f null -",
      "./$exeName '$filepath' ${dartArguments?.join(" ") ?? ''}",
    ],
  );

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

void runPCMBenchmark() {
  final folder = "benchmarks/pcm_files";

  // List of PCM formats
  final pcmFiles = [
    "pcm_u8.pcm",
    "pcm_s8.pcm",
    "pcm_u16be.pcm",
    "pcm_u16le.pcm",
    "pcm_s16be.pcm",
    "pcm_s16le.pcm",
    "pcm_u24be.pcm",
    "pcm_u24le.pcm",
    "pcm_s24be.pcm",
    "pcm_s24le.pcm",
    "pcm_u32be.pcm",
    "pcm_u32le.pcm",
    "pcm_s32be.pcm",
    "pcm_s32le.pcm",
  ];

  for (var pcmFile in pcmFiles) {
    final filePath = p.join(folder, pcmFile);
    final a = p.basenameWithoutExtension(pcmFile).split("pcm_").last;

    if (File(filePath).existsSync()) {
      runBenchmark("PCM: $a", filePath, ["-ar 44100 -ac 1 -f $a"], [a]);
    } else {
      print("File not found: $filePath");
    }
  }
}

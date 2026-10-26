import 'dart:io';

import 'package:ujumbe/ujumbe.dart';

import 'src/pack_files.dart';

/// Validates every pack under `packs/` (or the directories given) and runs
/// its fixtures. Exits non-zero if any pack fails.
///
///     dart run tool/check_packs.dart [packs/mpesa ...]
void main(List<String> args) {
  final dirs = args.isEmpty
      ? packDirectories(Directory('packs'))
      : [for (final a in args) Directory(a)];
  var failed = 0;
  for (final dir in dirs) {
    try {
      final loaded = PackDirectory.load(dir);
      final report = loaded.fixtures.run(loaded.pack);
      final label = '${loaded.pack.id} ${loaded.pack.version}';
      if (report.passed) {
        stdout.writeln('PASS $label (${report.sampleCount} samples)');
      } else {
        failed++;
        stdout.writeln('FAIL $label');
        for (final f in report.failures) {
          stdout.writeln('  - $f');
        }
      }
    } on PackFormatException catch (e) {
      failed++;
      stdout.writeln('FAIL $e');
    }
  }
  if (dirs.isEmpty) {
    stderr.writeln('No packs found.');
    exitCode = 1;
  } else if (failed > 0) {
    stderr.writeln('$failed of ${dirs.length} packs failed.');
    exitCode = 1;
  }
}

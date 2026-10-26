import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'src/pack_files.dart';
import 'src/release.dart';
import 'src/signing_key.dart';

/// Builds a signed over-the-air release of every pack: each pack file and
/// its signature, plus a signed `index.json` listing them.
///
///     UJUMBE_SIGNING_KEY=<base64 seed> dart run tool/build_release.dart
///     dart run tool/build_release.dart --key-file /secure/path/seed --out build/release
///
/// The key is never printed; only its public half is.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('key-file', help: 'File holding the base64 private seed.')
    ..addOption(
      'out',
      defaultsTo: 'build/release',
      help: 'Directory to write the release into; must be empty.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (e) {
    return _usage(parser, e.message);
  }
  if (options.flag('help')) return _usage(parser);

  final dirs = options.rest.isEmpty
      ? packDirectories(Directory('packs'))
      : [for (final path in options.rest) Directory(path)];
  try {
    final signer = await loadSigner(options.option('key-file'));
    final out = Directory(options.option('out')!);
    final index = await buildRelease(packDirs: dirs, out: out, signer: signer);
    for (final e in index.entries) {
      stdout.writeln('Signed ${e.id} ${e.version} (engine ${e.minEngine}+)');
    }
    stdout
      ..writeln('Wrote ${out.path}/$indexFileName and signatures.')
      ..writeln('Public key: ${base64.encode(await signer.publicKey())}');
  } on SigningKeyException catch (e) {
    return _usage(parser, e.message);
  } on Exception catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}

void _usage(ArgParser parser, [String? error]) {
  if (error != null) {
    stderr.writeln(error);
    exitCode = 64;
  }
  stdout
    ..writeln('Usage: dart run tool/build_release.dart [options] [pack-dir...]')
    ..writeln(parser.usage);
}

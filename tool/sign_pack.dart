import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ujumbe/ujumbe.dart';

import 'src/pack_files.dart';
import 'src/signing_key.dart';

/// Signs a pack after its fixtures pass, writing `pack.yaml.sig` beside it.
///
///     UJUMBE_SIGNING_KEY=<base64 seed> dart run tool/sign_pack.dart packs/mpesa
///     dart run tool/sign_pack.dart --key-file /secure/path/seed packs/mpesa
///     dart run tool/sign_pack.dart --generate-key /secure/path/seed
///
/// The key is a base64 32-byte Ed25519 seed. Keep it outside the repo, in a
/// hardware key or secrets manager.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('key-file', help: 'File holding the base64 private seed.')
    ..addOption(
      'generate-key',
      valueHelp: 'path',
      help: 'Write a new base64 seed to <path> and print its public key.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (e) {
    return _usage(parser, e.message);
  }
  if (options.flag('help')) return _usage(parser);

  final generatePath = options.option('generate-key');
  if (generatePath != null) return _generate(generatePath);

  if (options.rest.length != 1) {
    return _usage(parser, 'Give exactly one pack directory.');
  }
  final PackSigner signer;
  try {
    signer = await loadSigner(options.option('key-file'));
  } on SigningKeyException catch (e) {
    return _usage(parser, e.message);
  }

  final dir = Directory(options.rest.single);
  final loaded = PackDirectory.load(dir);
  final report = loaded.fixtures.run(loaded.pack);
  if (!report.passed) {
    stderr.writeln('Refusing to sign ${loaded.pack.id}: fixtures fail.');
    report.failures.forEach(stderr.writeln);
    exitCode = 1;
    return;
  }

  final packFile = File('${dir.path}/pack.yaml');
  final bytes = packFile.readAsBytesSync();
  final signature = await signer.sign(bytes);
  final verifier = PackVerifier([await signer.publicKey()]);
  await verifier.loadVerified(bytes, signature, source: packFile.path);

  File('${packFile.path}.sig').writeAsStringSync('$signature\n');
  stdout
    ..writeln('Signed ${loaded.pack.id} ${loaded.pack.version}')
    ..writeln('Public key: ${base64.encode(await signer.publicKey())}');
}

Future<void> _generate(String path) async {
  final file = File(path);
  if (file.existsSync()) {
    stderr.writeln('$path already exists; not overwriting.');
    exitCode = 1;
    return;
  }
  final signer = await PackSigner.generate();
  file.writeAsStringSync('${base64.encode(await signer.seed())}\n');
  if (!Platform.isWindows) await Process.run('chmod', ['600', path]);
  stdout
    ..writeln('Private seed written to $path. Never commit it.')
    ..writeln('Public key: ${base64.encode(await signer.publicKey())}');
}

void _usage(ArgParser parser, [String? error]) {
  if (error != null) {
    stderr.writeln(error);
    exitCode = 64;
  }
  stdout
    ..writeln('Usage: dart run tool/sign_pack.dart [options] <pack-dir>')
    ..writeln(parser.usage);
}

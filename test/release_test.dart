import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import '../tool/src/pack_files.dart';
import '../tool/src/release.dart';
import '../tool/src/signing_key.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('ujumbe_release'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('builds a release that a phone accepts', () async {
    final signer = await PackSigner.generate();
    final out = Directory('${temp.path}/release');
    final index = await buildRelease(
      packDirs: packDirectories(Directory('packs')),
      out: out,
      signer: signer,
    );
    expect(index.entries.map((e) => e.id), bundledPackIds);

    String read(String name) => File('${out.path}/$name').readAsStringSync();
    final result = await PackUpdateVerifier([await signer.publicKey()]).verify(
      indexBytes: utf8.encode(read(indexFileName)),
      indexSignature: read('$indexFileName.sig'),
      packs: {
        for (final e in index.entries)
          e.id: PackDownload(utf8.encode(read(e.file)), read(e.signature)),
      },
      installedVersions: const {},
    );
    expect(result.rejected, isEmpty);
    expect(result.accepted, hasLength(index.entries.length));

    expect(
      () => buildRelease(packDirs: const [], out: out, signer: signer),
      throwsA(isA<ReleaseException>()),
    );
  });

  test(
    'loads the key from a file or the environment, never echoing it',
    () async {
      final signer = await PackSigner.generate();
      final seed = base64.encode(await signer.seed());
      final file = File('${temp.path}/key.seed')..writeAsStringSync('$seed\n');

      for (final loaded in [
        await loadSigner(file.path),
        await loadSigner(null, environment: {signingKeyVariable: seed}),
      ]) {
        expect(await loaded.publicKey(), await signer.publicKey());
      }

      const secret = 'not-base64-but-secret!';
      for (final env in [
        <String, String>{},
        {signingKeyVariable: secret},
        {signingKeyVariable: base64.encode(List.filled(16, 1))},
      ]) {
        await expectLater(
          loadSigner(null, environment: env),
          throwsA(
            isA<SigningKeyException>().having(
              (e) => e.message,
              'message',
              isNot(contains(secret)),
            ),
          ),
        );
      }
    },
  );
}

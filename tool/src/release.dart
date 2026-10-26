import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ujumbe/ujumbe.dart';

import 'pack_files.dart';

/// Name of the index file in a release.
const indexFileName = 'index.json';

/// Thrown when a release cannot be built.
class ReleaseException implements Exception {
  /// Creates an exception with [message].
  const ReleaseException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Builds a signed release of the packs in [packDirs] into [out]:
/// `<id>.pack.yaml` and `<id>.pack.yaml.sig` for each pack, then
/// `index.json` and `index.json.sig`.
///
/// Refuses packs whose fixtures fail and an [out] directory that is not
/// empty, then checks the result with [PackUpdateVerifier] as a phone would.
Future<PackIndex> buildRelease({
  required List<Directory> packDirs,
  required Directory out,
  required PackSigner signer,
}) async {
  if (out.existsSync() && out.listSync().isNotEmpty) {
    throw ReleaseException('${out.path} is not empty.');
  }
  out.createSync(recursive: true);

  final entries = <PackIndexEntry>[];
  final downloads = <String, PackDownload>{};
  for (final dir in packDirs) {
    final loaded = PackDirectory.load(dir);
    final pack = loaded.pack;
    final report = loaded.fixtures.run(pack);
    if (!report.passed) {
      throw ReleaseException(
        'Refusing to release ${pack.id}: fixtures fail.\n'
        '${report.failures.join('\n')}',
      );
    }
    final bytes = File('${dir.path}/pack.yaml').readAsBytesSync();
    final entry = PackIndexEntry(
      id: pack.id,
      version: pack.version,
      minEngine: pack.minEngineVersion,
      sha256: sha256.convert(bytes).toString(),
      file: '${pack.id}.pack.yaml',
      signature: '${pack.id}.pack.yaml.sig',
    );
    final signature = await signer.sign(bytes);
    File('${out.path}/${entry.file}').writeAsBytesSync(bytes);
    File('${out.path}/${entry.signature}').writeAsStringSync('$signature\n');
    entries.add(entry);
    downloads[entry.id] = PackDownload(bytes, signature);
  }

  final index = PackIndex(entries..sort((a, b) => a.id.compareTo(b.id)));
  final indexBytes = utf8.encode(index.toJson());
  final indexSignature = await signer.sign(indexBytes);
  File('${out.path}/$indexFileName').writeAsBytesSync(indexBytes);
  File('${out.path}/$indexFileName.sig').writeAsStringSync('$indexSignature\n');

  final check = await PackUpdateVerifier([await signer.publicKey()]).verify(
    indexBytes: indexBytes,
    indexSignature: indexSignature,
    packs: downloads,
    installedVersions: const {},
  );
  if (check.rejected.isNotEmpty) {
    throw ReleaseException(
      'The release does not verify:\n${check.rejected.join('\n')}',
    );
  }
  return index;
}

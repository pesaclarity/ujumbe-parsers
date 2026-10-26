import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'helpers.dart';

/// A signed release built in memory with a throwaway key.
class _Release {
  _Release(this.indexBytes, this.indexSignature, this.packs);

  List<int> indexBytes;
  String indexSignature;
  final Map<String, PackDownload> packs;
}

String _pack({String version = '1.1.0', String? minEngine}) => testPackYaml
    .replaceFirst('version: 1.0.0', 'version: $version')
    .replaceFirst(
      'currency:',
      '${minEngine == null ? '' : 'min_engine: $minEngine\n'}currency:',
    );

Future<_Release> _release(
  PackSigner signer, {
  String version = '1.1.0',
  String? minEngine,
  String? indexMinEngine,
}) async {
  final bytes = utf8.encode(_pack(version: version, minEngine: minEngine));
  final index = PackIndex([
    PackIndexEntry(
      id: 'example_wallet',
      version: version,
      minEngine: indexMinEngine ?? minEngine ?? firstEngineVersion,
      sha256: sha256.convert(bytes).toString(),
      file: 'example_wallet.pack.yaml',
      signature: 'example_wallet.pack.yaml.sig',
    ),
  ]);
  final indexBytes = utf8.encode(index.toJson());
  return _Release(indexBytes, await signer.sign(indexBytes), {
    'example_wallet': PackDownload(bytes, await signer.sign(bytes)),
  });
}

const _installed = {'example_wallet': '1.0.0'};

void main() {
  late PackSigner signer;
  late PackUpdateVerifier verifier;

  setUp(() async {
    signer = await PackSigner.generate();
    verifier = PackUpdateVerifier([await signer.publicKey()]);
  });

  Future<PackUpdateResult> check(
    _Release r, {
    PackUpdateVerifier? using,
    Map<String, String> installed = _installed,
  }) => (using ?? verifier).verify(
    indexBytes: r.indexBytes,
    indexSignature: r.indexSignature,
    packs: r.packs,
    installedVersions: installed,
  );

  List<PackRejectionReason> reasons(PackUpdateResult result) => [
    for (final r in result.rejected) r.reason,
  ];

  test('accepts a correctly signed, newer, compatible pack', () async {
    final result = await check(await _release(signer));
    expect(result.rejected, isEmpty);
    expect(result.accepted.single.pack.id, 'example_wallet');
    expect(result.accepted.single.pack.version, '1.1.0');
  });

  test('offers a pack the phone does not have yet', () async {
    final r = await _release(signer);
    final result = await check(r, installed: const {});
    expect(result.accepted, hasLength(1));
    final index = await verifier.verifyIndex(r.indexBytes, r.indexSignature);
    expect(verifier.offered(index, installedVersions: const {}), hasLength(1));
    expect(
      verifier.offered(index, installedVersions: _installed),
      hasLength(1),
    );
  });

  test('rejects a pack changed after release', () async {
    final r = await _release(signer);
    final original = r.packs['example_wallet']!;
    final tampered = utf8.encode(
      utf8
          .decode(original.packBytes)
          .replaceFirst('direction: out', 'direction: in'),
    );
    r.packs['example_wallet'] = PackDownload(tampered, original.signature);
    final result = await check(r);
    expect(result.accepted, isEmpty);
    expect(reasons(result), [PackRejectionReason.hashMismatch]);
  });

  test('rejects an index changed after signing', () async {
    final r = await _release(signer);
    r.indexBytes = utf8.encode(
      utf8.decode(r.indexBytes).replaceFirst('"1.1.0"', '"9.9.9"'),
    );
    final result = await check(r);
    expect(result.accepted, isEmpty);
    expect(result.rejected.single.packId, isNull);
    expect(reasons(result), [PackRejectionReason.indexSignatureInvalid]);
    expect(
      verifier.verifyIndex(r.indexBytes, r.indexSignature),
      throwsA(isA<PackIndexException>()),
    );
  });

  test('rejects a release signed with an untrusted key', () async {
    final stranger = await PackSigner.generate();
    final result = await check(await _release(stranger));
    expect(reasons(result), [PackRejectionReason.indexSignatureInvalid]);
  });

  test(
    'rejects a pack signed with an untrusted key under a valid index',
    () async {
      final r = await _release(signer);
      final stranger = await PackSigner.generate();
      final download = r.packs['example_wallet']!;
      r.packs['example_wallet'] = PackDownload(
        download.packBytes,
        await stranger.sign(download.packBytes),
      );
      expect(reasons(await check(r)), [PackRejectionReason.signatureInvalid]);
    },
  );

  test('accepts either key during rotation', () async {
    final oldKey = await PackSigner.generate();
    final newKey = await PackSigner.generate();
    final both = PackUpdateVerifier([
      await oldKey.publicKey(),
      await newKey.publicKey(),
    ]);
    for (final key in [oldKey, newKey]) {
      final result = await check(await _release(key), using: both);
      expect(result.accepted, hasLength(1));
    }
  });

  test('rejects a pack that needs a newer engine', () async {
    final r = await _release(signer, minEngine: '0.2.0');
    final old = PackUpdateVerifier([await signer.publicKey()], engine: '0.1.0');
    expect(reasons(await check(r, using: old)), [
      PackRejectionReason.engineTooOld,
    ]);
    final index = await old.verifyIndex(r.indexBytes, r.indexSignature);
    expect(old.offered(index, installedVersions: _installed), isEmpty);
  });

  test(
    'rejects a pack whose own min_engine is newer than the index says',
    () async {
      final r = await _release(
        signer,
        minEngine: '99.0.0',
        indexMinEngine: '0.1.0',
      );
      expect(reasons(await check(r)), [PackRejectionReason.packInvalid]);
    },
  );

  test('rejects a downgrade and a re-release of the same version', () async {
    for (final version in ['0.9.0', '1.0.0', '1.0.0-beta.1']) {
      final r = await _release(signer, version: version);
      expect(reasons(await check(r)), [PackRejectionReason.notNewer]);
    }
  });

  test('rejects a pack whose contents disagree with its index entry', () async {
    final r = await _release(signer);
    final bytes = utf8.encode(_pack(version: '1.2.0'));
    final index = PackIndex([
      PackIndexEntry(
        id: 'example_wallet',
        version: '1.1.0',
        minEngine: firstEngineVersion,
        sha256: sha256.convert(bytes).toString(),
        file: 'example_wallet.pack.yaml',
        signature: 'example_wallet.pack.yaml.sig',
      ),
    ]);
    r
      ..indexBytes = utf8.encode(index.toJson())
      ..indexSignature = await signer.sign(r.indexBytes);
    r.packs['example_wallet'] = PackDownload(bytes, await signer.sign(bytes));
    expect(reasons(await check(r)), [PackRejectionReason.packMismatch]);
  });

  test('reports packs missing from the download or from the index', () async {
    final r = await _release(signer);
    final download = r.packs.remove('example_wallet')!;
    r.packs['other_wallet'] = download;
    expect(reasons(await check(r)), [
      PackRejectionReason.notInIndex,
      PackRejectionReason.notDownloaded,
    ]);
  });

  test('rejects a signed but malformed index', () async {
    for (final json in [
      'not json',
      '{"format": 2, "packs": []}',
      '{"format": 1, "packs": [{"id": "x"}]}',
      '{"format": 1, "packs": [{"id": "a", "version": "1", "min_engine": '
          '"0.1.0", "sha256": "${'0' * 64}", "file": "a", "signature": "b"}]}',
      '{"format": 1, "packs": [{"id": "a", "version": "1.0.0", "min_engine": '
          '"0.1.0", "sha256": "${'0' * 64}", "file": "../a", "signature": "b"}]}',
    ]) {
      final bytes = utf8.encode(json);
      final result = await verifier.verify(
        indexBytes: bytes,
        indexSignature: await signer.sign(bytes),
        packs: const {},
      );
      expect(reasons(result), [
        PackRejectionReason.indexMalformed,
      ], reason: json);
    }
  });

  test(
    'an index round-trips through JSON and ignores unknown fields',
    () async {
      final r = await _release(signer);
      final json =
          jsonDecode(utf8.decode(r.indexBytes)) as Map<String, Object?>;
      json['published'] = '2026-10-26';
      final index = PackIndex.fromJson(utf8.encode(jsonEncode(json)));
      expect(index['example_wallet']!.version, '1.1.0');
      expect(utf8.encode(index.toJson()), r.indexBytes);
    },
  );

  test('defaults to the bundled pack versions', () async {
    expect(bundledPackVersions(), containsPair('mpesa', isNotEmpty));
  });
}

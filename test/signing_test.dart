import 'dart:convert';

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'helpers.dart';

void main() {
  final bytes = utf8.encode(testPackYaml);

  test('loads a pack signed by a trusted key', () async {
    final signer = await PackSigner.generate();
    final verifier = PackVerifier([await signer.publicKey()]);
    final pack = await verifier.loadVerified(bytes, await signer.sign(bytes));
    expect(pack.id, 'example_wallet');
  });

  test('accepts any of several trusted keys, for rotation', () async {
    final oldKey = await PackSigner.generate();
    final newKey = await PackSigner.generate();
    final verifier = PackVerifier([
      await oldKey.publicKey(),
      await newKey.publicKey(),
    ]);
    expect(
      await verifier.verify(bytes, base64.decode(await newKey.sign(bytes))),
      isTrue,
    );
  });

  test('a seed reproduces the same key', () async {
    final signer = await PackSigner.generate();
    final again = await PackSigner.fromSeed(await signer.seed());
    expect(await again.publicKey(), await signer.publicKey());
  });

  test('rejects a pack signed by an untrusted key', () async {
    final trusted = await PackSigner.generate();
    final stranger = await PackSigner.generate();
    final verifier = PackVerifier([await trusted.publicKey()]);
    expect(
      verifier.loadVerified(bytes, await stranger.sign(bytes)),
      throwsA(isA<PackSignatureException>()),
    );
  });

  test('rejects a pack changed after signing', () async {
    final signer = await PackSigner.generate();
    final verifier = PackVerifier([await signer.publicKey()]);
    final signature = await signer.sign(bytes);
    final tampered = utf8.encode(testPackYaml.replaceFirst('out', 'in'));
    expect(
      verifier.loadVerified(tampered, signature),
      throwsA(isA<PackSignatureException>()),
    );
  });

  test('rejects malformed signatures and keys', () async {
    final signer = await PackSigner.generate();
    final verifier = PackVerifier([await signer.publicKey()]);
    expect(
      verifier.loadVerified(bytes, 'not base64!'),
      throwsA(isA<PackSignatureException>()),
    );
    expect(await verifier.verify(bytes, [1, 2, 3]), isFalse);
    expect(() => PackVerifier([]), throwsArgumentError);
    expect(() => PackVerifier([List.filled(31, 0)]), throwsArgumentError);
  });
}

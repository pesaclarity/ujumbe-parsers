import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'pack.dart';

/// Thrown when a pack's signature does not verify against any trusted key.
class PackSignatureException implements Exception {
  /// Creates an exception with [message].
  const PackSignatureException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'PackSignatureException: $message';
}

/// Verifies Ed25519 signatures over pack files before they are used.
///
/// The signature is detached: raw Ed25519 signature bytes over the exact
/// bytes of `pack.yaml`, stored base64-encoded in `pack.yaml.sig`.
class PackVerifier {
  /// Trusts the given 32-byte Ed25519 public keys.
  ///
  /// More than one key allows rotation: ship the new key in an app update,
  /// then start signing with it.
  PackVerifier(Iterable<List<int>> trustedPublicKeys)
    : _keys = [
        for (final key in trustedPublicKeys)
          SimplePublicKey(_checkLength(key), type: KeyPairType.ed25519),
      ] {
    if (_keys.isEmpty) {
      throw ArgumentError.value(
        trustedPublicKeys,
        'trustedPublicKeys',
        'at least one key is required',
      );
    }
  }

  final List<SimplePublicKey> _keys;
  static final _ed25519 = Ed25519();

  /// Whether [signature] over [packBytes] verifies against a trusted key.
  Future<bool> verify(List<int> packBytes, List<int> signature) async {
    if (signature.length != 64) return false;
    for (final key in _keys) {
      final ok = await _ed25519.verify(
        packBytes,
        signature: Signature(signature, publicKey: key),
      );
      if (ok) return true;
    }
    return false;
  }

  /// Verifies [packBytes] against a base64 [signatureBase64] (the contents
  /// of a `.sig` file), then parses and validates the pack.
  ///
  /// Throws [PackSignatureException] before any parsing if the signature
  /// does not verify, and [PackFormatException] if the pack is malformed.
  Future<ParserPack> loadVerified(
    List<int> packBytes,
    String signatureBase64, {
    String source = 'pack',
  }) async {
    final List<int> signature;
    try {
      signature = base64.decode(signatureBase64.trim());
    } on FormatException {
      throw PackSignatureException('$source: signature is not valid base64');
    }
    if (!await verify(packBytes, signature)) {
      throw PackSignatureException(
        '$source: signature does not match any trusted key',
      );
    }
    return ParserPack.fromYaml(utf8.decode(packBytes), source: source);
  }

  static List<int> _checkLength(List<int> key) {
    if (key.length != 32) {
      throw ArgumentError(
        'Ed25519 public keys are 32 bytes, got ${key.length}',
      );
    }
    return List.unmodifiable(key);
  }
}

/// Signs pack files. Used by release tooling and tests, never on phones.
class PackSigner {
  PackSigner._(this._keyPair);

  /// Creates a signer from a 32-byte Ed25519 private key seed.
  static Future<PackSigner> fromSeed(List<int> seed) async {
    if (seed.length != 32) {
      throw ArgumentError('Ed25519 seeds are 32 bytes, got ${seed.length}');
    }
    return PackSigner._(await Ed25519().newKeyPairFromSeed(seed));
  }

  /// Creates a signer with a fresh random key pair (for tests and key
  /// generation).
  static Future<PackSigner> generate() async =>
      PackSigner._(await Ed25519().newKeyPair());

  final SimpleKeyPair _keyPair;

  /// The 32-byte public key to give to [PackVerifier].
  Future<List<int>> publicKey() async =>
      (await _keyPair.extractPublicKey()).bytes;

  /// The 32-byte private seed. Handle with care; never commit it.
  Future<List<int>> seed() => _keyPair.extractPrivateKeyBytes();

  /// Signs [packBytes] and returns the base64 detached signature.
  Future<String> sign(List<int> packBytes) async {
    final signature = await Ed25519().sign(packBytes, keyPair: _keyPair);
    return base64.encode(signature.bytes);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:ujumbe/ujumbe.dart';

/// Environment variable holding the base64 32-byte Ed25519 seed.
const signingKeyVariable = 'UJUMBE_SIGNING_KEY';

/// Thrown when the signing key is missing or malformed. Its message never
/// contains any part of the key.
class SigningKeyException implements Exception {
  /// Creates an exception with [message].
  const SigningKeyException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Loads the signer from [keyFile] if given, otherwise from
/// [signingKeyVariable].
///
/// Throws [SigningKeyException] without echoing the key, since tools run in
/// CI where logs are public.
Future<PackSigner> loadSigner(
  String? keyFile, {
  Map<String, String>? environment,
}) async {
  final String? text;
  if (keyFile != null) {
    final file = File(keyFile);
    if (!file.existsSync()) {
      throw SigningKeyException('Key file $keyFile does not exist.');
    }
    text = file.readAsStringSync();
  } else {
    text = (environment ?? Platform.environment)[signingKeyVariable];
  }
  if (text == null || text.trim().isEmpty) {
    throw const SigningKeyException(
      'No signing key: pass --key-file or set $signingKeyVariable.',
    );
  }
  final List<int> seed;
  try {
    seed = base64.decode(text.trim());
  } on FormatException {
    throw const SigningKeyException('The signing key is not valid base64.');
  }
  if (seed.length != 32) {
    throw const SigningKeyException(
      'The signing key must be a base64 32-byte Ed25519 seed.',
    );
  }
  return PackSigner.fromSeed(seed);
}

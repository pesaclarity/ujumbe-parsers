import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bundled_packs.dart';
import 'pack.dart';
import 'signing.dart';
import 'version.dart';

/// The pack index format this engine reads.
const supportedIndexFormat = 1;

/// Why a downloaded index or pack was not accepted.
enum PackRejectionReason {
  /// The index signature does not verify against any trusted key.
  indexSignatureInvalid,

  /// The index is not valid JSON in the expected shape.
  indexMalformed,

  /// The pack needs a newer engine than this one.
  engineTooOld,

  /// The pack is not newer than the copy already on the phone.
  notNewer,

  /// The index offers the pack but its files were not supplied.
  notDownloaded,

  /// Pack files were supplied for an id the index does not list.
  notInIndex,

  /// The pack's SHA-256 differs from the one in the signed index.
  hashMismatch,

  /// The pack signature does not verify against any trusted key.
  signatureInvalid,

  /// The pack verified but is malformed, or needs a newer engine.
  packInvalid,

  /// The pack's id or version differs from its index entry.
  packMismatch,
}

/// One index or pack that was not accepted, and why.
class PackRejection {
  /// Creates a rejection.
  const PackRejection(this.reason, this.message, {this.packId});

  /// The pack concerned, or `null` when the whole index was rejected.
  final String? packId;

  /// Why it was rejected.
  final PackRejectionReason reason;

  /// A human-readable explanation, for logs.
  final String message;

  @override
  String toString() =>
      'PackRejection(${packId ?? 'index'}, ${reason.name}: $message)';
}

/// Thrown by [PackUpdateVerifier.verifyIndex] when the index is rejected.
class PackIndexException implements Exception {
  /// Wraps [rejection].
  const PackIndexException(this.rejection);

  /// Why the index was rejected.
  final PackRejection rejection;

  @override
  String toString() => 'PackIndexException: ${rejection.message}';
}

/// One pack listed in a [PackIndex].
class PackIndexEntry {
  /// Creates an entry.
  const PackIndexEntry({
    required this.id,
    required this.version,
    required this.minEngine,
    required this.sha256,
    required this.file,
    required this.signature,
  });

  /// The pack id, e.g. `mpesa`.
  final String id;

  /// The pack's version.
  final String version;

  /// The oldest engine version that can read the pack.
  final String minEngine;

  /// Lower-case hex SHA-256 of the exact `pack.yaml` bytes.
  final String sha256;

  /// Release asset name of the pack file, e.g. `mpesa.pack.yaml`.
  final String file;

  /// Release asset name of its detached signature.
  final String signature;

  /// The JSON form used in `index.json`.
  Map<String, Object> toJson() => {
    'id': id,
    'version': version,
    'min_engine': minEngine,
    'sha256': sha256,
    'file': file,
    'signature': signature,
  };
}

/// The signed list of released packs (`index.json`).
///
/// Unknown fields are ignored so that later releases can add fields without
/// breaking older apps; incompatible changes bump [supportedIndexFormat].
class PackIndex {
  /// Creates an index from [entries].
  PackIndex(Iterable<PackIndexEntry> entries)
    : entries = List.unmodifiable(entries);

  /// Parses an index from its JSON bytes.
  ///
  /// Throws [FormatException] describing the first problem found.
  factory PackIndex.fromJson(List<int> bytes) {
    final Object? doc;
    try {
      doc = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw FormatException('not valid JSON: ${e.message}');
    }
    if (doc is! Map<String, Object?>) {
      throw const FormatException('top level must be an object');
    }
    if (doc['format'] != supportedIndexFormat) {
      throw FormatException(
        'format ${doc['format']} is not supported '
        '(this engine reads $supportedIndexFormat)',
      );
    }
    final packs = doc['packs'];
    if (packs is! List<Object?>) {
      throw const FormatException('packs must be a list');
    }
    final seen = <String>{};
    final entries = <PackIndexEntry>[];
    for (var i = 0; i < packs.length; i++) {
      final entry = _readEntry(packs[i], 'packs[$i]');
      if (!seen.add(entry.id)) {
        throw FormatException('packs[$i]: duplicate id "${entry.id}"');
      }
      entries.add(entry);
    }
    return PackIndex(entries);
  }

  /// The packs in this release, one per id.
  final List<PackIndexEntry> entries;

  /// The entry for [id], or `null`.
  PackIndexEntry? operator [](String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The canonical JSON text written by the release tool.
  String toJson() =>
      '${const JsonEncoder.withIndent('  ').convert({
        'format': supportedIndexFormat,
        'packs': [for (final e in entries) e.toJson()],
      })}\n';

  static PackIndexEntry _readEntry(Object? node, String at) {
    if (node is! Map<String, Object?>) {
      throw FormatException('$at: must be an object');
    }
    String field(String key, RegExp pattern) {
      final value = node[key];
      if (value is! String || !pattern.hasMatch(value)) {
        throw FormatException('$at.$key: missing or malformed');
      }
      return value;
    }

    final version = field('version', _anything);
    final minEngine = field('min_engine', _anything);
    for (final (key, value) in [
      ('version', version),
      ('min_engine', minEngine),
    ]) {
      if (!isSemanticVersion(value)) {
        throw FormatException('$at.$key: "$value" is not a semantic version');
      }
    }
    return PackIndexEntry(
      id: field('id', _id),
      version: version,
      minEngine: minEngine,
      sha256: field('sha256', _sha256),
      file: field('file', _fileName),
      signature: field('signature', _fileName),
    );
  }

  static final _anything = RegExp('');
  static final _id = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');
  static final _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
}

/// A downloaded pack file and the contents of its `.sig` file.
class PackDownload {
  /// Creates a download.
  const PackDownload(this.packBytes, this.signature);

  /// The exact bytes of the pack file.
  final List<int> packBytes;

  /// The base64 detached signature.
  final String signature;
}

/// A pack that passed every check and may replace the installed copy.
class PackUpdate {
  /// Creates an update.
  const PackUpdate(this.entry, this.pack, this.packBytes, this.signature);

  /// Its entry in the signed index.
  final PackIndexEntry entry;

  /// The parsed, validated pack.
  final ParserPack pack;

  /// The verified bytes, for the app to store with [signature].
  final List<int> packBytes;

  /// The verified base64 signature.
  final String signature;
}

/// The outcome of [PackUpdateVerifier.verify].
class PackUpdateResult {
  /// Creates a result.
  const PackUpdateResult(this.accepted, this.rejected);

  /// Packs safe to install, in index order.
  final List<PackUpdate> accepted;

  /// Everything not accepted. A single entry with a `null` pack id means
  /// the index itself was rejected and nothing else was looked at.
  final List<PackRejection> rejected;
}

/// Checks over-the-air pack releases before the phone uses them.
///
/// A pack is accepted only when the index signature verifies against a
/// trusted key, the pack's SHA-256 matches its index entry, the pack's own
/// signature verifies, this engine is new enough, and the pack is newer than
/// the installed copy. Trusting several keys allows rotation; see
/// docs/RELEASING.md.
class PackUpdateVerifier {
  /// Trusts the given 32-byte Ed25519 public keys (pinned in the app).
  ///
  /// [engine] defaults to this package's [engineVersion]; tests override it.
  PackUpdateVerifier(
    Iterable<List<int>> trustedPublicKeys, {
    String engine = engineVersion,
  }) : _verifier = PackVerifier(trustedPublicKeys),
       _engine = engine;

  final PackVerifier _verifier;
  final String _engine;

  /// Verifies the index signature, then parses it.
  ///
  /// Throws [PackIndexException] if the signature does not verify or the
  /// index is malformed. Nothing in the index is read before the signature
  /// is checked.
  Future<PackIndex> verifyIndex(List<int> indexBytes, String signature) async {
    if (!await _verifier.verify(indexBytes, _decode(signature))) {
      throw const PackIndexException(
        PackRejection(
          PackRejectionReason.indexSignatureInvalid,
          'index signature does not match any trusted key',
        ),
      );
    }
    try {
      return PackIndex.fromJson(indexBytes);
    } on FormatException catch (e) {
      throw PackIndexException(
        PackRejection(
          PackRejectionReason.indexMalformed,
          'index: ${e.message}',
        ),
      );
    }
  }

  /// The entries of [index] worth downloading: compatible with this engine
  /// and newer than [installedVersions] (pack id to version; defaults to
  /// the bundled packs). Packs not installed at all are always offered.
  List<PackIndexEntry> offered(
    PackIndex index, {
    Map<String, String>? installedVersions,
  }) {
    final installed = installedVersions ?? bundledPackVersions();
    return [
      for (final e in index.entries)
        if (_compatibility(e, installed) == null) e,
    ];
  }

  /// Verifies a whole release: the signed index and the downloaded [packs]
  /// (by pack id). Returns the packs safe to install and a typed reason for
  /// everything else.
  ///
  /// [installedVersions] maps pack id to the version on the phone and
  /// defaults to the bundled packs.
  Future<PackUpdateResult> verify({
    required List<int> indexBytes,
    required String indexSignature,
    required Map<String, PackDownload> packs,
    Map<String, String>? installedVersions,
  }) async {
    final PackIndex index;
    try {
      index = await verifyIndex(indexBytes, indexSignature);
    } on PackIndexException catch (e) {
      return PackUpdateResult(const [], [e.rejection]);
    }
    final installed = installedVersions ?? bundledPackVersions();
    final accepted = <PackUpdate>[];
    final rejected = <PackRejection>[
      for (final id in packs.keys)
        if (index[id] == null)
          PackRejection(
            PackRejectionReason.notInIndex,
            '$id: not listed in the index',
            packId: id,
          ),
    ];
    for (final entry in index.entries) {
      final download = packs[entry.id];
      final problem =
          _compatibility(entry, installed) ??
          (download == null
              ? PackRejection(
                  PackRejectionReason.notDownloaded,
                  '${entry.id}: offered but its files were not supplied',
                  packId: entry.id,
                )
              : null);
      if (problem != null) {
        rejected.add(problem);
        continue;
      }
      final checked = await _checkPack(entry, download!);
      switch (checked) {
        case final PackUpdate update:
          accepted.add(update);
        case final PackRejection rejection:
          rejected.add(rejection);
      }
    }
    return PackUpdateResult(
      List.unmodifiable(accepted),
      List.unmodifiable(rejected),
    );
  }

  PackRejection? _compatibility(
    PackIndexEntry entry,
    Map<String, String> installed,
  ) {
    if (compareVersions(entry.minEngine, _engine) > 0) {
      return PackRejection(
        PackRejectionReason.engineTooOld,
        '${entry.id} ${entry.version}: needs engine ${entry.minEngine}, '
        'this engine is $_engine',
        packId: entry.id,
      );
    }
    final current = installed[entry.id];
    if (current != null && compareVersions(entry.version, current) <= 0) {
      return PackRejection(
        PackRejectionReason.notNewer,
        '${entry.id} ${entry.version}: not newer than installed $current',
        packId: entry.id,
      );
    }
    return null;
  }

  Future<Object> _checkPack(PackIndexEntry entry, PackDownload download) async {
    PackRejection reject(PackRejectionReason reason, String message) =>
        PackRejection(reason, '${entry.id}: $message', packId: entry.id);

    final bytes = download.packBytes;
    if (sha256.convert(bytes).toString() != entry.sha256) {
      return reject(
        PackRejectionReason.hashMismatch,
        'SHA-256 differs from the signed index',
      );
    }
    if (!await _verifier.verify(bytes, _decode(download.signature))) {
      return reject(
        PackRejectionReason.signatureInvalid,
        'signature does not match any trusted key',
      );
    }
    final ParserPack pack;
    try {
      pack = ParserPack.fromYaml(utf8.decode(bytes), source: entry.file);
    } on FormatException catch (e) {
      return reject(PackRejectionReason.packInvalid, e.message);
    } on PackFormatException catch (e) {
      return reject(PackRejectionReason.packInvalid, e.problems.join('; '));
    }
    if (pack.id != entry.id ||
        pack.version != entry.version ||
        pack.minEngineVersion != entry.minEngine) {
      return reject(
        PackRejectionReason.packMismatch,
        'pack says ${pack.id} ${pack.version} (engine '
        '${pack.minEngineVersion}), index says ${entry.id} ${entry.version} '
        '(engine ${entry.minEngine})',
      );
    }
    return PackUpdate(
      entry,
      pack,
      List.unmodifiable(bytes),
      download.signature,
    );
  }

  static List<int> _decode(String signature) {
    try {
      return base64.decode(signature.trim());
    } on FormatException {
      return const [];
    }
  }
}

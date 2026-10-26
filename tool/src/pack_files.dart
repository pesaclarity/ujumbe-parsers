import 'dart:io';

import 'package:ujumbe/ujumbe.dart';

/// A pack directory under `packs/`, with its pack and fixtures loaded.
class PackDirectory {
  PackDirectory._(this.directory, this.pack, this.fixtures);

  /// Loads `pack.yaml` and `fixtures.yaml` from [directory].
  ///
  /// Throws [PackFormatException] if either is malformed, or if the pack id
  /// does not match the directory name.
  static PackDirectory load(Directory directory) {
    final name = directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final packFile = File('${directory.path}/pack.yaml');
    final fixturesFile = File('${directory.path}/fixtures.yaml');
    for (final file in [packFile, fixturesFile]) {
      if (!file.existsSync()) {
        throw PackFormatException(file.path, ['file is missing']);
      }
    }
    final pack = ParserPack.fromYaml(
      packFile.readAsStringSync(),
      source: packFile.path,
    );
    if (pack.id != name) {
      throw PackFormatException(packFile.path, [
        'id "${pack.id}" must match its directory name "$name"',
      ]);
    }
    final fixtures = PackFixtures.fromYaml(
      fixturesFile.readAsStringSync(),
      source: fixturesFile.path,
    );
    return PackDirectory._(directory, pack, fixtures);
  }

  /// Where the pack lives.
  final Directory directory;

  /// The validated pack.
  final ParserPack pack;

  /// Its synthetic samples.
  final PackFixtures fixtures;
}

/// Every pack directory under [root], sorted by name.
List<Directory> packDirectories(Directory root) =>
    root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

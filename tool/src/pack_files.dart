import 'dart:io';

import 'package:ujumbe/ujumbe.dart';

/// A pack directory under `packs/`, with its pack and fixtures loaded.
class PackDirectory {
  PackDirectory._(
    this.directory,
    this.pack,
    this.fixtures, {
    this.statementPack,
    this.statementFixtures,
  });

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
    final statementFile = File('${directory.path}/statement.yaml');
    final statementFixturesFile = File(
      '${directory.path}/statement_fixtures.yaml',
    );
    StatementPack? statementPack;
    StatementFixtures? statementFixtures;
    if (statementFile.existsSync()) {
      if (!statementFixturesFile.existsSync()) {
        throw PackFormatException(statementFixturesFile.path, [
          'file is missing',
        ]);
      }
      statementPack = StatementPack.fromYaml(
        statementFile.readAsStringSync(),
        source: statementFile.path,
      );
      if (statementPack.institution != pack.id) {
        throw PackFormatException(statementFile.path, [
          'institution "${statementPack.institution}" must be "${pack.id}"',
        ]);
      }
      statementFixtures = StatementFixtures.fromYaml(
        statementFixturesFile.readAsStringSync(),
        source: statementFixturesFile.path,
      );
    }
    return PackDirectory._(
      directory,
      pack,
      fixtures,
      statementPack: statementPack,
      statementFixtures: statementFixtures,
    );
  }

  /// Where the pack lives.
  final Directory directory;

  /// The validated pack.
  final ParserPack pack;

  /// Its synthetic samples.
  final PackFixtures fixtures;

  /// The institution's statement pack (`statement.yaml`), if it has one.
  final StatementPack? statementPack;

  /// Synthetic statements for [statementPack].
  final StatementFixtures? statementFixtures;
}

/// Every pack directory under [root], sorted by name.
List<Directory> packDirectories(Directory root) =>
    root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

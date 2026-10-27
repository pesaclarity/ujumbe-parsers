import '../bundled_packs.g.dart';
import 'statement_pack.dart';

/// Ids of the statement packs shipped with this package, sorted.
List<String> get bundledStatementPackIds =>
    bundledStatementPackSources.keys.toList()..sort();

/// Loads the bundled statement pack [id].
///
/// Throws [ArgumentError] if no statement pack with that id is bundled.
StatementPack loadBundledStatementPack(String id) {
  final source = bundledStatementPackSources[id];
  if (source == null) {
    throw ArgumentError.value(
      id,
      'id',
      'No bundled statement pack with this id',
    );
  }
  return StatementPack.fromYaml(source, source: 'bundled:$id');
}

/// Loads every bundled statement pack, in [bundledStatementPackIds] order.
List<StatementPack> loadBundledStatementPacks() => [
  for (final id in bundledStatementPackIds) loadBundledStatementPack(id),
];

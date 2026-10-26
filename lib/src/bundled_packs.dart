import 'bundled_packs.g.dart';
import 'pack.dart';

export 'bundled_packs.g.dart';

/// Ids of the packs shipped with this package, e.g. `mpesa`, sorted.
List<String> get bundledPackIds => bundledPackSources.keys.toList()..sort();

/// Loads the bundled pack [id].
///
/// Bundled packs ship inside the app, so they need no signature check.
/// Throws [ArgumentError] if no pack with that id is bundled.
ParserPack loadBundledPack(String id) {
  final source = bundledPackSources[id];
  if (source == null) {
    throw ArgumentError.value(id, 'id', 'No bundled pack with this id');
  }
  return ParserPack.fromYaml(source, source: 'bundled:$id');
}

/// Loads every bundled pack, in [bundledPackIds] order.
List<ParserPack> loadBundledPacks() => [
  for (final id in bundledPackIds) loadBundledPack(id),
];

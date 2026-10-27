import 'package:yaml/yaml.dart';

import 'time_format.dart';

/// Reads typed fields from a YAML mapping, collecting every problem found
/// instead of stopping at the first. Shared by the pack formats; not part
/// of the public API.
class YamlFieldReader {
  /// Reads [map]; problems go to [problems], each prefixed with [prefix].
  YamlFieldReader(this.map, this.problems, {this.prefix = ''});

  /// The mapping being read.
  final YamlMap map;

  /// Where problems are collected.
  final List<String> problems;

  /// Path of [map] in the file, for messages.
  final String prefix;

  /// Reports keys outside [allowed].
  void checkKeys(Set<String> allowed) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) problems.add('$prefix$key: unknown field');
    }
  }

  /// A non-empty string, optionally matching [pattern].
  String? string(String key, {RegExp? pattern, bool optional = false}) {
    final value = map[key];
    if (value == null) {
      if (!optional) problems.add('$prefix$key: is required');
      return null;
    }
    if (value is! String || value.isEmpty) {
      problems.add('$prefix$key: must be a non-empty string');
      return null;
    }
    if (pattern != null && !pattern.hasMatch(value)) {
      problems.add('$prefix$key: "$value" does not match ${pattern.pattern}');
      return null;
    }
    return value;
  }

  /// An integer.
  int? integer(String key) {
    final value = map[key];
    if (value is! int) {
      problems.add('$prefix$key: must be an integer');
      return null;
    }
    return value;
  }

  /// A boolean, or null when absent.
  bool? boolean(String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! bool) {
      problems.add('$prefix$key: must be true or false');
      return null;
    }
    return value;
  }

  /// A list of non-empty strings.
  List<String>? stringList(String key) {
    final value = map[key];
    if (value is! YamlList || value.any((e) => e is! String || e.isEmpty)) {
      problems.add('$prefix$key: must be a list of non-empty strings');
      return null;
    }
    return value.cast<String>().toList();
  }

  /// A [MessageTimeFormat] pattern.
  MessageTimeFormat? timeFormat(
    String key, {
    bool optional = false,
    bool dateOnly = false,
  }) {
    final text = string(key, optional: optional);
    if (text == null) return null;
    try {
      return MessageTimeFormat(text, dateOnly: dateOnly);
    } on FormatException catch (e) {
      problems.add('$prefix$key: ${e.message}');
      return null;
    }
  }
}

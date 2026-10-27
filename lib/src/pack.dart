import 'package:yaml/yaml.dart';

import 'time_format.dart';
import 'version.dart';
import 'yaml_reader.dart';

/// The pack format version this engine reads.
const supportedPackSchema = 1;

/// Named groups a rule pattern may capture.
const allowedGroups = {
  'receipt',
  'amount',
  'direction',
  'counterparty',
  'account',
  'balance',
  'fee',
  'time',
};

/// The engine version assumed when a pack does not set `min_engine`.
const firstEngineVersion = '0.1.0';

/// Which way money moved, from the account holder's point of view.
enum Direction {
  /// Money came into the account.
  incoming('in'),

  /// Money left the account.
  outgoing('out');

  const Direction(this.code);

  /// The value used in pack and fixture files.
  final String code;

  /// Looks up a direction by its [code], or returns `null`.
  static Direction? fromCode(String code) {
    for (final d in values) {
      if (d.code == code) return d;
    }
    return null;
  }
}

/// The kind of message a rule recognises.
enum TransactionType {
  /// Money sent to a person.
  sent('sent'),

  /// Money received from a person or organisation.
  received('received'),

  /// Payment to a paybill number, usually with an account reference.
  paybill('paybill'),

  /// Payment to a till (Buy Goods).
  till('till'),

  /// Cash withdrawn at an agent or ATM.
  withdrawal('withdrawal'),

  /// Airtime bought.
  airtime('airtime'),

  /// An overdraft draw, such as Fuliza M-Pesa.
  fuliza('fuliza'),

  /// An overdraft repayment.
  fulizaRepayment('fuliza_repayment'),

  /// A reversal of an earlier transaction.
  reversal('reversal'),

  /// A bank account debit or credit not covered by a more specific type;
  /// the direction says which.
  bank('bank');

  const TransactionType(this.code);

  /// The value used in pack and fixture files.
  final String code;

  /// Looks up a type by its [code], or returns `null`.
  static TransactionType? fromCode(String code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Thrown when a pack or fixture file is malformed.
class PackFormatException implements Exception {
  /// Creates an exception listing every [problems] found in [source].
  const PackFormatException(this.source, this.problems);

  /// Where the file came from, for messages (a path or pack id).
  final String source;

  /// Every problem found; validation does not stop at the first.
  final List<String> problems;

  @override
  String toString() =>
      'PackFormatException($source):\n  - ${problems.join('\n  - ')}';
}

/// One regex rule for one message type.
class PackRule {
  /// Creates a rule. Prefer [ParserPack.fromYaml], which validates.
  PackRule({
    required this.id,
    required this.type,
    required this.pattern,
    required this.timeFormat,
    this.direction,
    this.directionValues = const {},
  });

  /// Unique within its pack, e.g. `sent`.
  final String id;

  /// The kind of transaction this rule produces.
  final TransactionType type;

  /// The compiled pattern, with named groups from [allowedGroups].
  final RegExp pattern;

  /// How to read the `time` group, if the pattern has one.
  final MessageTimeFormat? timeFormat;

  /// Fixed direction, when the message type always moves money one way.
  final Direction? direction;

  /// Maps the captured `direction` text (lower-cased) to a direction, for
  /// messages such as bank alerts that say "debited" or "credited".
  final Map<String, Direction> directionValues;
}

/// A validated parser pack for one institution.
class ParserPack {
  /// Creates a pack. Prefer [ParserPack.fromYaml], which validates.
  ParserPack({
    required this.id,
    required this.name,
    required this.version,
    required this.currency,
    required this.utcOffset,
    required this.senders,
    required this.rules,
    this.minEngineVersion = firstEngineVersion,
  });

  /// Parses and validates a pack from its YAML text.
  ///
  /// Throws [PackFormatException] listing every problem found.
  factory ParserPack.fromYaml(String yaml, {String source = 'pack'}) {
    final problems = <String>[];
    final Object? doc;
    try {
      doc = loadYaml(yaml);
    } on YamlException catch (e) {
      throw PackFormatException(source, ['Invalid YAML: ${e.message}']);
    }
    if (doc is! YamlMap) {
      throw PackFormatException(source, ['Top level must be a mapping']);
    }
    final r = YamlFieldReader(doc, problems);

    r.checkKeys(const {
      'schema',
      'id',
      'name',
      'version',
      'min_engine',
      'currency',
      'utc_offset',
      'senders',
      'time_format',
      'rules',
    });
    final schema = r.integer('schema');
    if (schema != null && schema != supportedPackSchema) {
      problems.add(
        'schema: $schema is not supported '
        '(this engine reads $supportedPackSchema)',
      );
    }
    final id = r.string('id', pattern: _idPattern);
    final name = r.string('name');
    final version = r.string('version', pattern: _semver);
    final minEngine =
        r.string('min_engine', pattern: _semver, optional: true) ??
        firstEngineVersion;
    if (_semver.hasMatch(minEngine) &&
        compareVersions(minEngine, engineVersion) > 0) {
      problems.add(
        'min_engine: needs engine $minEngine, this engine is $engineVersion',
      );
    }
    final currency = r.string('currency', pattern: RegExp(r'^[A-Z]{3}$'));
    final offsetText = r.string('utc_offset');
    final utcOffset = offsetText == null ? null : parseUtcOffset(offsetText);
    if (offsetText != null && utcOffset == null) {
      problems.add('utc_offset: "$offsetText" must look like +03:00');
    }
    final senders = r.stringList('senders') ?? const [];
    if (senders.isEmpty) problems.add('senders: at least one is required');
    final defaultFormat = r.timeFormat('time_format', optional: true);

    final rules = <PackRule>[];
    final ruleNodes = doc['rules'];
    if (ruleNodes is! YamlList || ruleNodes.isEmpty) {
      problems.add('rules: a non-empty list is required');
    } else {
      final seen = <String>{};
      for (var i = 0; i < ruleNodes.length; i++) {
        final rule = _readRule(ruleNodes[i], 'rules[$i]', defaultFormat);
        problems.addAll(rule.$2);
        final value = rule.$1;
        if (value == null) continue;
        if (!seen.add(value.id)) {
          problems.add('rules[$i].id: duplicate rule id "${value.id}"');
        }
        rules.add(value);
      }
    }

    if (problems.isNotEmpty) throw PackFormatException(source, problems);
    return ParserPack(
      id: id!,
      name: name!,
      version: version!,
      minEngineVersion: minEngine,
      currency: currency!,
      utcOffset: utcOffset!,
      senders: List.unmodifiable(senders),
      rules: List.unmodifiable(rules),
    );
  }

  /// Stable identifier, matching the pack's directory name, e.g. `mpesa`.
  final String id;

  /// Display name, e.g. `M-Pesa`.
  final String name;

  /// Semantic version of the pack's rules.
  final String version;

  /// The oldest engine version that can read this pack (`min_engine`).
  final String minEngineVersion;

  /// ISO 4217 code for amounts in this institution's messages.
  final String currency;

  /// Offset of the wall-clock times printed in messages.
  final Duration utcOffset;

  /// Sender IDs whose messages this pack reads.
  final List<String> senders;

  /// Rules in match order; the first matching rule wins.
  final List<PackRule> rules;

  static (PackRule?, List<String>) _readRule(
    Object? node,
    String at,
    MessageTimeFormat? defaultFormat,
  ) {
    final problems = <String>[];
    if (node is! YamlMap) return (null, ['$at: must be a mapping']);
    final r = YamlFieldReader(node, problems, prefix: '$at.');
    r.checkKeys(const {
      'id',
      'type',
      'direction',
      'direction_values',
      'time_format',
      'ignore_case',
      'pattern',
    });
    final id = r.string('id', pattern: _idPattern);
    final typeText = r.string('type');
    final type = typeText == null ? null : TransactionType.fromCode(typeText);
    if (typeText != null && type == null) {
      problems.add('$at.type: unknown type "$typeText"');
    }
    final format = r.timeFormat('time_format', optional: true) ?? defaultFormat;
    final ignoreCase = r.boolean('ignore_case') ?? false;

    final patternText = r.string('pattern');
    RegExp? pattern;
    if (patternText != null) {
      try {
        pattern = RegExp(patternText, caseSensitive: !ignoreCase);
      } on FormatException catch (e) {
        problems.add('$at.pattern: does not compile: ${e.message}');
      }
    }
    final groups = pattern == null
        ? const <String>{}
        : _namedGroups(patternText!).toSet();
    for (final g in groups.difference(allowedGroups)) {
      problems.add('$at.pattern: group "$g" is not one of $allowedGroups');
    }
    if (pattern != null && !groups.contains('amount')) {
      problems.add('$at.pattern: must capture an "amount" group');
    }
    if (groups.contains('time') && format == null) {
      problems.add('$at: captures "time" but no time_format is set');
    }

    final directionText = r.string('direction', optional: true);
    final direction = directionText == null
        ? null
        : Direction.fromCode(directionText);
    if (directionText != null && direction == null) {
      problems.add('$at.direction: must be "in" or "out"');
    }
    final directionValues = <String, Direction>{};
    final valuesNode = node['direction_values'];
    if (valuesNode is YamlMap) {
      for (final entry in valuesNode.entries) {
        final d = Direction.fromCode('${entry.value}');
        if (d == null) {
          problems.add('$at.direction_values.${entry.key}: must be in or out');
        } else {
          directionValues['${entry.key}'.toLowerCase()] = d;
        }
      }
    } else if (valuesNode != null) {
      problems.add('$at.direction_values: must be a mapping');
    }
    final capturesDirection = groups.contains('direction');
    if (capturesDirection == (direction != null) ||
        capturesDirection == directionValues.isEmpty) {
      problems.add(
        '$at: set either a fixed "direction", or capture a '
        '"direction" group and map it with "direction_values"',
      );
    }

    if (problems.isNotEmpty) return (null, problems);
    return (
      PackRule(
        id: id!,
        type: type!,
        pattern: pattern!,
        timeFormat: groups.contains('time') ? format : null,
        direction: direction,
        directionValues: Map.unmodifiable(directionValues),
      ),
      problems,
    );
  }

  static Iterable<String> _namedGroups(String pattern) => RegExp(
    r'\(\?<([A-Za-z_][A-Za-z0-9_]*)>',
  ).allMatches(pattern).map((m) => m.group(1)!);

  static final _idPattern = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _semver = RegExp(
    r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
  );
}

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
  'own_account',
  'currency',
  'balance',
  'fee',
  'time',
  // A debt's total still owed after this message, such as Fuliza's.
  'owed',
  // When that debt is due; read with the rule's `due_format`.
  'due',
};

/// The engine version assumed when a pack does not set `min_engine`.
const firstEngineVersion = '0.1.0';

/// The first engine version that reads `min_engine` on a rule. A pack that
/// gates a rule this way needs at least this version as its own
/// `min_engine`, because older engines refuse the field.
///
/// The field arrives in the first release after 0.3.0. Any version above
/// 0.3.0 and no later than that release keeps 0.3.0 engines out, so this
/// stays correct whether the release is 0.3.1 or 0.4.0.
const ruleMinEngineSince = '0.3.1';

/// Pack features newer than [firstEngineVersion], and the first engine
/// version that reads each.
///
/// A pack using one must set `min_engine` (on the pack, or on the rule that
/// uses it) to at least that version, so an older engine refuses the pack,
/// or skips the rule, instead of failing on it. [ParserPack.fromYaml]
/// rejects a pack that understates it.
const featureMinEngine = <String, String>{
  'an empty rules list (review-only pack)': '0.2.0',
  'the own_account group': '0.2.0',
  'the currency group': '0.2.0',
  'the owed group': '0.3.0',
  'the due group': '0.3.0',
  'due_format': '0.3.0',
  'min_engine on a rule': ruleMinEngineSince,
  'the loan_repayment type': '0.4.0',
  'institution on a rule': '0.4.0',
};

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

  /// A repayment of a loan, such as a bank's salary advance. `account` is
  /// the loan's number, `counterparty` the loan as printed, and `owed` and
  /// `due` what is left and when the next instalment is due.
  loanRepayment('loan_repayment'),

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

/// Thrown when a pack's `min_engine` is newer than the engine reading it.
///
/// It is a [PackFormatException], so code that catches that still refuses
/// the pack; catch this one first to tell "update the app" apart from a
/// broken pack. Nothing else in the pack is read, since it may use fields
/// this engine does not know.
class PackEngineException extends PackFormatException {
  /// Creates an exception for [source], which needs [minEngine] while this
  /// engine is [engine].
  PackEngineException(
    String source, {
    required this.minEngine,
    required this.engine,
  }) : super(source, [
         'min_engine: needs engine $minEngine, this engine is $engine',
       ]);

  /// The pack's `min_engine`.
  final String minEngine;

  /// The version of the engine that read it.
  final String engine;
}

/// A rule left out of a pack because its own `min_engine` is newer than the
/// engine reading the pack. Messages only it would read go to the review
/// inbox; the rest of the pack works as usual.
class SkippedRule {
  /// Creates a record of rule [id], which needs [minEngine].
  const SkippedRule(this.id, this.minEngine);

  /// The rule's `id`, as written.
  final String id;

  /// The rule's `min_engine`.
  final String minEngine;

  @override
  String toString() => 'SkippedRule($id, needs engine $minEngine)';
}

/// One regex rule for one message type.
class PackRule {
  /// Creates a rule. Prefer [ParserPack.fromYaml], which validates.
  PackRule({
    required this.id,
    required this.type,
    required this.pattern,
    required this.timeFormat,
    this.dueFormat,
    this.direction,
    this.directionValues = const {},
    this.institution,
  });

  /// Unique within its pack, e.g. `sent`.
  final String id;

  /// The kind of transaction this rule produces.
  final TransactionType type;

  /// The compiled pattern, with named groups from [allowedGroups].
  final RegExp pattern;

  /// How to read the `time` group, if the pattern has one.
  final MessageTimeFormat? timeFormat;

  /// How to read the `due` group (a date, no time), if the pattern has one.
  final MessageTimeFormat? dueFormat;

  /// Fixed direction, when the message type always moves money one way.
  final Direction? direction;

  /// Maps the captured `direction` text (lower-cased) to a direction, for
  /// messages such as bank alerts that say "debited" or "credited".
  final Map<String, Direction> directionValues;

  /// The pack id of the institution whose account the money moved on, when
  /// it is not this pack's own: KCB's confirmation of an M-Pesa payment to
  /// its paybill is `mpesa`. Null for the pack's own accounts.
  final String? institution;
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
    this.skippedRules = const [],
  });

  /// Parses and validates a pack from its YAML text, for an engine at
  /// version [engine] (this engine's [engineVersion] unless a test says
  /// otherwise).
  ///
  /// Throws [PackEngineException] if the pack's `min_engine` is newer than
  /// [engine], and [PackFormatException] listing every problem found if the
  /// pack is malformed, including when it uses a feature newer than its
  /// `min_engine` says (see [featureMinEngine]). Rules whose own
  /// `min_engine` is newer than [engine] are left out and listed in
  /// [skippedRules].
  factory ParserPack.fromYaml(
    String yaml, {
    String source = 'pack',
    String engine = engineVersion,
  }) {
    if (!isSemanticVersion(engine)) {
      throw ArgumentError.value(engine, 'engine', 'Not a semantic version');
    }
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

    // Checked first: a pack for a newer engine may use fields this one does
    // not know, and listing those would hide the real reason.
    final minEngine =
        r.version('min_engine', optional: true) ?? firstEngineVersion;
    if (!engineSatisfies(minEngine, engine: engine)) {
      throw PackEngineException(source, minEngine: minEngine, engine: engine);
    }

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
    final version = r.version('version');
    final currency = r.string('currency', pattern: RegExp(r'^[A-Z]{3}$'));
    final offsetText = r.string('utc_offset');
    final utcOffset = offsetText == null ? null : parseUtcOffset(offsetText);
    if (offsetText != null && utcOffset == null) {
      problems.add('utc_offset: "$offsetText" must look like +03:00');
    }
    final senders = r.stringList('senders') ?? const [];
    if (senders.isEmpty) problems.add('senders: at least one is required');
    final defaultFormat = r.timeFormat('time_format', optional: true);

    // Reports a feature from [featureMinEngine] that needs a newer engine
    // than [floor], the min_engine that applies where it is used.
    void requireEngine(String at, String feature, String floor) {
      final needs = featureMinEngine[feature]!;
      if (compareVersions(needs, floor) > 0) {
        problems.add(
          '$at: $feature needs engine $needs, but min_engine is $floor; '
          'set min_engine: $needs',
        );
      }
    }

    final rules = <PackRule>[];
    final skipped = <SkippedRule>[];
    final ruleNodes = doc['rules'];
    // An empty list is a review-only pack: its senders are read, and every
    // message goes to the review inbox until rules are written.
    if (ruleNodes is! YamlList) {
      problems.add('rules: a list is required');
    } else {
      if (ruleNodes.isEmpty) {
        requireEngine(
          'rules',
          'an empty rules list (review-only pack)',
          minEngine,
        );
      }
      final seen = <String>{};
      for (var i = 0; i < ruleNodes.length; i++) {
        final node = ruleNodes[i];
        final at = 'rules[$i]';
        var floor = minEngine;
        if (node is YamlMap && node.containsKey('min_engine')) {
          requireEngine(at, 'min_engine on a rule', minEngine);
          final ruleMin = YamlFieldReader(
            node,
            problems,
            prefix: '$at.',
          ).version('min_engine');
          if (ruleMin != null && !engineSatisfies(ruleMin, engine: engine)) {
            // Not read at all: it may use groups or fields this engine
            // does not know.
            skipped.add(SkippedRule('${node['id'] ?? at}', ruleMin));
            continue;
          }
          if (ruleMin != null && compareVersions(ruleMin, floor) > 0) {
            floor = ruleMin;
          }
        }
        final rule = _readRule(node, at, defaultFormat);
        problems.addAll(rule.$2);
        for (final feature in rule.$3) {
          requireEngine(at, feature, floor);
        }
        final value = rule.$1;
        if (value == null) continue;
        if (value.institution != null && value.institution == id) {
          problems.add(
            '$at.institution: "$id" is this pack; leave it out for the '
            "pack's own accounts",
          );
        }
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
      skippedRules: List.unmodifiable(skipped),
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

  /// Rules left out because their own `min_engine` is newer than the engine
  /// that read the pack. Empty for every pack this engine fully reads.
  final List<SkippedRule> skippedRules;

  /// Reads one rule. Returns the rule (or `null`), its problems, and the
  /// [featureMinEngine] features it uses.
  static (PackRule?, List<String>, Set<String>) _readRule(
    Object? node,
    String at,
    MessageTimeFormat? defaultFormat,
  ) {
    final problems = <String>[];
    if (node is! YamlMap) return (null, ['$at: must be a mapping'], const {});
    final r = YamlFieldReader(node, problems, prefix: '$at.');
    r.checkKeys(const {
      'min_engine',
      'id',
      'type',
      'direction',
      'direction_values',
      'time_format',
      'due_format',
      'ignore_case',
      'institution',
      'pattern',
    });
    final id = r.string('id', pattern: _idPattern);
    final typeText = r.string('type');
    final type = typeText == null ? null : TransactionType.fromCode(typeText);
    if (typeText != null && type == null) {
      problems.add('$at.type: unknown type "$typeText"');
    }
    final format = r.timeFormat('time_format', optional: true) ?? defaultFormat;
    final dueFormat = r.timeFormat(
      'due_format',
      optional: true,
      dateOnly: true,
    );
    final ignoreCase = r.boolean('ignore_case') ?? false;
    final institution = r.string(
      'institution',
      optional: true,
      pattern: _idPattern,
    );

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
    if (groups.contains('due') && dueFormat == null) {
      problems.add('$at: captures "due" but no due_format is set');
    }
    if (groups.contains('time') && format == null) {
      problems.add('$at: captures "time" but no time_format is set');
    }

    final features = {
      for (final g in const ['own_account', 'currency', 'owed', 'due'])
        if (groups.contains(g)) 'the $g group',
      if (node.containsKey('due_format')) 'due_format',
      if (type == TransactionType.loanRepayment) 'the loan_repayment type',
      if (node.containsKey('institution')) 'institution on a rule',
    };

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

    if (problems.isNotEmpty) return (null, problems, features);
    return (
      PackRule(
        id: id!,
        type: type!,
        pattern: pattern!,
        timeFormat: groups.contains('time') ? format : null,
        dueFormat: groups.contains('due') ? dueFormat : null,
        direction: direction,
        directionValues: Map.unmodifiable(directionValues),
        institution: institution,
      ),
      problems,
      features,
    );
  }

  static Iterable<String> _namedGroups(String pattern) => RegExp(
    r'\(\?<([A-Za-z_][A-Za-z0-9_]*)>',
  ).allMatches(pattern).map((m) => m.group(1)!);

  static final _idPattern = RegExp(r'^[a-z][a-z0-9_]*$');
}

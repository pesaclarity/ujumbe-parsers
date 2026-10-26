import 'package:yaml/yaml.dart';

import 'pack.dart';
import 'parser.dart';

/// Synthetic sample messages and the fields a pack must extract from them.
class PackFixtures {
  /// Creates fixtures for the pack [packId].
  const PackFixtures({required this.packId, required this.samples});

  /// Parses fixtures from YAML. Throws [PackFormatException] if malformed.
  factory PackFixtures.fromYaml(String yaml, {String source = 'fixtures'}) {
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
    final packId = doc['pack'];
    if (packId is! String) problems.add('pack: is required');
    final nodes = doc['samples'];
    final samples = <FixtureSample>[];
    if (nodes is! YamlList || nodes.isEmpty) {
      problems.add('samples: a non-empty list is required');
    } else {
      for (var i = 0; i < nodes.length; i++) {
        final sample = FixtureSample._read(nodes[i], 'samples[$i]', problems);
        if (sample != null) samples.add(sample);
      }
    }
    if (problems.isNotEmpty) throw PackFormatException(source, problems);
    return PackFixtures(packId: packId as String, samples: samples);
  }

  /// The pack these samples test.
  final String packId;

  /// The samples, in file order.
  final List<FixtureSample> samples;

  /// Runs every sample against [pack] and reports the results.
  ///
  /// A pack is valid only when [FixtureReport.passed] is true: every sample
  /// matches and every rule is exercised by at least one sample.
  FixtureReport run(ParserPack pack) {
    final parser = SmsParser([pack]);
    final failures = <String>[];
    if (pack.id != packId) {
      failures.add('fixtures are for "$packId", not "${pack.id}"');
    }
    final covered = <String>{};
    for (final sample in samples) {
      final result = parser.parse(sample.message);
      if (result is ParsedTransaction) covered.add(result.ruleId);
      for (final problem in sample.check(result)) {
        failures.add('${sample.name}: $problem');
      }
    }
    for (final rule in pack.rules) {
      if (!covered.contains(rule.id)) {
        failures.add('rule "${rule.id}" has no passing sample');
      }
    }
    return FixtureReport(
      packId: pack.id,
      sampleCount: samples.length,
      failures: failures,
    );
  }
}

/// One synthetic message and what parsing it must produce.
class FixtureSample {
  /// Creates a sample. A `null` [expected] means the message must be
  /// [Unmatched].
  const FixtureSample({
    required this.name,
    required this.message,
    required this.expected,
  });

  /// Short description shown in failure reports.
  final String name;

  /// The synthetic message.
  final SmsMessage message;

  /// Expected fields, keyed as in fixture files; `null` means unmatched.
  final Map<String, Object?>? expected;

  /// Every field a parsed sample is compared on. Fields left out of a
  /// fixture must parse as absent, so a rule cannot silently capture extra.
  static const fields = [
    'rule',
    'type',
    'direction',
    'amount_minor',
    'fee_minor',
    'balance_minor',
    'receipt',
    'counterparty',
    'account',
    'time',
  ];

  /// Lists how [result] differs from what this sample expects.
  List<String> check(ParseResult result) {
    final expected = this.expected;
    if (expected == null) {
      return result is Unmatched
          ? const []
          : ['expected unmatched, got ${_describe(result)}'];
    }
    if (result is! ParsedTransaction) {
      final reason = result is Unmatched ? result.reason : 'ignored';
      return ['expected a transaction, got $reason'];
    }
    final actual = <String, Object?>{
      'rule': result.ruleId,
      'type': result.type.code,
      'direction': result.direction.code,
      'amount_minor': result.amountMinor,
      'fee_minor': result.feeMinor,
      'balance_minor': result.balanceMinor,
      'receipt': result.receipt,
      'counterparty': result.counterparty,
      'account': result.account,
      'time': result.time,
    };
    final problems = <String>[];
    for (final field in fields) {
      var want = expected[field];
      if (field == 'time' && want is String) want = DateTime.parse(want);
      if (want != actual[field]) {
        problems.add('$field: expected $want, got ${actual[field]}');
      }
    }
    return problems;
  }

  static String _describe(ParseResult r) => switch (r) {
    ParsedTransaction(:final ruleId) => 'rule "$ruleId"',
    Unmatched() => 'unmatched',
    Ignored() => 'ignored',
  };

  // A fixed default keeps fixtures reproducible for messages without a time.
  static final _defaultReceivedAt = DateTime.utc(2026, 1, 1, 9);

  static FixtureSample? _read(Object? node, String at, List<String> problems) {
    if (node is! YamlMap) {
      problems.add('$at: must be a mapping');
      return null;
    }
    final name = node['name'];
    final sender = node['sender'];
    final body = node['body'];
    final receivedText = node['received_at'];
    final expect = node['expect'];
    final start = problems.length;
    if (name is! String) problems.add('$at.name: is required');
    if (sender is! String) problems.add('$at.sender: is required');
    if (body is! String) problems.add('$at.body: is required');
    DateTime? receivedAt = _defaultReceivedAt;
    if (receivedText != null) {
      receivedAt = DateTime.tryParse('$receivedText');
      if (receivedAt == null) {
        problems.add('$at.received_at: must be an ISO 8601 time');
      }
    }
    Map<String, Object?>? expected;
    if (expect is YamlMap) {
      expected = {for (final e in expect.entries) '${e.key}': e.value};
      for (final key in expected.keys) {
        if (!fields.contains(key)) {
          problems.add('$at.expect.$key: unknown field');
        }
      }
      for (final key in const ['rule', 'type', 'direction', 'amount_minor']) {
        if (expected[key] == null) problems.add('$at.expect.$key: required');
      }
      final time = expected['time'];
      if (time is! String || DateTime.tryParse(time) == null) {
        problems.add('$at.expect.time: must be an ISO 8601 time');
      }
    } else if (expect != 'unmatched') {
      problems.add('$at.expect: must be a mapping or "unmatched"');
    }
    if (problems.length > start) return null;
    return FixtureSample(
      name: name as String,
      message: SmsMessage(
        sender: sender as String,
        body: (body as String).trimRight(),
        receivedAt: receivedAt!,
      ),
      expected: expected,
    );
  }
}

/// The result of running a pack's fixtures.
class FixtureReport {
  /// Creates a report.
  const FixtureReport({
    required this.packId,
    required this.sampleCount,
    required this.failures,
  });

  /// The pack tested.
  final String packId;

  /// How many samples ran.
  final int sampleCount;

  /// Every failure; empty when the pack is valid.
  final List<String> failures;

  /// Whether every sample passed and every rule was exercised.
  bool get passed => failures.isEmpty;
}

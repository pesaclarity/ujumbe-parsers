import 'dart:convert';

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'helpers.dart';

/// [testPackYaml] with a pack-level `min_engine` (none when null).
String _withMinEngine(String? minEngine, [String yaml = testPackYaml]) =>
    minEngine == null
    ? yaml
    : yaml.replaceFirst('currency:', 'min_engine: $minEngine\ncurrency:');

/// A synthetic pack whose second rule reads Fuliza-style debt fields.
String _owedPack(String? minEngine) => _withMinEngine(minEngine, r'''
schema: 1
id: example_wallet
name: Example Wallet
version: 1.0.0
currency: KES
utc_offset: "+03:00"
senders: [EXWALLET]
rules:
  - id: alert
    type: bank
    direction_values: {debited: out, credited: in}
    pattern: '^Ksh(?<amount>[\d,]+\.\d{2}) (?<direction>\w+)\.$'
  - id: overdraft
    type: fuliza
    direction: in
    due_format: "dd/MM/yy"
    pattern: '^Overdraft Ksh(?<amount>[\d,]+\.\d{2})\. Owed Ksh(?<owed>[\d,]+\.\d{2}) due (?<due>\d{2}/\d{2}/\d{2})\.$'
''');

/// A pack for engine 0.4.0 with one rule gated on an engine from the future;
/// that rule uses a group and a field no engine reads today.
const _gatedPack = r'''
schema: 1
id: example_wallet
name: Example Wallet
version: 1.0.0
min_engine: 0.3.1
currency: KES
utc_offset: "+03:00"
senders: [EXWALLET]
rules:
  - id: future
    min_engine: 9.0.0
    type: till
    direction: out
    hologram: true
    pattern: '^Paid Ksh(?<amount>[\d,]+\.\d{2}) tip Ksh(?<tip>[\d,]+\.\d{2})\.$'
  - id: alert
    type: bank
    direction_values: {debited: out, credited: in}
    pattern: '^Ksh(?<amount>[\d,]+\.\d{2}) (?<direction>\w+)\.$'
''';

SmsMessage _sms(String body) => SmsMessage(
  sender: 'EXWALLET',
  body: body,
  receivedAt: DateTime.utc(2026, 10, 26, 6),
);

List<String> _problems(String yaml, {String engine = engineVersion}) {
  try {
    ParserPack.fromYaml(yaml, engine: engine);
  } on PackFormatException catch (e) {
    return e.problems;
  }
  return const [];
}

void main() {
  group('semantic versions', () {
    test('accepts SemVer 2.0 versions', () {
      for (final v in [
        '0.0.0',
        '0.3.0',
        '10.20.30',
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-0.3.7',
        '1.0.0-x-y.7a',
        '1.0.0+build.5',
        '1.0.0-rc.1+build.5',
      ]) {
        expect(isSemanticVersion(v), isTrue, reason: v);
      }
    });

    test('refuses malformed versions', () {
      for (final v in [
        '',
        'soon',
        '1',
        '0.3',
        '0.3.0.1',
        'v0.3.0',
        '01.0.0',
        '0.03.0',
        '1.0.0-',
        '1.0.0-01',
        '1.0.0-beta..1',
        '1.0.0+',
        ' 0.3.0',
      ]) {
        expect(isSemanticVersion(v), isFalse, reason: v);
        expect(() => compareVersions(v, '0.3.0'), throwsFormatException);
      }
    });

    test('a pre-release does not satisfy its release', () {
      expect(engineSatisfies('0.4.0', engine: '0.4.0-beta.1'), isFalse);
      expect(engineSatisfies('0.4.0-beta.1', engine: '0.4.0'), isTrue);
      expect(engineSatisfies('0.4.0-beta.10', engine: '0.4.0-beta.2'), isFalse);
      expect(engineSatisfies('0.4.0-beta.2', engine: '0.4.0-beta.10'), isTrue);
      expect(engineSatisfies('0.3.0', engine: '0.4.0-alpha'), isTrue);
    });

    test('build metadata is ignored', () {
      expect(engineSatisfies('0.3.0+build.7', engine: '0.3.0'), isTrue);
      expect(engineSatisfies('0.3.0', engine: '0.3.0+build.7'), isTrue);
    });
  });

  group('pack min_engine', () {
    test('equal to the engine loads', () {
      final pack = ParserPack.fromYaml(
        _withMinEngine('0.3.0'),
        engine: '0.3.0',
      );
      expect(pack.minEngineVersion, '0.3.0');
    });

    test('older than the engine loads', () {
      final pack = ParserPack.fromYaml(
        _withMinEngine('0.2.0'),
        engine: '0.3.0',
      );
      expect(pack.minEngineVersion, '0.2.0');
      expect(pack.rules, hasLength(2));
    });

    test('newer than the engine is refused with a typed error', () {
      // Unknown fields are not listed: the engine is the reason.
      final yaml = _withMinEngine(
        '0.4.0',
      ).replaceFirst('rules:', 'hologram: true\nrules:');
      expect(
        () => ParserPack.fromYaml(yaml, engine: '0.3.0', source: 'x'),
        throwsA(
          isA<PackEngineException>()
              .having((e) => e.minEngine, 'minEngine', '0.4.0')
              .having((e) => e.engine, 'engine', '0.3.0')
              .having((e) => e.source, 'source', 'x')
              .having((e) => e.problems, 'problems', [
                'min_engine: needs engine 0.4.0, this engine is 0.3.0',
              ]),
        ),
      );
    });

    test('follows pre-release precedence', () {
      expect(
        () => ParserPack.fromYaml(
          _withMinEngine('0.4.0'),
          engine: '0.4.0-beta.1',
        ),
        throwsA(isA<PackEngineException>()),
      );
      final pack = ParserPack.fromYaml(
        _withMinEngine('0.4.0-beta.1'),
        engine: '0.4.0',
      );
      expect(pack.minEngineVersion, '0.4.0-beta.1');
    });

    test('malformed is a format problem, not an engine one', () {
      for (final v in ['soon', '0.3', '01.0.0', '0.3.0-', '0.3.0-01', '1.0']) {
        Object? error;
        try {
          ParserPack.fromYaml(_withMinEngine(v));
        } on Object catch (e) {
          error = e;
        }
        expect(error, isA<PackFormatException>(), reason: v);
        expect(error, isNot(isA<PackEngineException>()), reason: v);
        expect(
          (error! as PackFormatException).problems.join(),
          contains('min_engine'),
          reason: v,
        );
      }
    });

    test('a malformed engine version is a programming error', () {
      expect(
        () => ParserPack.fromYaml(testPackYaml, engine: '0.3'),
        throwsArgumentError,
      );
    });

    test('statement packs refuse a newer min_engine the same way', () {
      const statement = r'''
schema: 1
id: example_statement
institution: example
name: Example statement
version: 0.1.0
min_engine: 0.4.0
currency: KES
utc_offset: "+03:00"
detect: ['^EXAMPLE$']
columns:
  - { key: date, header: '^Date$', format: dd/MM/yyyy }
  - { key: description, header: '^Details$' }
  - { key: money_in, header: '^In$', align: right }
  - { key: money_out, header: '^Out$', align: right }
row_starts_with: date
''';
      expect(
        () => StatementPack.fromYaml(statement, engine: '0.3.0'),
        throwsA(isA<PackEngineException>()),
      );
      expect(
        StatementPack.fromYaml(statement, engine: '0.4.0').minEngineVersion,
        '0.4.0',
      );
    });
  });

  group('feature gates', () {
    test('every gate is a semantic version this engine reads', () {
      for (final MapEntry(:key, :value) in featureMinEngine.entries) {
        expect(isSemanticVersion(value), isTrue, reason: key);
      }
    });

    test('a pack using owed and due needs min_engine 0.3.0', () {
      final problems = _problems(_owedPack('0.2.0'));
      expect(problems, [
        'rules[1]: the owed group needs engine 0.3.0, but min_engine is '
            '0.2.0; set min_engine: 0.3.0',
        'rules[1]: the due group needs engine 0.3.0, but min_engine is '
            '0.2.0; set min_engine: 0.3.0',
        'rules[1]: due_format needs engine 0.3.0, but min_engine is '
            '0.2.0; set min_engine: 0.3.0',
      ]);
      expect(_problems(_owedPack(null)), hasLength(3));
      expect(_problems(_owedPack('0.3.0')), isEmpty);
    });

    test('own_account and currency need min_engine 0.2.0', () {
      final yaml = testPackYaml.replaceFirst(
        r'^Ksh(?<amount>',
        r'^(?<own_account>\d+) (?<currency>[A-Z]{3})(?<amount>',
      );
      expect(_problems(yaml), [
        contains('the own_account group needs engine 0.2.0'),
        contains('the currency group needs engine 0.2.0'),
      ]);
      expect(_problems(_withMinEngine('0.2.0', yaml)), isEmpty);
    });

    test('a review-only pack needs min_engine 0.2.0', () {
      final empty =
          '${testPackYaml.substring(0, testPackYaml.indexOf('rules:'))}'
          'rules: []\n';
      expect(_problems(empty), [
        contains('an empty rules list (review-only pack) needs engine 0.2.0'),
      ]);
      expect(_problems(_withMinEngine('0.2.0', empty)), isEmpty);
    });
  });

  group('rule min_engine', () {
    test('a rule for a newer engine is skipped and reported', () {
      final pack = ParserPack.fromYaml(_gatedPack, engine: '0.4.0');
      expect(pack.rules.map((r) => r.id), ['alert']);
      expect(pack.skippedRules, hasLength(1));
      expect(pack.skippedRules.single.id, 'future');
      expect(pack.skippedRules.single.minEngine, '9.0.0');

      // The rest of the pack still reads; the skipped rule's messages go to
      // the review inbox instead of being half-read.
      final parser = SmsParser([pack]);
      expect(
        parser.parse(_sms('Ksh100.00 debited.')),
        isA<ParsedTransaction>(),
      );
      expect(
        parser.parse(_sms('Paid Ksh100.00 tip Ksh10.00.')),
        isA<Unmatched>(),
      );
    });

    test('a rule this engine meets is read and checked as usual', () {
      final yaml = _gatedPack.replaceFirst(
        'min_engine: 9.0.0',
        'min_engine: '
            '0.4.0',
      );
      final problems = _problems(yaml, engine: '0.4.0');
      expect(problems, contains('rules[0].hologram: unknown field'));
      expect(problems.join(), contains('group "tip"'));
    });

    test('needs the pack itself to require an engine that reads it', () {
      final yaml = _gatedPack.replaceFirst(
        'min_engine: 0.3.1\n',
        'min_engine: 0.3.0\n',
      );
      expect(_problems(yaml, engine: '0.4.0'), [
        'rules[0]: min_engine on a rule needs engine $ruleMinEngineSince, '
            'but min_engine is 0.3.0; set min_engine: $ruleMinEngineSince',
      ]);
    });

    test('a malformed rule min_engine is a format problem', () {
      final yaml = _gatedPack.replaceFirst(
        'min_engine: 9.0.0',
        'min_engine: '
            'later',
      );
      expect(
        _problems(yaml, engine: '0.4.0'),
        contains(
          'rules[0].min_engine: "later" is not a semantic version '
          '(x.y.z)',
        ),
      );
    });
  });

  group('packs that load today', () {
    test('every bundled pack loads in full on this engine', () {
      for (final id in bundledPackIds) {
        final pack = loadBundledPack(id);
        expect(pack.skippedRules, isEmpty, reason: id);
        expect(engineSatisfies(pack.minEngineVersion), isTrue, reason: id);
      }
    });

    test('M-Pesa needs engine 0.3.0 and loads on it', () {
      final pack = ParserPack.fromYaml(
        bundledPackSources['mpesa']!,
        engine: '0.3.0',
      );
      expect(pack.minEngineVersion, '0.3.0');
      expect(
        () =>
            ParserPack.fromYaml(bundledPackSources['mpesa']!, engine: '0.2.0'),
        throwsA(isA<PackEngineException>()),
      );
    });

    test('the plain test pack still needs nothing newer than 0.1.0', () {
      final pack = ParserPack.fromYaml(
        testPackYaml,
        engine: firstEngineVersion,
      );
      expect(pack.minEngineVersion, firstEngineVersion);
    });
  });

  test('a stored signed pack is refused on an older engine', () async {
    final signer = await PackSigner.generate();
    final verifier = PackVerifier([await signer.publicKey()]);
    final bytes = utf8.encode(_withMinEngine('0.3.0'));
    final signature = await signer.sign(bytes);
    expect(
      () => verifier.loadVerified(bytes, signature, engine: '0.2.0'),
      throwsA(isA<PackEngineException>()),
    );
    final pack = await verifier.loadVerified(bytes, signature, engine: '0.3.0');
    expect(pack.minEngineVersion, '0.3.0');
  });
}

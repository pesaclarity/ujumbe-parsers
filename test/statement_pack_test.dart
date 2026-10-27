import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

const _valid = r'''
schema: 1
id: example_statement
institution: example
name: Example statement
version: 0.1.0
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

List<String> _problems(String yaml) {
  try {
    StatementPack.fromYaml(yaml, source: 'test');
    return const [];
  } on PackFormatException catch (e) {
    return e.problems;
  }
}

void main() {
  test('a minimal pack loads with defaults', () {
    final pack = StatementPack.fromYaml(_valid);
    expect(pack.order, RowOrder.detect);
    expect(pack.rules, isEmpty);
    expect(pack.skip, isEmpty);
    expect(
      pack.timeFormat.parse('02/10/2026', utcOffset: Duration.zero),
      DateTime.utc(2026, 10, 2),
    );
    expect(pack.matches('EXAMPLE\nmore'), isTrue);
  });

  test('every bundled statement pack loads', () {
    expect(bundledStatementPackIds, contains('mpesa_statement'));
    expect(loadBundledStatementPacks(), isNotEmpty);
  });

  final cases = <String, (String, String)>{
    'unknown field': (
      'row_starts_with: date',
      'row_starts_with: date\nextra: 1',
    ),
    'no date column': (
      "  - { key: date, header: '^Date\$', format: dd/MM/yyyy }\n",
      '',
    ),
    'both amount styles': (
      'row_starts_with: date',
      'row_starts_with: date\namount: { negative_is: out }',
    ),
    'a regex that does not compile': ("'^Details\$'", "'^(Details\$'"),
    'row start that is not a column': (
      'row_starts_with: date',
      'row_starts_with: balance',
    ),
    'a period without its groups': (
      'row_starts_with: date',
      "row_starts_with: date\nperiod: 'From (.*)'\nperiod_format: dd/MM/yyyy",
    ),
    'a date format that is not a date': ('dd/MM/yyyy', 'HH:mm'),
    'fees without a reference column': (
      'row_starts_with: date',
      "row_starts_with: date\nfees: { description: 'Charge' }",
    ),
    'an unknown rule type': (
      'row_starts_with: date',
      "row_starts_with: date\nrules: [{ id: x, type: magic, pattern: 'x' }]",
    ),
    'a rule group outside counterparty and account': (
      'row_starts_with: date',
      "row_starts_with: date\nrules: [{ id: x, type: sent, pattern: '(?<amount>x)' }]",
    ),
  };
  for (final MapEntry(key: name, value: (from, to)) in cases.entries) {
    test('rejects $name', () {
      expect(_valid.contains(from), isTrue, reason: 'bad test: "$from"');
      expect(_problems(_valid.replaceFirst(from, to)), isNotEmpty);
    });
  }

  test('a single amount column needs a style, and a marker needs markers', () {
    final single = _valid.replaceFirst(
      "  - { key: money_in, header: '^In\$', align: right }\n"
          "  - { key: money_out, header: '^Out\$', align: right }\n",
      "  - { key: amount, header: '^Amount\$', align: right }\n",
    );
    expect(_problems(single), contains(startsWith('amount: required')));
    expect(_problems('$single\namount: { negative_is: out }'), isEmpty);
    final withMarker = single.replaceFirst(
      "  - { key: amount, header: '^Amount\$', align: right }\n",
      "  - { key: amount, header: '^Amount\$', align: right }\n"
          "  - { key: marker, header: '^DrCr\$' }\n",
    );
    expect(_problems('$withMarker\namount: { negative_is: out }'), isNotEmpty);
    expect(
      _problems(
        "$withMarker\namount: { marker_out: '^DR\$', marker_in: '^CR\$' }",
      ),
      isEmpty,
    );
  });

  test('a date column without the time joins a time column', () {
    final pack = StatementPack.fromYaml(
      _valid.replaceFirst(
        "  - { key: description, header: '^Details\$' }\n",
        "  - { key: time, header: '^Time\$', format: 'h:mm a' }\n"
            "  - { key: description, header: '^Details\$' }\n",
      ),
    );
    expect(
      pack.timeFormat.parse('02/10/2026 1:05 PM', utcOffset: Duration.zero),
      DateTime.utc(2026, 10, 2, 13, 5),
    );
  });
}

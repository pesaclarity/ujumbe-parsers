import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'helpers.dart';

void main() {
  final pack = ParserPack.fromYaml(testPackYaml);

  String fixtures({String amount = '150000', bool includeAlert = true}) =>
      '''
pack: example_wallet
samples:
  - name: sent
    sender: EXWALLET
    body: '$testSentBody'
    expect:
      rule: sent
      type: sent
      direction: out
      amount_minor: $amount
      fee_minor: 1500
      balance_minor: 325000
      receipt: EX0001
      counterparty: JANE DOE
      time: '2026-10-26T09:15:00+03:00'
${includeAlert ? '''
  - name: alert
    sender: EXWALLET
    received_at: '2026-10-26T10:00:00+03:00'
    body: 'Ksh5.00 debited.'
    expect:
      rule: alert
      type: bank
      direction: out
      amount_minor: 500
      time: '2026-10-26T10:00:00+03:00'
''' : ''}
  - name: notice
    sender: EXWALLET
    body: 'Hello.'
    expect: unmatched
''';

  test('passes when every sample matches and every rule is covered', () {
    final report = PackFixtures.fromYaml(fixtures()).run(pack);
    expect(report.failures, isEmpty);
    expect(report.passed, isTrue);
    expect(report.sampleCount, 3);
  });

  test('fails on a wrong expected field', () {
    final report = PackFixtures.fromYaml(fixtures(amount: '1')).run(pack);
    expect(report.passed, isFalse);
    expect(report.failures.single, contains('amount_minor'));
  });

  test('fails when a field is captured but not expected', () {
    final yaml = fixtures().replaceFirst('      fee_minor: 1500\n', '');
    final report = PackFixtures.fromYaml(yaml).run(pack);
    expect(report.failures.single, contains('fee_minor'));
  });

  test('fails when a rule has no sample', () {
    final report = PackFixtures.fromYaml(
      fixtures(includeAlert: false),
    ).run(pack);
    expect(report.failures.single, contains('"alert" has no passing sample'));
  });

  test('fails when an unmatched sample is parsed', () {
    final yaml = fixtures().replaceFirst("'Hello.'", "'Ksh1.00 credited.'");
    expect(PackFixtures.fromYaml(yaml).run(pack).passed, isFalse);
  });

  test('rejects malformed fixture files', () {
    expect(
      () => PackFixtures.fromYaml('pack: x\nsamples:\n  - name: a\n'),
      throwsA(isA<PackFormatException>()),
    );
  });
}

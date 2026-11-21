import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'helpers.dart';

void main() {
  final pack = ParserPack.fromYaml(testNoticePackYaml);
  final parser = SmsParser([pack]);

  SmsMessage sms(String body, {String sender = 'EXWALLET'}) => SmsMessage(
    sender: sender,
    body: body,
    receivedAt: DateTime.utc(2026, 10, 26, 7),
  );

  List<String> problemsFor(String yaml) {
    try {
      ParserPack.fromYaml(yaml);
    } on PackFormatException catch (e) {
      return e.problems;
    }
    return const [];
  }

  group('reading notices', () {
    test('reads them in order', () {
      expect(pack.notices.map((n) => n.id), ['declined', 'pin_changed']);
    });

    test('a pack without notices has none', () {
      expect(ParserPack.fromYaml(testPackYaml).notices, isEmpty);
    });

    test('need min_engine 0.4.0', () {
      final problems = problemsFor(
        testNoticePackYaml.replaceFirst('min_engine: 0.4.0\n', ''),
      );
      expect(problems, [
        'notices: notices needs engine 0.4.0, but min_engine is 0.1.0; '
            'set min_engine: 0.4.0',
      ]);
    });

    final cases = {
      'a notice that is not a mapping': (
        '  - id: declined\n',
        '  - x\n  - id: declined\n',
      ),
      'a duplicate notice id': ('id: pin_changed', 'id: declined'),
      'a bad notice id': ('id: pin_changed', 'id: Pin-Changed'),
      'a missing pattern': ("    pattern: '^Your PIN was changed\\.\$'\n", ''),
      'a pattern that does not compile': (r'payment to .+', r'payment to (.+'),
      'a named group': (r'payment to .+', r'payment to (?<counterparty>.+)'),
      'an unknown field': ('id: declined', 'id: declined\n    type: bank'),
    };
    for (final MapEntry(key: name, value: (from, to)) in cases.entries) {
      test('rejects $name', () {
        expect(testNoticePackYaml, contains(from));
        expect(
          problemsFor(testNoticePackYaml.replaceFirst(from, to)),
          isNotEmpty,
        );
      });
    }

    test('notices must be a list', () {
      final yaml =
          '${testNoticePackYaml.substring(0, testNoticePackYaml.indexOf('notices:'))}'
          'notices: {}\n';
      expect(problemsFor(yaml), ['notices: must be a list']);
    });

    test('names the group a notice may not capture', () {
      expect(
        problemsFor(
          testNoticePackYaml.replaceFirst(
            r'payment to .+',
            r'payment to (?<counterparty>.+)',
          ),
        ),
        [contains('a notice reads no fields; make group "counterparty"')],
      );
    });
  });

  group('parsing', () {
    test('a matched notice is a KnownNotice naming the notice', () {
      const body = 'Ksh1,200.00 payment to EXAMPLE STORES was declined.';
      final result = parser.parse(sms(body));
      expect(result, isA<KnownNotice>());
      final notice = result as KnownNotice;
      expect(notice.packId, 'example_wallet');
      expect(notice.packVersion, '1.0.0');
      expect(notice.noticeId, 'declined');
      expect(notice.rawHash, hashMessageBody(body));
    });

    test('ignore_case applies to the notice pattern', () {
      final result = parser.parse(sms('YOUR PIN WAS CHANGED.'));
      expect((result as KnownNotice).noticeId, 'pin_changed');
    });

    test('a KnownNotice is dropped by code that drops Ignored', () {
      final result = parser.parse(sms('Your PIN was changed.'));
      expect(result, isA<Ignored>());
      final dropped = switch (result) {
        ParsedTransaction() || Unmatched() => false,
        Ignored() => true,
      };
      expect(dropped, isTrue);
    });

    test('rules win over notices, so a notice never hides a transaction', () {
      final wide = ParserPack.fromYaml(
        testNoticePackYaml.replaceFirst(r"'^Your PIN was changed\.$'", "'.'"),
      );
      expect(
        SmsParser([wide]).parse(sms(testSentBody)),
        isA<ParsedTransaction>(),
      );
      expect(SmsParser([wide]).parse(sms('Hello.')), isA<KnownNotice>());
    });

    test('other messages from the sender still go to review', () {
      expect(parser.parse(sms('Your statement is ready.')), isA<Unmatched>());
    });

    test('other senders are plainly ignored, not notices', () {
      final result = parser.parse(
        sms('Your PIN was changed.', sender: 'PROMO'),
      );
      expect(result, isA<Ignored>());
      expect(result, isNot(isA<KnownNotice>()));
    });

    test(
      'older engines refuse a pack with notices instead of misreading it',
      () {
        expect(
          () => ParserPack.fromYaml(testNoticePackYaml, engine: '0.3.0'),
          throwsA(isA<PackEngineException>()),
        );
      },
    );
  });

  group('fixtures', () {
    String fixtures(String noticeExpect) =>
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
      amount_minor: 150000
      fee_minor: 1500
      balance_minor: 325000
      receipt: EX0001
      counterparty: JANE DOE
      time: '2026-10-26T09:15:00+03:00'
  - name: alert
    sender: EXWALLET
    body: 'Ksh5.00 debited.'
    expect:
      rule: alert
      type: bank
      direction: out
      amount_minor: 500
      time: '2026-01-01T09:00:00Z'
  - name: declined
    sender: EXWALLET
    body: 'Ksh9.00 payment to EXAMPLE STORES was declined.'
    expect:
      $noticeExpect
  - name: pin
    sender: EXWALLET
    body: 'Your PIN was changed.'
    expect:
      notice: pin_changed
''';

    test('pass when each notice sample matches its notice', () {
      final report = PackFixtures.fromYaml(
        fixtures('notice: declined'),
      ).run(pack);
      expect(report.failures, isEmpty);
    });

    test('fail when a sample matches another notice', () {
      final report = PackFixtures.fromYaml(
        fixtures('notice: pin_changed'),
      ).run(pack);
      expect(report.failures, [
        'declined: expected notice "pin_changed", got notice "declined"',
      ]);
    });

    test('fail when an unmatched sample is a notice', () {
      final yaml = fixtures('notice: declined').replaceFirst(
        '    expect:\n      notice: pin_changed',
        '    expect: unmatched',
      );
      expect(PackFixtures.fromYaml(yaml).run(pack).failures, [
        'pin: expected unmatched, got notice "pin_changed"',
      ]);
    });

    test('fail when a transaction sample is a notice', () {
      final yaml = fixtures(
        'notice: declined',
      ).replaceFirst("'Ksh5.00 debited.'", "'Your PIN was changed.'");
      expect(PackFixtures.fromYaml(yaml).run(pack).failures, [
        contains('alert: expected a transaction, got notice "pin_changed"'),
        contains('rule "alert" has no passing sample'),
      ]);
    });

    test('a notice sample takes no other fields', () {
      expect(
        () => PackFixtures.fromYaml(
          fixtures('notice: declined\n      amount_minor: 900'),
        ),
        throwsA(
          isA<PackFormatException>().having((e) => e.problems, 'problems', [
            contains('a notice reads no fields'),
          ]),
        ),
      );
    });
  });
}

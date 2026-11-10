import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'helpers.dart';

void main() {
  final pack = ParserPack.fromYaml(testPackYaml);
  final parser = SmsParser([pack]);
  final receivedAt = DateTime.utc(2026, 10, 26, 7);

  SmsMessage sms(String body, {String sender = 'EXWALLET'}) =>
      SmsMessage(sender: sender, body: body, receivedAt: receivedAt);

  test('ignores senders that are not selected', () {
    expect(parser.parse(sms(testSentBody, sender: 'PROMO')), isA<Ignored>());
  });

  test('matches senders case-insensitively', () {
    expect(
      parser.parse(sms(testSentBody, sender: ' exwallet ')),
      isA<ParsedTransaction>(),
    );
  });

  test('parses fields into a typed transaction with integer cents', () {
    final t = parser.parse(sms(testSentBody)) as ParsedTransaction;
    expect(t.packId, 'example_wallet');
    expect(t.packVersion, '1.0.0');
    expect(t.ruleId, 'sent');
    expect(t.type, TransactionType.sent);
    expect(t.direction, Direction.outgoing);
    expect(t.amountMinor, 150000);
    expect(t.feeMinor, 1500);
    expect(t.balanceMinor, 325000);
    expect(t.currency, 'KES');
    expect(t.receipt, 'EX0001');
    expect(t.counterparty, 'JANE DOE');
    expect(t.account, isNull);
    expect(t.time, DateTime.utc(2026, 10, 26, 6, 15));
    expect(t.timeFromMessage, isTrue);
  });

  test('collapses runs of spaces in the counterparty', () {
    final body = testSentBody.replaceFirst('JANE DOE', 'JANE  DOE');
    final t = parser.parse(sms(body)) as ParsedTransaction;
    expect(t.counterparty, 'JANE DOE');
  });

  test('keeps a hash of the raw text and a dedupe key, not the text', () {
    final t = parser.parse(sms(testSentBody)) as ParsedTransaction;
    expect(t.rawHash, hashMessageBody(testSentBody));
    expect(t.rawHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(t.dedupeKey, 'EX0001|150000|2026-10-26T06:15Z');
  });

  test('dedupe key matches a statement line at the same minute', () {
    final t = parser.parse(sms(testSentBody)) as ParsedTransaction;
    final fromStatement = dedupeKeyFor(
      receipt: 'ex0001',
      amountMinor: 150000,
      time: DateTime.utc(2026, 10, 26, 6, 15, 42),
    );
    expect(fromStatement, t.dedupeKey);
  });

  test('maps a captured direction and falls back to the received time', () {
    final t = parser.parse(sms('Ksh20.00 credited.')) as ParsedTransaction;
    expect(t.direction, Direction.incoming);
    expect(t.type, TransactionType.bank);
    expect(t.time, receivedAt);
    expect(t.timeFromMessage, isFalse);
  });

  test('sends unmatched messages from known senders to review', () {
    final result = parser.parse(sms('Your PIN was changed.'));
    expect(result, isA<Unmatched>());
    final unmatched = result as Unmatched;
    expect(unmatched.packId, 'example_wallet');
    expect(unmatched.message.body, 'Your PIN was changed.');
    expect(unmatched.rawHash, hashMessageBody('Your PIN was changed.'));
  });

  test('an unknown captured direction is unmatched, not guessed', () {
    final result = parser.parse(sms('Ksh20.00 reserved.'));
    expect(result, isA<Unmatched>());
    expect((result as Unmatched).reason, contains('direction'));
  });

  test('an impossible time is unmatched, not guessed', () {
    final body = testSentBody.replaceFirst('26/10/2026', '31/02/2026');
    expect(parser.parse(sms(body)), isA<Unmatched>());
  });

  group('the currency printed with the amount', () {
    final multi = ParserPack.fromYaml(r'''
schema: 1
id: example_bank
name: Example Bank
version: 1.0.0
currency: KES
utc_offset: "+03:00"
senders: [EXBANK]
rules:
  - id: alert
    type: bank
    direction: in
    pattern: '^(?<currency>[A-Za-z.]{3,5}) ?(?<amount>[\d,]+\.\d{2}) into (?<own_account>[\d*]+)\.$'
''');
    final bank = SmsParser([multi]);
    ParseResult read(String body) => bank.parse(sms(body, sender: 'EXBANK'));

    test('wins over the pack currency, with the own account', () {
      final t = read('USD 250.00 into 0170****8765.') as ParsedTransaction;
      expect(t.currency, 'USD');
      expect(t.amountMinor, 25000);
      expect(t.ownAccount, '0170****8765');
      expect(t.account, isNull);
    });

    test('reads Ksh and Kshs as KES', () {
      expect(
        (read('Kshs 10.00 into 01**1.') as ParsedTransaction).currency,
        'KES',
      );
      expect(
        (read('KSh. 10.00 into 01**1.') as ParsedTransaction).currency,
        'KES',
      );
    });

    test('an unreadable currency is unmatched, not guessed', () {
      expect(read('U.S. 10.00 into 01**1.'), isA<Unmatched>());
    });

    test('a pack without the group keeps its own currency', () {
      final t = parser.parse(sms(testSentBody)) as ParsedTransaction;
      expect(t.currency, 'KES');
      expect(t.ownAccount, isNull);
    });
  });

  test('currencyCode', () {
    expect(currencyCode('eur'), 'EUR');
    expect(currencyCode('Ksh'), 'KES');
    expect(currencyCode('US\$'), isNull);
  });

  test('two packs may not claim the same sender', () {
    final clash = ParserPack.fromYaml(
      testPackYaml.replaceFirst('id: example_wallet', 'id: other'),
    );
    expect(() => SmsParser([pack, clash]), throwsArgumentError);
  });
}

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

/// Two institutions' messages about the same money expose the same code, so
/// the app can keep one transfer for both. Synthetic messages only.
void main() {
  final parser = SmsParser(loadBundledPacks());
  final at = DateTime.utc(2026, 11, 14, 8, 11);

  ParsedTransaction parse(String sender, String body) {
    final result = parser.parse(
      SmsMessage(sender: sender, body: body, receivedAt: at),
    );
    expect(result, isA<ParsedTransaction>(), reason: body);
    return result as ParsedTransaction;
  }

  test('an Etica payout and its M-Pesa credit share the M-Pesa receipt', () {
    final etica = parse(
      'ETICA',
      'Dear esteemed client, Your payment of KES 400.00 to 0700000000 - '
          'JANE DOE from account 000000M (EMMF - KES) has been processed '
          'successfully. Transaction ref: TJA0000035',
    );
    final mpesa = parse(
      'MPESA',
      'TJA0000035 Confirmed.You have received Ksh400.00 from ETICA CAPITAL '
          'LTD on 14/11/26 at 11:10 AM New M-PESA balance is Ksh1,500.50.',
    );
    expect(etica.accountInstitution, 'etica');
    expect(etica.direction, Direction.outgoing);
    expect(mpesa.accountInstitution, 'mpesa');
    expect(mpesa.direction, Direction.incoming);
    expect(etica.receipt, mpesa.receipt);
    expect(etica.amountMinor, mpesa.amountMinor);
  });

  test('an M-Pesa send to Airtel Money is the Airtel credit\'s Sender TID', () {
    final mpesa = parse(
      'MPESA',
      'TJA0000037 Confirmed. Ksh100.00 sent to AIRTEL MONEY for account '
          '0730000000 on 14/11/26 at 3:00 PM New M-PESA balance is '
          'Ksh4,885.50. Transaction cost, Ksh15.00.',
    );
    final airtel = parse(
      'AirtelMoney',
      'TID:TJA0000040. Received Ksh 100 from JOHN DOE 0711000000 on '
          '14/11/26 15:00. Bal Ksh 220. Sender TID:TJA0000037.',
    );
    expect(airtel.receipt, 'TJA0000040');
    expect(airtel.account, mpesa.receipt);
    expect(airtel.amountMinor, mpesa.amountMinor);
  });

  test('Ziidi and Pochi movements are told apart from plain sends', () {
    final ziidi = parse(
      'MPESA',
      'TJA0000030 Confirmed. Ksh1,000.00 sent to ZIIDI on 12/11/26 at 2:30 '
          'PM New M-PESA balance is Ksh50.00. Transaction cost, Ksh0.00.',
    );
    expect(ziidi.ruleId, 'ziidi_deposit');
    expect(ziidi.receipt, 'TJA0000030');

    final pochi = parse(
      'MPESA',
      'TJA0000039 Confirmed.You have received Ksh200.00 from JOHN DOE '
          '0711***000 on 15/11/26 at 8:40 AM New Pochi balance is '
          'Ksh1,200.00.',
    );
    expect(pochi.ruleId, 'pochi_received');
    expect(pochi.ownAccount, 'Pochi');
  });
}

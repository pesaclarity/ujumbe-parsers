/// A minimal valid pack used across tests. Synthetic sender and wording.
const testPackYaml = r'''
schema: 1
id: example_wallet
name: Example Wallet
version: 1.0.0
currency: KES
utc_offset: "+03:00"
senders: [EXWALLET]
time_format: "dd/MM/yyyy HH:mm"
rules:
  - id: sent
    type: sent
    direction: out
    pattern: '^(?<receipt>EX\d{4}) sent Ksh(?<amount>[\d,]+\.\d{2}) to (?<counterparty>.+?) on (?<time>\d{2}/\d{2}/\d{4} \d{2}:\d{2})\. Fee Ksh(?<fee>[\d,]+\.\d{2})\. Bal Ksh(?<balance>[\d,]+\.\d{2})\.$'
  - id: alert
    type: bank
    direction_values: {debited: out, credited: in}
    pattern: '^Ksh(?<amount>[\d,]+\.\d{2}) (?<direction>\w+)\.$'
''';

/// A message [testPackYaml]'s `sent` rule matches.
const testSentBody =
    'EX0001 sent Ksh1,500.00 to JANE DOE on 26/10/2026 09:15. '
    'Fee Ksh15.00. Bal Ksh3,250.00.';

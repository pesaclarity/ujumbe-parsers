import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'support/synthetic_pages.dart';
import 'support/synthetic_statement.dart';

final _mpesa = loadBundledStatementPack('mpesa_statement');

void main() {
  group('the M-Pesa pack matches the text reader', () {
    for (final linesPerPage in [3, 7, 100]) {
      for (final newestFirst in [true, false]) {
        for (final detailsWidth in [20, 34]) {
          final label =
              '$linesPerPage lines a page, '
              '${newestFirst ? 'newest' : 'oldest'} first, '
              'details wrapped at $detailsWidth';
          test(label, () {
            final fromPages = StatementReader(_mpesa).read(
              syntheticStatementPages(
                syntheticOctober,
                openingBalance: syntheticOpening,
                linesPerPage: linesPerPage,
                newestFirst: newestFirst,
                detailsWidth: detailsWidth,
              ),
            );
            final fromText = const MpesaStatementParser().parse(
              syntheticStatement(
                syntheticOctober,
                openingBalance: syntheticOpening,
                linesPerPage: linesPerPage,
                newestFirst: newestFirst,
                detailsWidth: detailsWidth,
              ),
            );

            expect(fromPages.reconciles, isTrue);
            expect(fromPages.periodStart, fromText.periodStart);
            expect(fromPages.periodEnd, fromText.periodEnd);
            expect(fromPages.openingBalanceMinor, syntheticOpening);
            expect(fromPages.closingBalanceMinor, syntheticClosing);
            expect(fromPages.lines, hasLength(fromText.rows.length));
            expect(
              fromPages.transactions.map(_fields),
              fromText.transactions.map(_fields),
            );
          });
        }
      }
    }
  });

  test('statement rows share the SMS dedupe key', () {
    final sms =
        SmsParser([loadBundledPack('mpesa')]).parse(
              SmsMessage(
                sender: 'MPESA',
                body:
                    'TJA0000001 Confirmed. Ksh1,500.00 sent to JANE DOE '
                    '0700***001 on 26/10/26 at 9:15 AM. New M-PESA balance is '
                    'Ksh5,485.00. Transaction cost, Ksh15.00.',
                receivedAt: DateTime.utc(2026, 10, 26, 6, 16),
              ),
            )
            as ParsedTransaction;
    final read = StatementReader(_mpesa).read(
      syntheticStatementPages(
        syntheticOctober,
        openingBalance: syntheticOpening,
      ),
    );
    final row = read.transactions.firstWhere((t) => t.receipt == 'TJA0000001');
    expect(row.dedupeKey, sms.dedupeKey);
    expect(row.feeMinor, sms.feeMinor);
    expect(row.balanceMinor, sms.balanceMinor);
    expect(row.counterparty, sms.counterparty);
    expect(row.account, sms.account);
    expect(row.packId, 'mpesa');
  });

  test('a missing row shows up as a balance break', () {
    final read = StatementReader(_mpesa).read(
      syntheticStatementPages(
        syntheticOctober,
        openingBalance: syntheticOpening,
        omit: {'TJA0000004'},
      ),
    );
    expect(read.reconciles, isFalse);
    expect(read.balanceBreaks.single.gapMinor, -35000);
  });

  test('a row with an unreadable amount is held, not guessed', () {
    final pages = [
      typesetPage([
        'M-PESA STATEMENT',
        [
          'Receipt No.',
          'Completion Time',
          'Details',
          'Transaction Status',
          'Paid In',
          'Withdrawn',
          'Balance',
        ],
        [
          'TJA0000001',
          '2026-10-26 09:15:42',
          'Airtime Purchase',
          'Completed',
          '',
          '-1O0.00',
          '900.00',
        ],
      ], mpesaColumns),
    ];
    final read = StatementReader(_mpesa).read(pages);
    expect(read.transactions, isEmpty);
    expect(read.unreadLines, hasLength(1));
    expect(read.reconciles, isFalse);
  });

  group('detectStatementPack', () {
    test('picks the pack whose first page matches', () {
      final pages = syntheticStatementPages(
        syntheticOctober,
        openingBalance: syntheticOpening,
      );
      expect(
        detectStatementPack(pages, loadBundledStatementPacks())?.id,
        'mpesa_statement',
      );
    });

    test('returns null for other statements', () {
      final pages = [
        typesetPage(['EXAMPLE BANK', 'Account statement'], mpesaColumns),
      ];
      expect(detectStatementPack(pages, loadBundledStatementPacks()), isNull);
      expect(
        detectStatementPack(const [], loadBundledStatementPacks()),
        isNull,
      );
    });
  });

  group('a bank layout with one amount column and a DR or CR marker', () {
    final pack = StatementPack.fromYaml(_bankPack, source: 'test');
    const columns = [
      FixtureColumn(30),
      FixtureColumn(95),
      FixtureColumn(140),
      FixtureColumn(400, rightAligned: true),
      FixtureColumn(420),
      FixtureColumn(520, rightAligned: true),
    ];

    test('reads dates, times, markers and wrapped descriptions', () {
      final read = StatementReader(pack).read([
        typesetPage([
          'EXAMPLE BANK LIMITED',
          'Statement from 01/10/2026 to 31/10/2026',
          ['Date', 'Time', 'Narration', 'Amount', 'Dr/Cr', 'Balance'],
          [
            '02/10/2026',
            '10:15',
            'SALARY EXAMPLE LTD',
            '50,000.00',
            'CR',
            '60,000.00',
          ],
          [
            '03/10/2026',
            '18:40',
            'POS PURCHASE EXAMPLE',
            '1,250.50',
            'DR',
            '58,749.50',
          ],
          ['', '', 'SUPERMARKET NAIROBI', '', '', ''],
          ['', '', '', '', '', ''],
          'Page 1 of 1',
        ], columns),
      ]);
      expect(read.reconciles, isTrue);
      expect(read.periodStart, DateTime.utc(2026, 10));
      expect(read.periodEnd, DateTime.utc(2026, 10, 31));
      expect(read.openingBalanceMinor, 1000000);
      expect(read.closingBalanceMinor, 5874950);

      final [salary, purchase] = read.transactions;
      expect(salary.direction, Direction.incoming);
      expect(salary.type, TransactionType.received);
      expect(salary.counterparty, 'EXAMPLE LTD');
      expect(salary.time, DateTime.utc(2026, 10, 2, 7, 15));
      expect(salary.packId, 'example_bank');
      expect(purchase.direction, Direction.outgoing);
      expect(purchase.amountMinor, 125050);
      expect(purchase.type, TransactionType.bank);
      expect(purchase.ruleId, 'statement_other');
      expect(purchase.receipt, isNull);
    });

    test('a marker it does not know leaves the row unread', () {
      final read = StatementReader(pack).read([
        typesetPage([
          ['Date', 'Time', 'Narration', 'Amount', 'Dr/Cr', 'Balance'],
          ['02/10/2026', '10:15', 'TRANSFER', '500.00', '??', '500.00'],
        ], columns),
      ]);
      expect(read.lines, isEmpty);
      expect(read.unreadLines, hasLength(1));
    });
  });

  test('a signed amount column reads the sign as the direction', () {
    final pack = StatementPack.fromYaml(
      _bankPack
          .replaceFirst("  - key: marker\n    header: '^Dr/Cr\$'\n", '')
          .replaceFirst(
            "  marker_out: '^DR\$'\n  marker_in: '^CR\$'",
            '  negative_is: out',
          ),
      source: 'test',
    );
    final read = StatementReader(pack).read([
      typesetPage(
        [
          ['Date', 'Time', 'Narration', 'Amount', 'Balance'],
          ['02/10/2026', '10:15', 'SALARY EXAMPLE LTD', '500.00', '1,500.00'],
          ['02/10/2026', '11:00', 'ATM CASH', '-200.00', '1,300.00'],
        ],
        const [
          FixtureColumn(30),
          FixtureColumn(95),
          FixtureColumn(140),
          FixtureColumn(400, rightAligned: true),
          FixtureColumn(520, rightAligned: true),
        ],
      ),
    ]);
    expect(read.transactions.map((t) => t.direction), [
      Direction.incoming,
      Direction.outgoing,
    ]);
    expect(read.reconciles, isTrue);
  });
}

Map<String, Object?> _fields(ParsedTransaction t) => {
  'ruleId': t.ruleId.replaceFirst('statement_', ''),
  'type': t.type,
  'direction': t.direction,
  'amount': t.amountMinor,
  'fee': t.feeMinor,
  'balance': t.balanceMinor,
  'receipt': t.receipt,
  'counterparty': t.counterparty,
  'account': t.account,
  'time': t.time,
  'dedupe': t.dedupeKey,
};

const _bankPack = r'''
schema: 1
id: example_bank_statement
institution: example_bank
name: Example Bank statement
version: 0.1.0
currency: KES
utc_offset: "+03:00"
detect:
  - '^EXAMPLE BANK LIMITED$'
period: 'Statement from (?<start>\d{2}/\d{2}/\d{4}) to (?<end>\d{2}/\d{2}/\d{4})'
period_format: dd/MM/yyyy
columns:
  - key: date
    header: '^Date$'
    format: dd/MM/yyyy
  - key: time
    header: '^Time$'
    format: HH:mm
  - key: description
    header: '^Narration$'
  - key: amount
    header: '^Amount$'
    align: right
  - key: marker
    header: '^Dr/Cr$'
  - key: balance
    header: '^Balance$'
    align: right
row_starts_with: date
order: oldest_first
skip:
  - '^Page \d+ of \d+$'
amount:
  marker_out: '^DR$'
  marker_in: '^CR$'
rules:
  - id: salary
    type: received
    pattern: '^SALARY (?<counterparty>.+)$'
''';

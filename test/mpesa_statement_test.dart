import 'dart:math';

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'support/synthetic_statement.dart';

const _opening = 500000;

const _october = [
  SyntheticEntry(
    'TJA0000003',
    '2026-10-26 08:02:10',
    'Funds received from 0700***002 - JOHN KAMAU',
    paidIn: 200000,
  ),
  SyntheticEntry(
    'TJA0000001',
    '2026-10-26 09:15:42',
    'Customer Transfer to 0700***001 - JANE DOE',
    withdrawn: 150000,
  ),
  SyntheticEntry(
    'TJA0000001',
    '2026-10-26 09:15:42',
    'Customer Transfer of Funds Charge',
    withdrawn: 1500,
  ),
  SyntheticEntry(
    'TJA0000002',
    '2026-10-26 11:30:05',
    'Pay Bill Online to 888880 - EXAMPLE POWER LTD Acc. 1234567890',
    withdrawn: 120000,
  ),
  SyntheticEntry(
    'TJA0000002',
    '2026-10-26 11:30:05',
    'Pay Bill Charge',
    withdrawn: 1500,
  ),
  SyntheticEntry(
    'TJA0000004',
    '2026-10-26 13:45:00',
    'Merchant Payment Online to 5000001 - EXAMPLE GROCERS',
    withdrawn: 35000,
  ),
  SyntheticEntry(
    'TJA0000005',
    '2026-10-26 17:10:30',
    'Customer Withdrawal At Agent Till 123456 - EXAMPLE AGENT SHOP NAIROBI',
    withdrawn: 100000,
  ),
  SyntheticEntry(
    'TJA0000005',
    '2026-10-26 17:10:30',
    'Withdrawal Charge',
    withdrawn: 2900,
  ),
  SyntheticEntry(
    'TJA0000006',
    '2026-10-26 19:00:00',
    'Airtime Purchase',
    withdrawn: 10000,
  ),
  SyntheticEntry(
    'TJA0000011',
    '2026-10-26 20:00:00',
    'Customer Transfer to 0700***003 - MARY WANJIRU',
    withdrawn: 50000,
    status: 'Failed',
  ),
  SyntheticEntry(
    'TJA0000010',
    '2026-10-27 08:05:00',
    'Business Payment from 400001 - EXAMPLE SACCO via API',
    paidIn: 500000,
  ),
];

const _closing = 779100;

const _parser = MpesaStatementParser();

void main() {
  group('a synthetic October statement', () {
    for (final linesPerPage in [3, 7, 100]) {
      for (final amountsOnLastLine in [false, true]) {
        for (final newestFirst in [true, false]) {
          for (final twoAmountColumns in [false, true]) {
            final label =
                '$linesPerPage lines a page, '
                'amounts on ${amountsOnLastLine ? 'last' : 'first'} line, '
                '${newestFirst ? 'newest' : 'oldest'} first, '
                '${twoAmountColumns ? 'two' : 'one'} amount column(s)';
            test(label, () {
              final text = syntheticStatement(
                _october,
                openingBalance: _opening,
                linesPerPage: linesPerPage,
                amountsOnLastLine: amountsOnLastLine,
                newestFirst: newestFirst,
                twoAmountColumns: twoAmountColumns,
              );
              _expectOctober(_parser.parse(text));
            });
          }
        }
      }
    }
  });

  test('statement rows share the SMS dedupe key', () {
    final sms = SmsParser([loadBundledPack('mpesa')]).parse(
      SmsMessage(
        sender: 'MPESA',
        body:
            'TJA0000001 Confirmed. Ksh1,500.00 sent to JANE DOE 0700***001 '
            'on 26/10/26 at 9:15 AM. New M-PESA balance is Ksh5,485.00. '
            'Transaction cost, Ksh15.00.',
        receivedAt: DateTime.utc(2026, 10, 26, 6, 16),
      ),
    );
    final statement = _parser.parse(
      syntheticStatement(_october, openingBalance: _opening),
    );
    final row = statement.transactions.firstWhere(
      (t) => t.receipt == 'TJA0000001',
    );
    final fromSms = sms as ParsedTransaction;
    expect(row.dedupeKey, fromSms.dedupeKey);
    expect(row.amountMinor, fromSms.amountMinor);
    expect(row.feeMinor, fromSms.feeMinor);
    expect(row.balanceMinor, fromSms.balanceMinor);
    expect(row.counterparty, fromSms.counterparty);
    expect(row.account, fromSms.account);
    expect(row.type, fromSms.type);
  });

  test('a missing row shows up as a balance break', () {
    final statement = _parser.parse(
      syntheticStatement(
        _october,
        openingBalance: _opening,
        omit: {'TJA0000004'},
      ),
    );
    expect(statement.reconciles, isFalse);
    expect(statement.balanceBreaks, hasLength(1));
    final gap = statement.balanceBreaks.single;
    expect(gap.receipt, 'TJA0000005');
    expect(gap.gapMinor, -35000);
    expect(statement.closingBalanceMinor, _closing);
  });

  test('a row without amounts is kept for review', () {
    final statement = _parser.parse(
      syntheticStatement(
        _october,
        openingBalance: _opening,
        newestFirst: false,
        extraTableLines: [
          'TJA0000099 2026-10-28 10:00:00 Customer Transfer to 0700***009',
        ],
      ),
    );
    expect(statement.unreadLines, [
      'TJA0000099 2026-10-28 10:00:00 Customer Transfer to 0700***009',
    ]);
    expect(statement.reconciles, isFalse);
    expect(statement.transactions, hasLength(7));
  });

  test('a fee row without its payment stays a transaction', () {
    final statement = _parser.parse(
      syntheticStatement(const [
        SyntheticEntry(
          'TJA0000020',
          '2026-10-28 10:00:00',
          'Pay Bill Charge',
          withdrawn: 1500,
        ),
      ], openingBalance: 10000),
    );
    final t = statement.transactions.single;
    expect(t.ruleId, 'statement_charge');
    expect(t.type, TransactionType.bank);
    expect(t.direction, Direction.outgoing);
    expect(t.amountMinor, 1500);
    expect(t.feeMinor, isNull);
  });

  test('Fuliza draws, repayments and reversals are typed', () {
    final statement = _parser.parse(
      syntheticStatement(const [
        SyntheticEntry(
          'TJA0000030',
          '2026-10-28 10:00:00',
          'OverDraft of Credit Party',
          paidIn: 15000,
        ),
        SyntheticEntry(
          'TJA0000030',
          '2026-10-28 10:00:00',
          'Merchant Payment Fuliza M-Pesa to 5000002 - EXAMPLE KIOSK',
          withdrawn: 15000,
        ),
        SyntheticEntry(
          'TJA0000031',
          '2026-10-29 08:00:00',
          'OD Loan Repayment to 232323 - M-PESA Overdraw',
          withdrawn: 15150,
        ),
        SyntheticEntry(
          'TJA0000032',
          '2026-10-29 09:00:00',
          'Reversal of TJA0000001',
          paidIn: 150000,
        ),
        SyntheticEntry(
          'TJA0000033',
          '2026-10-29 10:00:00',
          'Deposit of Funds at Agent Till 123456 - EXAMPLE AGENT',
          paidIn: 50000,
        ),
      ], openingBalance: 20000),
    );
    expect(statement.transactions.map((t) => t.type), [
      TransactionType.fuliza,
      TransactionType.till,
      TransactionType.fulizaRepayment,
      TransactionType.reversal,
      TransactionType.bank,
    ]);
    expect(statement.transactions[1].counterparty, 'EXAMPLE KIOSK');
    expect(statement.transactions[3].account, 'TJA0000001');
    expect(statement.transactions[4].ruleId, 'statement_other');
    expect(statement.reconciles, isTrue);
  });

  test('text with no table gives an empty statement', () {
    final statement = _parser.parse('M-PESA STATEMENT\nNothing here.\n');
    expect(statement.rows, isEmpty);
    expect(statement.transactions, isEmpty);
    expect(statement.openingBalanceMinor, isNull);
    expect(statement.closingBalanceMinor, isNull);
    expect(statement.periodStart, isNull);
    expect(statement.reconciles, isTrue);
  });

  test('an impossible completion time is unread', () {
    final statement = _parser.parse(
      'Receipt No. Completion Time Details Transaction Status Paid In '
      'Withdrawn Balance\n'
      'TJA0000040 2026-02-30 10:00:00 Airtime Purchase Completed -100.00 '
      '900.00\n',
    );
    expect(statement.rows, isEmpty);
    expect(statement.unreadLines, hasLength(1));
  });

  test('random synthetic statements reconcile', () {
    final random = Random(20261026);
    for (var run = 0; run < 25; run++) {
      final entries = _randomEntries(random, 40);
      final opening = random.nextInt(1000000);
      final statement = _parser.parse(
        syntheticStatement(
          entries,
          openingBalance: opening,
          linesPerPage: 2 + random.nextInt(30),
          detailsWidth: 12 + random.nextInt(30),
          amountsOnLastLine: random.nextBool(),
          newestFirst: random.nextBool(),
          twoAmountColumns: random.nextBool(),
        ),
      );
      final completed = entries.where((e) => e.status == 'Completed');
      final net = completed.fold<int>(
        0,
        (sum, e) => sum + e.paidIn - e.withdrawn,
      );
      expect(statement.reconciles, isTrue, reason: 'run $run');
      expect(statement.rows, hasLength(entries.length));
      expect(statement.openingBalanceMinor, opening);
      expect(statement.closingBalanceMinor, opening + net);
      expect(
        statement.transactions.map((t) => t.receipt),
        completed.map((e) => e.receipt),
      );
    }
  });
}

void _expectOctober(MpesaStatement s) {
  expect(s.unreadLines, isEmpty);
  expect(s.balanceBreaks, isEmpty);
  expect(s.reconciles, isTrue);
  expect(s.periodStart, DateTime.utc(2026, 10, 1));
  expect(s.periodEnd, DateTime.utc(2026, 10, 31));
  expect(s.openingBalanceMinor, _opening);
  expect(s.closingBalanceMinor, _closing);
  expect(s.rows, hasLength(_october.length));
  expect(s.rows.where((r) => !r.isCompleted).single.receipt, 'TJA0000011');

  final t = s.transactions;
  expect(t.map((x) => x.receipt), [
    'TJA0000003',
    'TJA0000001',
    'TJA0000002',
    'TJA0000004',
    'TJA0000005',
    'TJA0000006',
    'TJA0000010',
  ]);
  expect(t.map((x) => x.type), [
    TransactionType.received,
    TransactionType.sent,
    TransactionType.paybill,
    TransactionType.till,
    TransactionType.withdrawal,
    TransactionType.airtime,
    TransactionType.received,
  ]);
  expect(t.map((x) => x.feeMinor), [null, 1500, 1500, null, 2900, null, null]);
  expect(t.every((x) => x.packId == 'mpesa' && x.currency == 'KES'), isTrue);

  final received = t[0];
  expect(received.direction, Direction.incoming);
  expect(received.amountMinor, 200000);
  expect(received.counterparty, 'JOHN KAMAU');
  expect(received.account, '0700***002');
  expect(received.time, DateTime.utc(2026, 10, 26, 5, 2, 10));
  expect(received.balanceMinor, 700000);

  final sent = t[1];
  expect(sent.direction, Direction.outgoing);
  expect(sent.amountMinor, 150000);
  expect(sent.counterparty, 'JANE DOE');
  expect(sent.account, '0700***001');
  expect(sent.balanceMinor, 548500);
  expect(sent.ruleId, 'statement_sent');

  final paybill = t[2];
  expect(paybill.counterparty, 'EXAMPLE POWER LTD');
  expect(paybill.account, '1234567890');
  expect(paybill.balanceMinor, 427000);

  expect(t[3].counterparty, 'EXAMPLE GROCERS');
  expect(t[4].counterparty, 'EXAMPLE AGENT SHOP NAIROBI');
  expect(t[4].account, '123456');
  expect(t[6].counterparty, 'EXAMPLE SACCO');
  expect(t[6].account, '400001');
}

List<SyntheticEntry> _randomEntries(Random random, int count) {
  const shapes = [
    'Customer Transfer to 0700***0{n} - EXAMPLE PERSON {n}',
    'Funds received from 0700***0{n} - EXAMPLE SENDER {n}',
    'Pay Bill Online to 88{n} - EXAMPLE BILLER {n} Acc. ACC{n}',
    'Merchant Payment Online to 50{n} - EXAMPLE SHOP NUMBER {n}',
    'Airtime Purchase',
  ];
  final entries = <SyntheticEntry>[];
  var minute = 0;
  for (var i = 0; i < count; i++) {
    final n = (10 + random.nextInt(89)).toString();
    final shape = shapes[random.nextInt(shapes.length)];
    minute += 1 + random.nextInt(600);
    final time = DateTime.utc(2026, 10, 1).add(Duration(minutes: minute));
    final stamp =
        '${time.year}-${_two(time.month)}-${_two(time.day)} '
        '${_two(time.hour)}:${_two(time.minute)}:${_two(random.nextInt(60))}';
    final receipt = 'TJR${i.toString().padLeft(7, '0')}';
    final amount = 100 * (1 + random.nextInt(5000));
    final incoming = shape.startsWith('Funds');
    entries.add(
      SyntheticEntry(
        receipt,
        stamp,
        shape.replaceAll('{n}', n),
        paidIn: incoming ? amount : 0,
        withdrawn: incoming ? 0 : amount,
        status: random.nextInt(10) == 0 ? 'Failed' : 'Completed',
      ),
    );
  }
  return entries;
}

String _two(int v) => v.toString().padLeft(2, '0');

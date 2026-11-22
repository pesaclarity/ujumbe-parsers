import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

// Synthetic KCB-style pages, built word by word: JANE DOE and JOHN DOE,
// made-up references and amounts.
final _kcb = loadBundledStatementPack('kcb_statement');

const _columns = [20.0, 80.0, 140.0, 230.0, 370.0, 500.0, 570.0, 650.0];
const _right = {5, 6, 7};

/// A word [text] in column [c] (right-aligned columns end at their edge),
/// or at [x] when given, on the line whose top is [top].
List<PageWord> _cell(int c, String text, double top, {double height = 6}) {
  final parts = text.split(' ').where((p) => p.isNotEmpty).toList();
  final width = parts.join(' ').length * 4.0;
  var x = _right.contains(c) ? _columns[c] - width : _columns[c];
  return [
    for (final part in parts)
      () {
        final word = PageWord(
          part,
          x,
          top,
          x + part.length * 4.0,
          top + height,
        );
        x += (part.length + 1) * 4.0;
        return word;
      }(),
  ];
}

List<PageWord> _line(double top, Map<int, String> cells) => [
  for (final e in cells.entries) ..._cell(e.key, e.value, top),
];

List<PageWord> _text(double top, String text) => _cell(0, text, top);

List<PageWord> _headerBlock({required String closing}) => [
  ..._text(10, 'Transactional Account PAYG Statement'),
  ..._text(20, 'Statement Period'),
  ..._text(28, '2026-09-01 - 2026-09-30'),
  ..._text(40, 'Balance at Period Start: KES 1,000.00'),
  ..._text(50, 'Balance at Period End: KES $closing'),
  ..._line(70, const {
    0: 'TXN Date',
    1: 'Value Date',
    2: 'Transaction Type',
    3: 'Transaction Details',
    4: 'Reference',
    5: 'Money Out',
    6: 'Money In',
    7: 'Running Balance',
  }),
];

Map<int, String> _anchor(
  String ref, {
  String out = '',
  String into = '',
  required String balance,
  String kind = '',
  String details = '',
}) => {
  0: '05/Sep/2026',
  1: '05/Sep/2026',
  if (kind.isNotEmpty) 2: kind,
  if (details.isNotEmpty) 3: details,
  4: ref,
  if (out.isNotEmpty) 5: out,
  if (into.isNotEmpty) 6: into,
  7: balance,
};

void main() {
  test('text above and below the date joins its row; rows part by space', () {
    // Lines 4.5 points apart within a row, 16 between rows, as KCB prints.
    final page = StatementPage([
      ..._headerBlock(closing: '700.00'),
      ..._line(84, const {3: 'BALANCE FWD', 7: '1,000.00'}),
      ..._line(100, const {2: 'Mobile Money', 3: '254700000001-JANE'}),
      ..._line(
        104.5,
        _anchor('FT00000AAA01', out: '-250.00', balance: '750.00'),
      ),
      ..._line(109, const {2: 'Transfer', 3: 'DOE Mobile Money'}),
      ..._line(125, const {3: '254700000001-JANE'}),
      ..._line(
        129.5,
        _anchor(
          'FT00000AAA01',
          out: '-50.00',
          balance: '700.00',
          kind: 'Transfer Charge',
        ),
      ),
      ..._line(134, const {3: 'DOE Mobile Money'}),
      ..._text(200, 'Showing page 1 of 1'),
      ..._text(210, 'Synthetic footer text, not a real record.'),
    ]);

    final statement = StatementReader(_kcb).read([page]);

    expect(statement.lines.map((l) => l.kind), [
      'Mobile Money Transfer',
      'Transfer Charge',
    ]);
    expect(
      statement.lines.first.description,
      '254700000001-JANE DOE Mobile Money',
    );
    expect(statement.transactions, hasLength(1));
    final sent = statement.transactions.single;
    expect(sent.ruleId, 'statement_mobile_money');
    expect(sent.type, TransactionType.sent);
    expect(sent.account, '254700000001');
    expect(sent.counterparty, 'JANE DOE');
    expect(sent.feeMinor, 5000);
    expect(sent.balanceMinor, 70000);
    expect(statement.unreadLines, isEmpty);
    expect(statement.reconciles, isTrue);
  });

  test('large header text overlaid on the table, and the dash beside it, '
      'are dropped', () {
    final page = StatementPage([
      ..._headerBlock(closing: '750.00'),
      ..._line(100, const {2: 'Mobile Money', 3: '254700000001-JANE'}),
      ..._line(
        104.5,
        _anchor('FT00000AAA01', out: '-250.00', balance: '750.00'),
      ),
      ..._line(109, const {2: 'Transfer', 3: 'DOE Mobile Money'}),
      // "Statement Period 2026-09-01 - 2026-09-30" in large type across
      // the row, with its dash just right of the first date.
      const PageWord('Statement', 230, 96, 330, 114),
      const PageWord('Period', 335, 96, 390, 114),
      const PageWord('2026-09-01', 150, 98, 420, 116),
      const PageWord('-', 430, 106, 437, 107.5),
    ]);

    final statement = StatementReader(_kcb).read([page]);

    expect(statement.unreadLines, isEmpty);
    expect(
      statement.lines.single.description,
      '254700000001-JANE DOE Mobile Money',
    );
    expect(statement.lines.single.moneyOutMinor, 25000);
    expect(statement.reconciles, isTrue);
  });

  test('a row cut by a page break continues on the next page', () {
    final first = StatementPage([
      ..._headerBlock(closing: '400.00'),
      ..._line(84, const {3: 'BALANCE FWD', 7: '1,000.00'}),
      ..._line(
        100,
        _anchor(
          'FT00000AAA01',
          out: '-500.00',
          balance: '500.00',
          kind: 'Transfer',
          details: 'Goal Top Up JANE',
        ),
      ),
      // The head of a row whose date is on the next page.
      ..._line(120, const {2: 'Mobile Money', 3: '254700000002-JOHN'}),
      ..._text(200, 'Showing page 1 of 3'),
    ]);
    final second = StatementPage([
      ..._headerBlock(closing: '400.00'),
      ..._line(84, _anchor('FT00000AAA02', out: '-100.00', balance: '400.00')),
      ..._line(88.5, const {2: 'Transfer', 3: 'DOE Mobile'}),
      ..._text(200, 'Showing page 2 of 3'),
    ]);
    // A closing summary page with no table header.
    final summary = StatementPage([
      ..._text(10, 'Transactional Account PAYG Statement'),
      ..._line(84, const {
        3: 'Balance at Period End',
        5: '-600.00',
        7: '400.00',
      }),
      ..._text(200, 'Showing page 3 of 3'),
    ]);

    final statement = StatementReader(_kcb).read([first, second, summary]);

    expect(statement.lines, hasLength(2));
    expect(statement.lines.last.kind, 'Mobile Money Transfer');
    expect(statement.lines.last.description, '254700000002-JOHN DOE Mobile');
    expect(statement.transactions.first.counterparty, 'JANE');
    expect(statement.transactions.last.counterparty, 'JOHN DOE Mobile');
    expect(statement.unreadLines, isEmpty);
    expect(statement.reconciles, isTrue);
  });

  test('the top of a page can finish the last row of the page before', () {
    final first = StatementPage([
      ..._headerBlock(closing: '900.00'),
      ..._line(100, const {2: 'Pesalink', 3: 'JOHN DOE'}),
      ..._line(
        104.5,
        _anchor(
          'FT00000AAA03',
          out: '-100.00',
          balance: '900.00',
          kind: 'Outgoing',
        ),
      ),
      ..._text(200, 'Showing page 1 of 2'),
    ]);
    final second = StatementPage([
      ..._headerBlock(closing: '900.00'),
      ..._line(84, const {3: '0123456789-EXAMPLE BANK'}),
      ..._text(200, 'Showing page 2 of 2'),
    ]);

    final statement = StatementReader(_kcb).read([first, second]);

    expect(
      statement.lines.single.description,
      'JOHN DOE 0123456789-EXAMPLE BANK',
    );
    expect(statement.transactions.single.counterparty, 'JOHN DOE');
    expect(statement.reconciles, isTrue);
  });

  test('a summary balance that the rows do not reach fails to reconcile', () {
    final page = StatementPage([
      ..._headerBlock(closing: '999.00'),
      ..._line(
        100,
        _anchor(
          'FT00000AAA04',
          into: '100.00',
          balance: '1,100.00',
          kind: 'Direct Credits',
          details: 'EXAMPLE REFUND',
        ),
      ),
    ]);

    final statement = StatementReader(_kcb).read([page]);

    expect(statement.balanceBreaks, isEmpty);
    expect(statement.statedOpeningBalanceMinor, 100000);
    expect(statement.statedClosingBalanceMinor, 99900);
    expect(statement.matchesSummary, isFalse);
    expect(statement.reconciles, isFalse);
  });

  test('a row giving back an earlier one with its reference is a reversal', () {
    final page = StatementPage([
      ..._headerBlock(closing: '1,000.00'),
      ..._line(
        100,
        _anchor(
          'FT00000AAA05',
          out: '-30.00',
          balance: '970.00',
          kind: 'ATM Card Fee',
        ),
      ),
      ..._line(
        120,
        _anchor(
          'FT00000AAA05',
          into: '30.00',
          balance: '1,000.00',
          kind: 'ATM Card Fee',
        ),
      ),
    ]);

    final statement = StatementReader(_kcb).read([page]);

    expect(statement.transactions.map((t) => t.ruleId), [
      'statement_charge',
      'statement_reversal',
    ]);
    final reversal = statement.transactions.last;
    expect(reversal.type, TransactionType.reversal);
    expect(reversal.receipt, isNull);
    expect(reversal.account, 'FT00000AAA05');
    expect(statement.transactions.first.feeMinor, isNull);
    expect(statement.reconciles, isTrue);
  });

  test('rows are dates only, so the pack says it has no times', () {
    expect(_kcb.hasTimes, isFalse);
    expect(loadBundledStatementPack('mpesa_statement').hasTimes, isTrue);
  });
}

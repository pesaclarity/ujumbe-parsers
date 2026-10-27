import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

final _pack = StatementPack.fromYaml(r'''
schema: 1
id: layout_test
institution: example
name: Layout test
version: 0.1.0
currency: KES
utc_offset: "+03:00"
detect: ['.']
columns:
  - { key: date, header: '^Value Date$', format: dd/MM/yyyy }
  - { key: description, header: '^Description$' }
  - { key: money_out, header: '^Debit$', align: right }
  - { key: money_in, header: '^Credit$', align: right }
  - { key: balance, header: '^Running Balance$', align: right }
row_starts_with: date
skip: ['^Page \d+']
''');

PageWord _w(String text, double left, double top, {double width = 0}) =>
    PageWord(
      text,
      left,
      top,
      left + (width == 0 ? text.length * 5 : width),
      top + 9,
    );

void main() {
  test('words slightly off the line stay on it, in reading order', () {
    final lines = pageLines(
      StatementPage([
        _w('second', 80, 101),
        _w('first', 20, 100),
        _w('below', 20, 115),
        _w('', 50, 100),
      ]),
    );
    expect(lines.map((l) => l.map((w) => w.text).join(' ')), [
      'first second',
      'below',
    ]);
  });

  test('small marks such as * , and - stay on their line', () {
    // Boxes as PDFium reports them: tight around each mark's ink.
    final lines = pageLines(
      const StatementPage([
        PageWord('*', 222, 36.9, 224, 38.9),
        PageWord('TJA0000001', 30, 36.9, 68, 42),
        PageWord('-', 244, 39.6, 246, 40.3),
        PageWord(',', 327.9, 41.1, 328.6, 42.9),
        PageWord('JANE', 248, 36.9, 265, 42),
        PageWord('NEXT', 30, 50.7, 50, 56),
      ]),
    );
    expect(lines.map((l) => l.map((w) => w.text).join(' ')), [
      'TJA0000001 * - JANE ,',
      'NEXT',
    ]);
  });

  test('multi-word headers, wide amounts, wrapped text and page breaks', () {
    final header = [
      _w('Value', 20, 60),
      _w('Date', 50, 60),
      _w('Description', 100, 60),
      _w('Debit', 300, 60),
      _w('Credit', 370, 60),
      _w('Running', 430, 60),
      _w('Balance', 470, 60),
    ];
    final pages = [
      StatementPage([
        _w('EXAMPLE', 20, 20),
        _w('BANK', 60, 20),
        ...header,
        _w('01/10/2026', 20, 80),
        // A description far wider than its header.
        _w('CARD', 100, 80),
        _w('PAYMENT', 125, 80),
        _w('EXAMPLE', 165, 80),
        _w('SUPERMARKET', 205, 80),
        // Wider than "Debit" and starting left of it, right-aligned.
        _w('1,234,567.00', 265, 80),
        _w('2,000,000.00', 445, 80),
        _w('NAIROBI', 100, 92),
        _w('Page', 20, 200),
        _w('1', 45, 200),
      ]),
      StatementPage([
        ...header,
        _w('BRANCH', 100, 80),
        _w('02/10/2026', 20, 92),
        _w('SALARY', 100, 92),
        _w('500.00', 375, 92),
        _w('2,000,500.00', 445, 92),
        // A sign printed apart from its number stays in the amount column.
        _w('03/10/2026', 20, 104),
        _w('FEE', 100, 104),
        _w('-', 300, 104),
        _w('5.00', 305, 104),
        _w('2,000,495.00', 445, 104),
      ]),
    ];
    final table = readTable(pages, _pack);
    expect(table.headerFound, isTrue);
    expect(table.outside, ['EXAMPLE BANK']);
    expect(table.rows, hasLength(3));
    expect(table.rows[2][StatementColumnKey.moneyOut], '- 5.00');
    expect(table.rows[2][StatementColumnKey.description], 'FEE');

    final first = table.rows[0];
    expect(first.page, 1);
    expect(
      first[StatementColumnKey.description],
      'CARD PAYMENT EXAMPLE SUPERMARKET NAIROBI BRANCH',
    );
    expect(first[StatementColumnKey.moneyOut], '1,234,567.00');
    expect(first[StatementColumnKey.moneyIn], '');
    expect(first[StatementColumnKey.balance], '2,000,000.00');

    final second = table.rows[1];
    expect(second.page, 2);
    expect(second[StatementColumnKey.moneyIn], '500.00');
    expect(second[StatementColumnKey.moneyOut], '');
  });

  test('centred headers: columns follow the gutters in the body', () {
    // Like the real M-Pesa layout: each header sits in the middle of its
    // column, so values start well left of it or end well right of it.
    final pack = StatementPack.fromYaml(r'''
schema: 1
id: centred
institution: example
name: Centred
version: 0.1.0
currency: KES
utc_offset: "+03:00"
detect: ['.']
columns:
  - { key: reference, header: '^Receipt No\.$' }
  - { key: date, header: '^Completion Time$', format: 'yyyy-MM-dd HH:mm:ss' }
  - { key: description, header: '^Details$' }
  - { key: status, header: '^Transaction Status$' }
  - { key: money_in, header: '^Paid In$', align: right }
  - { key: money_out, header: '^Withdrawn$', align: right, negative: true }
  - { key: balance, header: '^Balance$', align: right }
row_starts_with: reference
skip: ['^Page \d+ of \d+$']
''');
    PageWord at(String text, double left, double top) =>
        PageWord(text, left, top, left + text.length * 3.6, top + 7);
    final page = StatementPage([
      at('Receipt', 51, 60),
      at('No.', 80, 60),
      at('Completion', 111, 60),
      at('Time', 153, 60),
      at('Details', 216, 60),
      at('Transaction', 282, 60),
      at('Status', 326, 60),
      at('Paid', 374, 60),
      at('In', 391, 60),
      at('Withdrawn', 436, 60),
      at('Balance', 511, 60),
      // A payment: details start 38 points left of their header.
      at('TJA0000001', 39, 80),
      at('2026-10-26', 108, 80),
      at('09:15:42', 145, 80),
      at('Merchant', 178, 80),
      at('Payment', 211, 80),
      at('to', 241, 80),
      at('Completed', 283, 80),
      at('-1,500.00', 455, 80),
      at('5,500.00', 528, 80),
      at('5000001', 178, 91),
      at('-', 205, 91),
      at('EXAMPLE', 211, 91),
      // Money in: the amount ends 21 points right of its header.
      at('TJA0000002', 39, 102),
      at('2026-10-26', 108, 102),
      at('10:00:00', 145, 102),
      at('Funds', 178, 102),
      at('received', 199, 102),
      at('Completed', 283, 102),
      at('2,000.00', 388, 102),
      at('7,500.00', 528, 102),
      at('Page', 39, 140),
      at('1', 58, 140),
      at('of', 64, 140),
      at('1', 73, 140),
    ]);
    final table = readTable([page], pack);
    expect(table.rows, hasLength(2));
    final [payment, received] = table.rows;
    expect(payment[StatementColumnKey.date], '2026-10-26 09:15:42');
    expect(
      payment[StatementColumnKey.description],
      'Merchant Payment to 5000001 - EXAMPLE',
    );
    expect(payment[StatementColumnKey.status], 'Completed');
    expect(payment[StatementColumnKey.moneyOut], '-1,500.00');
    expect(payment[StatementColumnKey.balance], '5,500.00');
    expect(received[StatementColumnKey.moneyIn], '2,000.00');
    expect(received[StatementColumnKey.moneyOut], '');

    final read = StatementReader(pack).read([page]);
    expect(read.lines, hasLength(2));
    expect(read.unreadLines, isEmpty);
  });

  test('without a header row nothing is read as a row', () {
    final table = readTable([
      StatementPage([_w('01/10/2026', 20, 80), _w('TEXT', 100, 80)]),
    ], _pack);
    expect(table.headerFound, isFalse);
    expect(table.rows, isEmpty);
    expect(table.outside, ['01/10/2026 TEXT']);
  });
}

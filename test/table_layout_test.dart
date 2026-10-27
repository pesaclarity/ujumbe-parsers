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
      ]),
    ];
    final table = readTable(pages, _pack);
    expect(table.headerFound, isTrue);
    expect(table.outside, ['EXAMPLE BANK']);
    expect(table.rows, hasLength(2));

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

  test('without a header row nothing is read as a row', () {
    final table = readTable([
      StatementPage([_w('01/10/2026', 20, 80), _w('TEXT', 100, 80)]),
    ], _pack);
    expect(table.headerFound, isFalse);
    expect(table.rows, isEmpty);
    expect(table.outside, ['01/10/2026 TEXT']);
  });
}

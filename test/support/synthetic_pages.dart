/// Lays out synthetic M-Pesa statements as positioned words, the way the
/// app's PDF extractor reports a real statement's pages. Every name, number
/// and receipt is made up; never paste a real statement here.
library;

import 'package:ujumbe/ujumbe.dart';

import 'synthetic_statement.dart';

/// Where the M-Pesa columns sit in these synthetic pages.
const mpesaColumns = [
  FixtureColumn(30),
  FixtureColumn(90),
  FixtureColumn(195),
  FixtureColumn(375),
  FixtureColumn(545, rightAligned: true),
  FixtureColumn(615, rightAligned: true),
  FixtureColumn(690, rightAligned: true),
];

const _header = [
  'Receipt No.',
  'Completion Time',
  'Details',
  'Transaction Status',
  'Paid In',
  'Withdrawn',
  'Balance',
];

/// The same statement as [syntheticStatement], as pages of positioned
/// words. Rows wrap their details at [detailsWidth] characters, and pages
/// hold [linesPerPage] table lines, so a row can straddle a page break.
List<StatementPage> syntheticStatementPages(
  List<SyntheticEntry> entries, {
  required int openingBalance,
  String period = '01 Oct 2026 - 31 Oct 2026',
  int linesPerPage = 40,
  int detailsWidth = 34,
  bool newestFirst = true,
  Set<String> omit = const {},
}) {
  var balance = openingBalance;
  final rows = <List<List<String>>>[];
  for (final e in entries) {
    if (e.status == 'Completed') balance += e.paidIn - e.withdrawn;
    if (omit.contains(e.receipt)) continue;
    final chunks = wrapWords(e.details, detailsWidth);
    rows.add([
      [
        e.receipt,
        e.time,
        chunks.first,
        e.status,
        e.paidIn > 0 ? money(e.paidIn) : '',
        e.withdrawn > 0 ? money(-e.withdrawn) : '',
        money(balance),
      ],
      for (final chunk in chunks.skip(1)) ['', '', chunk, '', '', '', ''],
    ]);
  }
  final table = [for (final row in newestFirst ? rows.reversed : rows) ...row];
  final pageCount = table.isEmpty
      ? 1
      : (table.length + linesPerPage - 1) ~/ linesPerPage;
  return [
    for (var p = 0; p < pageCount; p++)
      typesetPage([
        'M-PESA STATEMENT',
        if (p == 0) ...[
          'Customer Name: JANE DOE',
          'Statement Period: $period',
          'SUMMARY',
          'TRANSACTION TYPE PAID IN PAID OUT',
        ],
        _header,
        ...table.skip(p * linesPerPage).take(linesPerPage),
        'Disclaimer: synthetic test statement, not a real record.',
        'Page ${p + 1} of $pageCount',
      ], mpesaColumns),
  ];
}

/// Wraps [text] into lines of at most [width] characters.
List<String> wrapWords(String text, int width) {
  final lines = <String>[];
  var line = '';
  for (final word in text.split(' ')) {
    if (line.isNotEmpty && line.length + 1 + word.length > width) {
      lines.add(line);
      line = word;
    } else {
      line = line.isEmpty ? word : '$line $word';
    }
  }
  lines.add(line);
  return lines;
}

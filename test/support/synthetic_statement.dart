/// Generates synthetic M-Pesa statement text in the shape a PDF text
/// extractor produces, for tests. Every name, number and receipt is made
/// up; never paste a real statement here.
library;

/// One synthetic statement row, in East Africa Time.
class SyntheticEntry {
  /// Creates an entry. Give one of [paidIn] or [withdrawn], in cents.
  const SyntheticEntry(
    this.receipt,
    this.time,
    this.details, {
    this.paidIn = 0,
    this.withdrawn = 0,
    this.status = 'Completed',
  });

  /// Receipt number.
  final String receipt;

  /// `yyyy-MM-dd HH:mm:ss`.
  final String time;

  /// Details column text.
  final String details;

  /// Paid in, cents.
  final int paidIn;

  /// Withdrawn, cents (positive).
  final int withdrawn;

  /// Transaction status.
  final String status;
}

/// Lays out [entries] (oldest first) as statement text.
///
/// Rows are wrapped so details fit [detailsWidth] characters, and pages
/// hold [linesPerPage] table lines, so a wrapped row can straddle a page
/// break. With [amountsOnLastLine], the status and amounts sit on a row's
/// last line instead of its first. Receipts in [omit] are left out after
/// balances are worked out, to simulate rows lost in extraction.
String syntheticStatement(
  List<SyntheticEntry> entries, {
  required int openingBalance,
  String period = '01 Oct 2026 - 31 Oct 2026',
  int linesPerPage = 40,
  int detailsWidth = 34,
  bool amountsOnLastLine = false,
  bool newestFirst = true,
  bool twoAmountColumns = false,
  Set<String> omit = const {},
  List<String> extraTableLines = const [],
}) {
  var balance = openingBalance;
  var paidInTotal = 0, withdrawnTotal = 0;
  final rows = <List<String>>[];
  for (final e in entries) {
    if (e.status == 'Completed') {
      balance += e.paidIn - e.withdrawn;
      paidInTotal += e.paidIn;
      withdrawnTotal += e.withdrawn;
    }
    if (omit.contains(e.receipt)) continue;
    final amounts = twoAmountColumns
        ? '${money(e.paidIn)} ${money(-e.withdrawn)}'
        : (e.paidIn > 0 ? money(e.paidIn) : money(-e.withdrawn));
    final tail = '${e.status.padRight(10)} $amounts ${money(balance)}';
    final chunks = _wrap(e.details, detailsWidth);
    final lead = '${e.receipt} ${e.time} ';
    final indent = ' ' * lead.length;
    rows.add([
      for (var i = 0; i < chunks.length; i++)
        '${i == 0 ? lead : indent}${chunks[i].padRight(detailsWidth)}'
                '${(amountsOnLastLine ? i == chunks.length - 1 : i == 0) ? ' $tail' : ''}'
            .trimRight(),
    ]);
  }

  final tableLines = [
    for (final row in newestFirst ? rows.reversed : rows) ...row,
    ...extraTableLines,
  ];
  final pages = <List<String>>[];
  for (var i = 0; i < tableLines.length; i += linesPerPage) {
    final end = i + linesPerPage;
    pages.add(
      tableLines.sublist(i, end > tableLines.length ? tableLines.length : end),
    );
  }
  if (pages.isEmpty) pages.add([]);

  const columns =
      'Receipt No.  Completion Time      Details                            '
      'Transaction Status  Paid In  Withdrawn  Balance';
  final out = StringBuffer();
  for (var p = 0; p < pages.length; p++) {
    if (p == 0) {
      out
        ..writeln('M-PESA STATEMENT')
        ..writeln('Customer Name:   JANE DOE')
        ..writeln('Mobile Number:   0700 000 000')
        ..writeln('Email Address:   jane.doe@example.com')
        ..writeln('Statement Period:   $period')
        ..writeln('Request Date:   01 Nov 2026')
        ..writeln('SUMMARY')
        ..writeln('TRANSACTION TYPE        PAID IN      PAID OUT')
        ..writeln('TOTAL:   ${money(paidInTotal)}   ${money(withdrawnTotal)}')
        ..writeln('DETAILED STATEMENT');
    } else {
      out.writeln('M-PESA STATEMENT');
    }
    out.writeln(columns);
    pages[p].forEach(out.writeln);
    out
      ..writeln('Disclaimer: synthetic test statement, not a real record.')
      ..writeln('Page ${p + 1} of ${pages.length}');
    if (p < pages.length - 1) out.write('\f');
  }
  return out.toString();
}

/// Formats cents as `1,234.50`, negative with a leading minus.
String money(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  return '$sign$whole.${(abs % 100).toString().padLeft(2, '0')}';
}

List<String> _wrap(String text, int width) {
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

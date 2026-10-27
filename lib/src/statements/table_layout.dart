import 'page_text.dart';
import 'statement_pack.dart';

/// One row of a statement table, with each column's text.
class TableRow {
  /// Creates a row.
  TableRow(this.page, this.cells);

  /// Page number, from 1.
  final int page;

  /// Text of each column, wrapped lines joined by single spaces.
  final Map<StatementColumnKey, String> cells;

  /// The cell for [key], or an empty string.
  String operator [](StatementColumnKey key) => cells[key] ?? '';

  /// Every cell in column order, for hashing and review.
  String textIn(List<StatementColumn> columns) => [
    for (final c in columns) this[c.key],
  ].where((t) => t.isNotEmpty).join(' ');
}

/// The table read from a statement, and the text outside it.
class StatementTable {
  /// Creates a table.
  const StatementTable({
    required this.rows,
    required this.outside,
    required this.headerFound,
  });

  /// Rows in printed order.
  final List<TableRow> rows;

  /// Lines outside the table (titles, period, summary), in page order.
  final List<String> outside;

  /// Whether the pack's header row was found on any page.
  final bool headerFound;
}

/// Rebuilds the statement table on [pages] using [pack]'s columns.
///
/// On each page the header row is the first line where every column's
/// header matches, in order. A left-aligned column starts just left of its
/// header, since its values start where the header does and may run far to
/// the right of it. A right-aligned column (amounts) starts halfway across
/// the gap after the header to its left, since its values end where its
/// header ends and may start to the left of it. A word belongs to the
/// column its centre falls in, except that only numbers go in
/// right-aligned columns: other text there joins the nearest left-aligned
/// column to its left, as a long description does. Pages with
/// no header row reuse the last header's columns. A line starts a new row
/// when its [StatementPack.rowStartsWith] cell has text; other lines
/// continue the row above. Lines matching [StatementPack.skip] and
/// repeated header rows are dropped.
StatementTable readTable(List<StatementPage> pages, StatementPack pack) {
  final rows = <TableRow>[];
  final outside = <String>[];
  List<double>? bounds;
  var headerFound = false;

  for (var p = 0; p < pages.length; p++) {
    final lines = pageLines(pages[p]);
    final header = _findHeader(lines, pack);
    if (header != null) {
      bounds = header.bounds;
      headerFound = true;
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final text = line.map((w) => w.text).join(' ');
      final beforeHeader = header != null && i < header.line;
      if (bounds == null || beforeHeader) {
        outside.add(text);
        continue;
      }
      if (i == header?.line || pack.skip.any((s) => s.hasMatch(text))) {
        continue;
      }
      final cells = _cells(line, bounds, pack.columns);
      if ((cells[pack.rowStartsWith] ?? '').isNotEmpty) {
        rows.add(TableRow(p + 1, cells));
      } else if (rows.isNotEmpty) {
        final row = rows.last;
        cells.forEach((key, value) {
          final current = row.cells[key];
          row.cells[key] = current == null || current.isEmpty
              ? value
              : '$current $value';
        });
      } else {
        outside.add(text);
      }
    }
  }
  return StatementTable(rows: rows, outside: outside, headerFound: headerFound);
}

class _Header {
  const _Header(this.line, this.bounds);

  /// Index of the header line on its page.
  final int line;

  /// Column boundaries: column i spans bounds[i] to bounds[i + 1].
  final List<double> bounds;
}

/// The longest run of words a single header may span.
const _maxHeaderWords = 4;

/// How far left of its header a left-aligned value may start, in points.
const _leftSlack = 2.0;

/// An amount as statements print it: `1,234.50`, `-50.00`, `(50.00)`,
/// `KES 10.00` split over words, or with a `CR` or `DR` suffix; or a sign
/// that a PDF printed apart from its number.
final _number = RegExp(
  r'^(?:[-(]?(?:[A-Z]{3}\.?)?[\d,]*\d(?:\.\d+)?\)?(?:CR|DR)?|[-(])$',
  caseSensitive: false,
);

_Header? _findHeader(List<List<PageWord>> lines, StatementPack pack) {
  for (var i = 0; i < lines.length; i++) {
    final spans = _matchHeaders(lines[i], pack.columns);
    if (spans == null) continue;
    final bounds = <double>[double.negativeInfinity];
    for (var c = 1; c < spans.length; c++) {
      final leftEdge = spans[c - 1].$2;
      final rightStart = spans[c].$1;
      bounds.add(
        pack.columns[c].align == ColumnAlign.right
            ? (leftEdge + rightStart) / 2
            : rightStart - _leftSlack,
      );
    }
    bounds.add(double.infinity);
    return _Header(i, bounds);
  }
  return null;
}

// Matches each column's header to a run of words, left to right. Returns
// each header's left and right edge, or null if any column is missing.
List<(double, double)>? _matchHeaders(
  List<PageWord> line,
  List<StatementColumn> columns,
) {
  final spans = <(double, double)>[];
  var start = 0;
  for (final column in columns) {
    (double, double)? found;
    for (var from = start; from < line.length && found == null; from++) {
      for (var n = 1; n <= _maxHeaderWords && from + n <= line.length; n++) {
        final words = line.sublist(from, from + n);
        if (column.header.hasMatch(words.map((w) => w.text).join(' '))) {
          found = (words.first.left, words.last.right);
          start = from + n;
          break;
        }
      }
    }
    if (found == null) return null;
    spans.add(found);
  }
  return spans;
}

Map<StatementColumnKey, String> _cells(
  List<PageWord> line,
  List<double> bounds,
  List<StatementColumn> columns,
) {
  final parts = <StatementColumnKey, List<String>>{};
  for (final word in line) {
    var c = 0;
    while (c < columns.length - 1 && word.centerX >= bounds[c + 1]) {
      c++;
    }
    // Only numbers go in right-aligned (amount) columns: other text that
    // reaches into one belongs to the text column to its left.
    if (columns[c].align == ColumnAlign.right && !_number.hasMatch(word.text)) {
      var left = c;
      while (left > 0 && columns[left].align == ColumnAlign.right) {
        left--;
      }
      if (columns[left].align == ColumnAlign.left) c = left;
    }
    (parts[columns[c].key] ??= []).add(word.text);
  }
  return {for (final e in parts.entries) e.key: e.value.join(' ')};
}

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
/// header matches, in order. The headers give a first guess at where each
/// column starts: a left-aligned column just left of its header, a
/// right-aligned column (amounts) halfway across the gap after the header
/// to its left. Each guess then moves to the gutter, the widest x range no
/// word of the table body crosses between the two headers' centres, because many statements centre their
/// headers so values start well left of them or end well right of them.
/// A word belongs to the column its centre falls in, except that only
/// numbers go in right-aligned columns: other text there joins the nearest
/// left-aligned column to its left. Pages with no header row reuse the last
/// columns. A line starts a new row when its [StatementPack.rowStartsWith]
/// cell has text (matching that column's pattern, if it has one); other
/// lines continue the row above when they sit within two line heights of
/// it, and are left out otherwise. Lines matching [StatementPack.skip] and
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
      bounds = _snapToGutters(header, _bodyLines(lines, header, pack));
      headerFound = true;
    }
    // The last line taken into the table on this page, to tell
    // continuation lines from text further down such as footers. Lines
    // just under a repeated header continue the previous page's last row.
    var previous = header == null ? null : lines[header.line];
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
      if (_startsRow(cells, pack)) {
        rows.add(TableRow(p + 1, cells));
        previous = line;
      } else if (rows.isNotEmpty &&
          (previous == null || _follows(line, previous))) {
        previous = line;
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

bool _startsRow(Map<StatementColumnKey, String> cells, StatementPack pack) {
  final value = cells[pack.rowStartsWith] ?? '';
  if (value.isEmpty) return false;
  final pattern = pack.column(pack.rowStartsWith)?.pattern;
  return pattern == null || pattern.hasMatch(value);
}

/// Whether [line] sits close enough under [previous] to continue its row:
/// at most two line heights below it. Text further down, such as a page
/// footer, is left out.
bool _follows(List<PageWord> line, List<PageWord> previous) {
  double top(List<PageWord> l) =>
      l.map((w) => w.top).reduce((a, b) => a < b ? a : b);
  double bottom(List<PageWord> l) =>
      l.map((w) => w.bottom).reduce((a, b) => a > b ? a : b);
  final height = bottom(previous) - top(previous);
  return top(line) - bottom(previous) <= 2 * height;
}

class _Header {
  const _Header(this.line, this.bounds, this.spans);

  /// Index of the header line on its page.
  final int line;

  /// Column boundaries guessed from the headers alone: column i spans
  /// bounds[i] to bounds[i + 1].
  final List<double> bounds;

  /// Each header's left and right edge.
  final List<(double, double)> spans;
}

/// The page's table body: lines after the header, without skipped ones,
/// up to the last line that starts a row, so footers are left out.
List<List<PageWord>> _bodyLines(
  List<List<PageWord>> lines,
  _Header header,
  StatementPack pack,
) {
  final body = <List<PageWord>>[];
  var lastRowStart = -1;
  for (var i = header.line + 1; i < lines.length; i++) {
    final text = lines[i].map((w) => w.text).join(' ');
    if (pack.skip.any((s) => s.hasMatch(text))) continue;
    body.add(lines[i]);
    final cells = _cells(lines[i], header.bounds, pack.columns);
    if (_startsRow(cells, pack)) lastRowStart = body.length - 1;
  }
  return body.sublist(0, lastRowStart + 1);
}

/// Narrowest gutter that counts as a gap between columns, in points.
const _minGutter = 1.0;

/// Moves each boundary to the gutter: the widest x range that no word of
/// the table body crosses, between the centres of the two headers on
/// either side. Many statements centre headers over their columns, so the
/// values start well left of their header or end well right of it; the
/// gutters show where the columns really are. A boundary with no gutter
/// near it keeps its header-based place.
List<double> _snapToGutters(_Header header, List<List<PageWord>> body) {
  final spans = [
    for (final line in body)
      for (final word in line) (word.left, word.right),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final covered = <(double, double)>[];
  for (final (left, right) in spans) {
    final last = covered.lastOrNull;
    if (last != null && left <= last.$2) {
      if (right > last.$2) covered[covered.length - 1] = (last.$1, right);
    } else {
      covered.add((left, right));
    }
  }

  final bounds = [...header.bounds];
  for (var c = 1; c < bounds.length - 1; c++) {
    // A header's centre is inside its column however it is aligned, so the
    // boundary lies between the two centres.
    final from = (header.spans[c - 1].$1 + header.spans[c - 1].$2) / 2;
    final to = (header.spans[c].$1 + header.spans[c].$2) / 2;
    final guess = bounds[c];
    double? best;
    var bestWidth = 0.0, bestDistance = double.infinity;
    for (var i = 0; i + 1 < covered.length; i++) {
      final gapStart = covered[i].$2 > from ? covered[i].$2 : from;
      final gapEnd = covered[i + 1].$1 < to ? covered[i + 1].$1 : to;
      final width = gapEnd - gapStart;
      if (width < _minGutter) continue;
      final distance = guess < gapStart
          ? gapStart - guess
          : guess > gapEnd
          ? guess - gapEnd
          : 0.0;
      // The widest gap is the gutter; spaces between words inside a column
      // are narrower. Equal widths go to the one nearer the guess.
      if (width > bestWidth || width == bestWidth && distance < bestDistance) {
        bestWidth = width;
        bestDistance = distance;
        best = (gapStart + gapEnd) / 2;
      }
    }
    if (best != null && best > bounds[c - 1]) bounds[c] = best;
  }
  return bounds;
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
    return _Header(i, bounds, spans);
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

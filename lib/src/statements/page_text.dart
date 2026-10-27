/// Text from a statement PDF with each word's position, as a PDF engine
/// reports it. The app extracts this on the phone; the engine only reads it.
library;

/// One word on a page, with its box in PDF points from the page's top-left
/// corner (y grows downwards).
class PageWord {
  /// Creates a word.
  const PageWord(this.text, this.left, this.top, this.right, this.bottom);

  /// The word, with no spaces inside.
  final String text;

  /// Box edges, in points.
  final double left, top, right, bottom;

  /// Horizontal centre.
  double get centerX => (left + right) / 2;

  /// Vertical centre.
  double get centerY => (top + bottom) / 2;

  /// Box height.
  double get height => bottom - top;

  @override
  String toString() => 'PageWord("$text", $left, $top, $right, $bottom)';
}

/// The words on one page, in any order.
class StatementPage {
  /// Creates a page.
  const StatementPage(this.words);

  /// Every word on the page.
  final List<PageWord> words;

  /// The page as plain text: lines top to bottom, words left to right.
  String get text => [
    for (final line in pageLines(this)) line.map((w) => w.text).join(' '),
  ].join('\n');
}

/// Groups [page]'s words into lines, top to bottom, each left to right.
///
/// Words whose vertical centres lie within half a word height of a line's
/// first word join that line, so words printed slightly higher or lower
/// (different fonts, superscripts) stay on it.
List<List<PageWord>> pageLines(StatementPage page) {
  final words = [...page.words.where((w) => w.text.trim().isNotEmpty)]
    ..sort((a, b) {
      final byY = a.centerY.compareTo(b.centerY);
      return byY != 0 ? byY : a.left.compareTo(b.left);
    });
  final lines = <List<PageWord>>[];
  for (final word in words) {
    final line = lines.lastOrNull;
    final anchor = line?.first;
    final tolerance = anchor == null
        ? 0
        : (anchor.height > word.height ? anchor.height : word.height) / 2;
    if (anchor != null && (word.centerY - anchor.centerY).abs() <= tolerance) {
      line!.add(word);
    } else {
      lines.add([word]);
    }
  }
  for (final line in lines) {
    line.sort((a, b) => a.left.compareTo(b.left));
  }
  return lines;
}

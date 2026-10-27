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
/// A word joins the line whose vertical span overlaps at least half of the
/// word's own height, or half the line's when the line is shorter; the
/// line's span then grows to cover the word. So punctuation, hyphens and
/// asterisks, whose boxes are much smaller than letters', stay on their
/// line, as do words printed slightly higher or lower.
List<List<PageWord>> pageLines(StatementPage page) {
  final words = [...page.words.where((w) => w.text.trim().isNotEmpty)]
    ..sort((a, b) {
      final byY = a.centerY.compareTo(b.centerY);
      return byY != 0 ? byY : a.left.compareTo(b.left);
    });
  final lines = <_Line>[];
  for (final word in words) {
    final line = lines.lastOrNull;
    if (line != null && line.takes(word)) {
      line.add(word);
    } else {
      lines.add(_Line(word));
    }
  }
  return [
    for (final line in lines)
      line.words..sort((a, b) => a.left.compareTo(b.left)),
  ];
}

class _Line {
  _Line(PageWord first) : top = first.top, bottom = first.bottom {
    words.add(first);
  }

  final words = <PageWord>[];
  double top, bottom;

  bool takes(PageWord word) {
    final overlap =
        (word.bottom < bottom ? word.bottom : bottom) -
        (word.top > top ? word.top : top);
    final lineHeight = bottom - top;
    final shorter = word.height < lineHeight ? word.height : lineHeight;
    return overlap > 0 && overlap >= shorter / 2;
  }

  void add(PageWord word) {
    words.add(word);
    if (word.top < top) top = word.top;
    if (word.bottom > bottom) bottom = word.bottom;
  }
}

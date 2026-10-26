/// A small date-time pattern for the `time` text captured from a message.
///
/// Supported tokens: `d` `dd` (day), `M` `MM` `MMM` (month; `MMM` is an
/// English three-letter name), `yy` `yyyy` (year; `yy` means 2000 + yy),
/// `H` `HH` (24-hour), `h` `hh` (12-hour), `mm` (minute), `ss` (second),
/// `a` (AM or PM). Text inside single quotes is matched literally, and any
/// run of spaces matches one or more whitespace characters.
///
/// Packs name a pattern rather than relying on a locale library because
/// SMS formats are fixed by each institution and must parse identically on
/// every phone, whatever its locale.
class MessageTimeFormat {
  /// Compiles [pattern]. Throws [FormatException] if it is not supported.
  factory MessageTimeFormat(String pattern) {
    final tokens = <String>[];
    final buffer = StringBuffer('^');
    var i = 0;
    while (i < pattern.length) {
      final char = pattern[i];
      if (char == "'") {
        final end = pattern.indexOf("'", i + 1);
        if (end < 0) {
          throw FormatException('Unclosed quote in time format', pattern, i);
        }
        buffer.write(RegExp.escape(pattern.substring(i + 1, end)));
        i = end + 1;
      } else if (char == ' ') {
        while (i < pattern.length && pattern[i] == ' ') {
          i++;
        }
        buffer.write(r'\s+');
      } else if (_letters.hasMatch(char)) {
        var end = i;
        while (end < pattern.length && pattern[end] == char) {
          end++;
        }
        final token = pattern.substring(i, end);
        final regex = _tokens[token];
        if (regex == null) {
          throw FormatException('Unsupported time token "$token"', pattern, i);
        }
        tokens.add(token);
        buffer.write('($regex)');
        i = end;
      } else {
        buffer.write(RegExp.escape(char));
        i++;
      }
    }
    buffer.write(r'$');
    _checkComplete(tokens, pattern);
    return MessageTimeFormat._(
      pattern,
      RegExp(buffer.toString(), caseSensitive: false),
      tokens,
    );
  }

  MessageTimeFormat._(this.pattern, this._regex, this._fields);

  /// The pattern this format was compiled from.
  final String pattern;
  final RegExp _regex;
  final List<String> _fields;

  /// Parses [text] as wall-clock time at [utcOffset] and returns it in UTC.
  ///
  /// Returns `null` when [text] does not fit the pattern or names an
  /// impossible date such as 31 February.
  DateTime? parse(String text, {required Duration utcOffset}) {
    final match = _regex.firstMatch(text.trim());
    if (match == null) return null;
    int? day, month, year, hour, minute;
    var second = 0;
    bool? pm;
    for (var g = 0; g < _fields.length; g++) {
      final value = match.group(g + 1)!;
      switch (_fields[g]) {
        case 'd' || 'dd':
          day = int.parse(value);
        case 'M' || 'MM':
          month = int.parse(value);
        case 'MMM':
          month = _months.indexOf(value.toLowerCase()) + 1;
        case 'yy':
          year = 2000 + int.parse(value);
        case 'yyyy':
          year = int.parse(value);
        case 'H' || 'HH' || 'h' || 'hh':
          hour = int.parse(value);
        case 'mm':
          minute = int.parse(value);
        case 'ss':
          second = int.parse(value);
        case 'a':
          pm = value.toLowerCase() == 'pm';
      }
    }
    if (pm != null) {
      if (hour! < 1 || hour > 12) return null;
      hour = hour % 12 + (pm ? 12 : 0);
    }
    if (month! < 1 || month > 12 || hour! > 23 || minute! > 59 || second > 59) {
      return null;
    }
    final local = DateTime.utc(year!, month, day!, hour, minute, second);
    if (local.day != day || local.month != month) return null;
    return local.subtract(utcOffset);
  }

  static void _checkComplete(List<String> tokens, String pattern) {
    bool has(Set<String> any) => tokens.any(any.contains);
    final twelveHour = has({'h', 'hh'});
    final ok =
        has({'d', 'dd'}) &&
        has({'M', 'MM', 'MMM'}) &&
        has({'yy', 'yyyy'}) &&
        has({'H', 'HH', 'h', 'hh'}) &&
        has({'mm'}) &&
        twelveHour == has({'a'}) &&
        tokens.toSet().length == tokens.length;
    if (!ok) {
      throw FormatException(
        'Time format needs exactly one day, month, year, hour and minute '
        'field, and "a" if and only if the hour is 12-hour',
        pattern,
      );
    }
  }

  static final _letters = RegExp('[A-Za-z]');

  static const _tokens = {
    'd': r'\d{1,2}',
    'dd': r'\d{2}',
    'M': r'\d{1,2}',
    'MM': r'\d{2}',
    'MMM': '[A-Za-z]{3}',
    'yy': r'\d{2}',
    'yyyy': r'\d{4}',
    'H': r'\d{1,2}',
    'HH': r'\d{2}',
    'h': r'\d{1,2}',
    'hh': r'\d{2}',
    'mm': r'\d{2}',
    'ss': r'\d{2}',
    'a': '[AaPp][Mm]',
  };

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
}

/// Parses a UTC offset such as `+03:00` or `-05:30`.
///
/// Returns `null` if [text] is not in that form.
Duration? parseUtcOffset(String text) {
  final match = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final hours = int.parse(match.group(2)!);
  final minutes = int.parse(match.group(3)!);
  if (hours > 14 || minutes > 59) return null;
  final offset = Duration(hours: hours, minutes: minutes);
  return match.group(1) == '-' ? -offset : offset;
}

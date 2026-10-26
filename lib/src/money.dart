/// Parses a money string such as `1,234.50` or `Ksh 1,234.5` into integer
/// minor units (cents), so amounts never pass through floating point.
///
/// Accepts digits with optional thousands separators (`,`) and at most
/// [fractionDigits] decimal places. Returns `null` for anything else.
int? parseMinorUnits(String input, {int fractionDigits = 2}) {
  final match = _amount.firstMatch(input.trim());
  if (match == null) return null;
  final whole = match.group(1)!.replaceAll(',', '');
  final fraction = match.group(2) ?? '';
  if (fraction.length > fractionDigits) return null;
  if (!_groupedThousands.hasMatch(match.group(1)!)) return null;

  var scale = 1;
  for (var i = 0; i < fractionDigits; i++) {
    scale *= 10;
  }
  final padded = fraction.padRight(fractionDigits, '0');
  return int.parse(whole) * scale + (padded.isEmpty ? 0 : int.parse(padded));
}

final _amount = RegExp(r'^(?:[A-Za-z]{3}\.?\s*)?([\d,]+)(?:\.(\d+))?$');

// Either plain digits, or digits grouped in threes by commas.
final _groupedThousands = RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)$');

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

void main() {
  group('parseMinorUnits', () {
    test('reads grouped amounts into cents', () {
      expect(parseMinorUnits('1,234.50'), 123450);
      expect(parseMinorUnits('498,500.00'), 49850000);
      expect(parseMinorUnits('0.00'), 0);
    });

    test('pads short fractions and accepts whole amounts', () {
      expect(parseMinorUnits('12.5'), 1250);
      expect(parseMinorUnits('300'), 30000);
    });

    test('ignores a currency prefix', () {
      expect(parseMinorUnits('Ksh 150.00'), 15000);
      expect(parseMinorUnits('KES1,000.00'), 100000);
    });

    test('is exact where doubles are not', () {
      expect(parseMinorUnits('0.10')! + parseMinorUnits('0.20')!, 30);
      expect(parseMinorUnits('9,007,199,254,740.99'), 900719925474099);
    });

    test('rejects malformed input', () {
      for (final bad in ['', 'abc', '1.234', '1,23.00', '12,3456', '-5.00']) {
        expect(parseMinorUnits(bad), isNull, reason: bad);
      }
    });
  });
}

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

void main() {
  const eat = Duration(hours: 3);

  group('MessageTimeFormat', () {
    test('reads M-Pesa style 12-hour times and converts to UTC', () {
      final f = MessageTimeFormat("d/M/yy 'at' h:mm a");
      expect(
        f.parse('26/10/26 at 9:15 AM', utcOffset: eat),
        DateTime.utc(2026, 10, 26, 6, 15),
      );
      expect(
        f.parse('1/1/27 at 12:05 AM', utcOffset: eat),
        DateTime.utc(2026, 12, 31, 21, 5),
      );
      expect(
        f.parse('1/1/27 at 12:05 PM', utcOffset: eat),
        DateTime.utc(2027, 1, 1, 9, 5),
      );
    });

    test('reads month names and 24-hour times', () {
      final f = MessageTimeFormat('dd-MMM-yyyy HH:mm');
      expect(
        f.parse('26-oct-2026 14:05', utcOffset: eat),
        DateTime.utc(2026, 10, 26, 11, 5),
      );
    });

    test('rejects impossible dates and text that does not fit', () {
      final f = MessageTimeFormat('dd/MM/yyyy HH:mm');
      expect(f.parse('31/02/2026 10:00', utcOffset: eat), isNull);
      expect(f.parse('26/10/2026 24:00', utcOffset: eat), isNull);
      expect(f.parse('26-10-2026 10:00', utcOffset: eat), isNull);
    });

    test('rejects incomplete or unsupported patterns', () {
      for (final bad in ['dd/MM HH:mm', 'dd/MM/yyyy h:mm', 'dd/MM/yyyy zz']) {
        expect(() => MessageTimeFormat(bad), throwsFormatException);
      }
    });
  });

  test('parseUtcOffset', () {
    expect(parseUtcOffset('+03:00'), eat);
    expect(parseUtcOffset('-05:30'), const Duration(hours: -5, minutes: -30));
    expect(parseUtcOffset('3'), isNull);
  });

  group('date-only formats', () {
    test('parse to midnight', () {
      expect(
        MessageTimeFormat(
          'd MMM yyyy',
          dateOnly: true,
        ).parse('1 Oct 2026', utcOffset: Duration.zero),
        DateTime.utc(2026, 10),
      );
    });

    test('must not hold a time, and need a full date', () {
      for (final pattern in ['d MMM yyyy HH:mm', 'MMM yyyy', 'dd dd MM yyyy']) {
        expect(
          () => MessageTimeFormat(pattern, dateOnly: true),
          throwsFormatException,
          reason: pattern,
        );
      }
    });

    test('are refused where a time is needed', () {
      expect(() => MessageTimeFormat('d MMM yyyy'), throwsFormatException);
    });
  });
}

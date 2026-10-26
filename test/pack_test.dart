import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import 'helpers.dart';

void main() {
  test('loads a valid pack', () {
    final pack = ParserPack.fromYaml(testPackYaml);
    expect(pack.id, 'example_wallet');
    expect(pack.version, '1.0.0');
    expect(pack.minEngineVersion, firstEngineVersion);
    expect(pack.utcOffset, const Duration(hours: 3));
    expect(pack.senders, ['EXWALLET']);
    expect(pack.rules.map((r) => r.id), ['sent', 'alert']);
    expect(pack.rules.first.timeFormat, isNotNull);
    expect(pack.rules.last.directionValues, {
      'debited': Direction.outgoing,
      'credited': Direction.incoming,
    });
  });

  List<String> problemsFor(String yaml) {
    try {
      ParserPack.fromYaml(yaml);
    } on PackFormatException catch (e) {
      return e.problems;
    }
    fail('expected PackFormatException');
  }

  String mutate(String from, String to) {
    if (!testPackYaml.contains(from)) throw StateError('No "$from" in pack');
    return testPackYaml.replaceFirst(from, to);
  }

  test('reports every problem, not just the first', () {
    final problems = problemsFor(
      mutate('version: 1.0.0', 'version: one').replaceFirst('KES', 'shillings'),
    );
    expect(problems, hasLength(2));
  });

  final cases = {
    'unsupported schema': mutate('schema: 1', 'schema: 2'),
    'bad id': mutate('id: example_wallet', 'id: Example-Wallet'),
    'bad offset': mutate('"+03:00"', '"EAT"'),
    'no senders': mutate('[EXWALLET]', '[]'),
    'unknown field': mutate('schema: 1', 'schema: 1\nextra: true'),
    'unknown type': mutate('type: sent', 'type: gift'),
    'duplicate rule id': mutate('id: alert', 'id: sent'),
    'unknown group': mutate('(?<fee>', '(?<tip>'),
    'missing amount group': mutate(
      r'Ksh(?<amount>[\d,]+\.\d{2}) (?<dir',
      'x (?<dir',
    ),
    'regex does not compile': mutate(r'(?<direction>\w+)', r'(?<direction>\w+'),
    'time without format': mutate('time_format: "dd/MM/yyyy HH:mm"\n', ''),
    'direction both fixed and captured': mutate(
      'direction_values:',
      'direction: in\n    direction_values:',
    ),
    'captured direction without values': mutate(
      '    direction_values: {debited: out, credited: in}\n',
      '',
    ),
    'not yaml': ':\n  - [',
    'needs a newer engine': mutate(
      'currency:',
      'min_engine: 99.0.0\ncurrency:',
    ),
    'malformed min_engine': mutate('currency:', 'min_engine: soon\ncurrency:'),
  };
  for (final entry in cases.entries) {
    test('rejects ${entry.key}', () {
      expect(problemsFor(entry.value), isNotEmpty);
    });
  }

  test('reads min_engine', () {
    final pack = ParserPack.fromYaml(
      mutate('currency:', 'min_engine: $engineVersion\ncurrency:'),
    );
    expect(pack.minEngineVersion, engineVersion);
  });
}

import 'package:yaml/yaml.dart';

import '../fixtures.dart';
import '../pack.dart';
import '../parser.dart';
import 'page_text.dart';
import 'statement_pack.dart';
import 'statement_reader.dart';

/// Where a fixture column's cells sit: from [x] for left-aligned cells, or
/// ending at [x] for right-aligned ones.
class FixtureColumn {
  /// Creates a column.
  const FixtureColumn(this.x, {this.rightAligned = false});

  /// Parses `40` (left edge) or `">540"` (right edge).
  factory FixtureColumn.parse(Object? value) {
    if (value is num) return FixtureColumn(value.toDouble());
    if (value is String && value.startsWith('>')) {
      final x = double.tryParse(value.substring(1));
      if (x != null) return FixtureColumn(x, rightAligned: true);
    }
    throw FormatException('A column is a number, or ">" and a number', value);
  }

  /// Left edge, or right edge when [rightAligned].
  final double x;

  /// Whether cells end at [x].
  final bool rightAligned;
}

/// Lays out synthetic lines as a PDF engine would report them, for
/// fixtures and tests. Each line is a string (free text at the first
/// column) or a list of cells, one per column (empty for none). Characters
/// are [charWidth] points wide and lines [lineHeight] points apart.
StatementPage typesetPage(
  List<Object> lines,
  List<FixtureColumn> columns, {
  double charWidth = 5,
  double lineHeight = 12,
  double top = 40,
}) {
  final words = <PageWord>[];
  void place(String text, FixtureColumn column, double y) {
    final parts = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return;
    final width = (parts.join(' ').length) * charWidth;
    var x = column.rightAligned ? column.x - width : column.x;
    for (final part in parts) {
      final w = part.length * charWidth;
      words.add(PageWord(part, x, y, x + w, y + lineHeight * 0.75));
      x += w + charWidth;
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final y = top + i * lineHeight;
    final line = lines[i];
    if (line is String) {
      place(line, columns.first, y);
    } else if (line is List) {
      for (var c = 0; c < line.length && c < columns.length; c++) {
        place('${line[c]}', columns[c], y);
      }
    } else {
      throw ArgumentError.value(line, 'lines', 'must be strings or lists');
    }
  }
  return StatementPage(words);
}

/// Synthetic statements for a statement pack, with what reading them must
/// produce.
class StatementFixtures {
  /// Creates fixtures.
  const StatementFixtures({required this.packId, required this.statements});

  /// Parses fixtures from YAML. Throws [PackFormatException] on problems.
  factory StatementFixtures.fromYaml(
    String yaml, {
    String source = 'statement fixtures',
  }) {
    final problems = <String>[];
    final Object? doc;
    try {
      doc = loadYaml(yaml);
    } on YamlException catch (e) {
      throw PackFormatException(source, ['Invalid YAML: ${e.message}']);
    }
    if (doc is! YamlMap) {
      throw PackFormatException(source, ['Top level must be a mapping']);
    }
    final packId = doc['pack'];
    if (packId is! String) problems.add('pack: is required');
    final nodes = doc['statements'];
    final statements = <StatementFixture>[];
    if (nodes is! YamlList || nodes.isEmpty) {
      problems.add('statements: a non-empty list is required');
    } else {
      for (var i = 0; i < nodes.length; i++) {
        final s = StatementFixture._read(nodes[i], 'statements[$i]', problems);
        if (s != null) statements.add(s);
      }
    }
    if (problems.isNotEmpty) throw PackFormatException(source, problems);
    return StatementFixtures(packId: packId as String, statements: statements);
  }

  /// The statement pack these fixtures test.
  final String packId;

  /// The fixtures.
  final List<StatementFixture> statements;

  /// Reads every fixture with [pack] and reports what differs. Every rule
  /// must produce at least one expected transaction.
  FixtureReport run(StatementPack pack) {
    final failures = <String>[];
    if (pack.id != packId) {
      failures.add('fixtures are for "$packId", not "${pack.id}"');
    }
    final covered = <String>{};
    final reader = StatementReader(pack);
    for (final fixture in statements) {
      if (!pack.matches(fixture.pages.first.text)) {
        failures.add('${fixture.name}: detect does not match the first page');
      }
      final read = reader.read(fixture.pages);
      for (final t in read.transactions) {
        covered.add(t.ruleId.replaceFirst('statement_', ''));
      }
      for (final problem in fixture.check(read)) {
        failures.add('${fixture.name}: $problem');
      }
    }
    for (final rule in pack.rules) {
      if (!covered.contains(rule.id)) {
        failures.add('rule "${rule.id}" has no passing statement');
      }
    }
    return FixtureReport(
      packId: pack.id,
      sampleCount: statements.length,
      failures: failures,
    );
  }
}

/// One synthetic statement and its expected result.
class StatementFixture {
  /// Creates a fixture.
  const StatementFixture({
    required this.name,
    required this.pages,
    required this.expected,
  });

  /// Shown in reports.
  final String name;

  /// The typeset pages.
  final List<StatementPage> pages;

  /// Expected fields, as written in the fixture file.
  final Map<String, Object?> expected;

  static const _fields = {
    'period',
    'opening_balance_minor',
    'closing_balance_minor',
    'reconciles',
    'unread_lines',
    'transactions',
  };

  /// Every way [statement] differs from [expected].
  List<String> check(ParsedStatement statement) {
    final problems = <String>[];
    void same(String field, Object? actual) {
      if (!expected.containsKey(field)) return;
      final want = expected[field];
      if ('$want' != '$actual') {
        problems.add('$field: expected $want, got $actual');
      }
    }

    final period = expected['period'];
    if (period is List) {
      String? day(DateTime? d) => d?.toIso8601String().substring(0, 10);
      final actual = [day(statement.periodStart), day(statement.periodEnd)];
      if ('${period.toList()}' != '$actual') {
        problems.add('period: expected $period, got $actual');
      }
    }
    same('opening_balance_minor', statement.openingBalanceMinor);
    same('closing_balance_minor', statement.closingBalanceMinor);
    same('reconciles', statement.reconciles);
    same('unread_lines', statement.unreadLines.length);

    final want = expected['transactions'];
    if (want is List) {
      final got = statement.transactions;
      if (want.length != got.length) {
        problems.add(
          'transactions: expected ${want.length}, got ${got.length}',
        );
      }
      for (var i = 0; i < want.length && i < got.length; i++) {
        final sample = FixtureSample(
          name: 'transactions[$i]',
          message: _placeholder,
          expected: {
            for (final e in (want[i] as Map).entries) '${e.key}': e.value,
          },
        );
        for (final p in sample.check(got[i])) {
          problems.add('transactions[$i] ${p.replaceFirst(': ', ' ')}');
        }
      }
    }
    return problems;
  }

  static final _placeholder = SmsMessage(
    sender: 'statement',
    body: '',
    receivedAt: DateTime.utc(2026),
  );

  static StatementFixture? _read(
    Object? node,
    String at,
    List<String> problems,
  ) {
    if (node is! YamlMap) {
      problems.add('$at: must be a mapping');
      return null;
    }
    final start = problems.length;
    final name = node['name'];
    if (name is! String) problems.add('$at.name: is required');
    final columnNodes = node['columns'];
    final columns = <FixtureColumn>[];
    if (columnNodes is! YamlList || columnNodes.isEmpty) {
      problems.add('$at.columns: a non-empty list is required');
    } else {
      for (final c in columnNodes) {
        try {
          columns.add(FixtureColumn.parse(c));
        } on FormatException catch (e) {
          problems.add('$at.columns: ${e.message}');
        }
      }
    }
    final pageNodes = node['pages'];
    final pages = <StatementPage>[];
    if (pageNodes is! YamlList || pageNodes.isEmpty) {
      problems.add('$at.pages: a non-empty list is required');
    } else if (columns.isNotEmpty) {
      for (var p = 0; p < pageNodes.length; p++) {
        final lines = pageNodes[p];
        if (lines is! YamlList) {
          problems.add('$at.pages[$p]: must be a list of lines');
          continue;
        }
        final plain = <Object>[
          for (final l in lines)
            l is YamlList ? l.map((c) => '${c ?? ''}').toList() : '$l',
        ];
        pages.add(typesetPage(plain, columns));
      }
    }
    final expect = node['expect'];
    Map<String, Object?> expected = const {};
    if (expect is! YamlMap) {
      problems.add('$at.expect: is required');
    } else {
      expected = {for (final e in expect.entries) '${e.key}': e.value};
      for (final key in expected.keys) {
        if (!_fields.contains(key)) {
          problems.add('$at.expect.$key: unknown field');
        }
      }
    }
    if (problems.length > start) return null;
    return StatementFixture(
      name: name! as String,
      pages: pages,
      expected: expected,
    );
  }
}

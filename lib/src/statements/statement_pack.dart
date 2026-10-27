import 'package:yaml/yaml.dart';

import '../pack.dart';
import '../time_format.dart';
import '../version.dart';
import '../yaml_reader.dart';

/// The statement pack format version this engine reads.
const supportedStatementPackSchema = 1;

/// What a statement table column holds.
enum StatementColumnKey {
  /// The institution's reference, such as an M-Pesa receipt number.
  reference('reference'),

  /// The transaction date, or date and time.
  date('date'),

  /// The time, when the statement prints it in its own column.
  time('time'),

  /// The description or details.
  description('description'),

  /// The transaction status, such as `Completed`.
  status('status'),

  /// Money into the account.
  moneyIn('money_in'),

  /// Money out of the account.
  moneyOut('money_out'),

  /// One amount column for both directions; see [StatementPack.amount].
  amount('amount'),

  /// A debit or credit marker beside [amount], such as `DR` or `CR`.
  marker('marker'),

  /// The balance after the row.
  balance('balance');

  const StatementColumnKey(this.code);

  /// The value used in pack files.
  final String code;

  /// Looks up a key by its [code], or returns `null`.
  static StatementColumnKey? fromCode(String code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Which side of its header a column's values line up on.
enum ColumnAlign {
  /// Values start where the header starts (text, dates).
  left,

  /// Values end where the header ends (amounts), so they may start to the
  /// left of the header.
  right,
}

/// One column of the statement table.
class StatementColumn {
  /// Creates a column. Prefer [StatementPack.fromYaml], which validates.
  const StatementColumn({
    required this.key,
    required this.header,
    this.format,
    this.negative = false,
    this.align = ColumnAlign.left,
  });

  /// What the column holds.
  final StatementColumnKey key;

  /// Matches the column's header text, all words joined by single spaces.
  final RegExp header;

  /// The [MessageTimeFormat] pattern of a [StatementColumnKey.date] or
  /// [StatementColumnKey.time] column. A date column's may include the
  /// time; a time column's is joined to the date column's.
  final String? format;

  /// Whether amounts in this column are printed with a minus sign that
  /// carries no meaning (M-Pesa prints withdrawals as negative).
  final bool negative;

  /// See [ColumnAlign].
  final ColumnAlign align;
}

/// How a single [StatementColumnKey.amount] column shows direction.
class AmountStyle {
  /// Creates a style. Set [negativeIsOut], or both marker patterns.
  const AmountStyle({this.negativeIsOut, this.markerOut, this.markerIn});

  /// For a signed amount: true when a negative amount is money out.
  final bool? negativeIsOut;

  /// For a marker column: matches markers meaning money out (`DR`).
  final RegExp? markerOut;

  /// For a marker column: matches markers meaning money in (`CR`).
  final RegExp? markerIn;
}

/// The order rows are printed in.
enum RowOrder {
  /// Newest at the top, as M-Pesa prints them.
  newestFirst('newest_first'),

  /// Oldest at the top, as most banks print them.
  oldestFirst('oldest_first'),

  /// Worked out from the first and last row's dates.
  detect('detect');

  const RowOrder(this.code);

  /// The value used in pack files.
  final String code;
}

/// Description rule: the first rule matching a row's description sets its
/// type, counterparty and account.
class StatementRule {
  /// Creates a rule. Prefer [StatementPack.fromYaml], which validates.
  const StatementRule({
    required this.id,
    required this.type,
    required this.pattern,
  });

  /// Unique within its pack, e.g. `paybill`.
  final String id;

  /// The kind of transaction.
  final TransactionType type;

  /// Matches the description, with optional `counterparty` and `account`
  /// named groups.
  final RegExp pattern;
}

/// Charge rows printed separately from the payment they belong to, which
/// are folded into it as its fee, as the SMS for the payment states it.
class FeeRows {
  /// Creates a fee rule.
  const FeeRows(this.description);

  /// Matches the description of a charge row.
  final RegExp description;
}

/// A validated statement pack: how to read one statement layout.
class StatementPack {
  /// Creates a pack. Prefer [StatementPack.fromYaml], which validates.
  StatementPack({
    required this.id,
    required this.institution,
    required this.name,
    required this.version,
    required this.currency,
    required this.utcOffset,
    required this.detect,
    required this.columns,
    required this.timeFormat,
    required this.rowStartsWith,
    required this.rules,
    this.minEngineVersion = firstEngineVersion,
    this.period,
    this.periodFormat,
    this.order = RowOrder.detect,
    this.completedStatus,
    this.skip = const [],
    this.fees,
    this.amount,
    this.passwordHint,
  });

  /// Parses and validates a pack from its YAML text.
  ///
  /// Throws [PackFormatException] listing every problem found.
  factory StatementPack.fromYaml(String yaml, {String source = 'pack'}) {
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
    final r = YamlFieldReader(doc, problems);
    r.checkKeys(const {
      'schema',
      'id',
      'institution',
      'name',
      'version',
      'min_engine',
      'currency',
      'utc_offset',
      'detect',
      'period',
      'period_format',
      'columns',
      'row_starts_with',
      'order',
      'completed_status',
      'skip',
      'fees',
      'amount',
      'rules',
      'password_hint',
    });

    final schema = r.integer('schema');
    if (schema != null && schema != supportedStatementPackSchema) {
      problems.add(
        'schema: $schema is not supported '
        '(this engine reads $supportedStatementPackSchema)',
      );
    }
    final id = r.string('id', pattern: _idPattern);
    final institution = r.string('institution', pattern: _idPattern);
    final name = r.string('name');
    final version = r.string('version', pattern: _semver);
    final minEngine =
        r.string('min_engine', pattern: _semver, optional: true) ??
        firstEngineVersion;
    if (_semver.hasMatch(minEngine) &&
        compareVersions(minEngine, engineVersion) > 0) {
      problems.add(
        'min_engine: needs engine $minEngine, this engine is $engineVersion',
      );
    }
    final currency = r.string('currency', pattern: RegExp(r'^[A-Z]{3}$'));
    final offsetText = r.string('utc_offset');
    final utcOffset = offsetText == null ? null : parseUtcOffset(offsetText);
    if (offsetText != null && utcOffset == null) {
      problems.add('utc_offset: "$offsetText" must look like +03:00');
    }

    final detect = _regexList(doc, 'detect', problems, multiLine: true);
    if (detect != null && detect.isEmpty) {
      problems.add('detect: at least one pattern is required');
    }
    final period = _regex(doc, 'period', problems, optional: true);
    if (period != null &&
        !_groups(period.pattern).containsAll(const {'start', 'end'})) {
      problems.add('period: must capture "start" and "end" groups');
    }
    final periodFormat = r.timeFormat(
      'period_format',
      optional: period == null,
      dateOnly: true,
    );

    final columns = _readColumns(doc['columns'], problems);
    final keys = {for (final c in columns) c.key};
    final rowStartText = r.string('row_starts_with');
    final rowStart = rowStartText == null
        ? null
        : StatementColumnKey.fromCode(rowStartText);
    if (rowStartText != null && !keys.contains(rowStart)) {
      problems.add('row_starts_with: "$rowStartText" is not one of columns');
    }
    for (final required in const [
      StatementColumnKey.date,
      StatementColumnKey.description,
    ]) {
      if (columns.isNotEmpty && !keys.contains(required)) {
        problems.add('columns: a "${required.code}" column is required');
      }
    }
    final split =
        keys.contains(StatementColumnKey.moneyIn) &&
        keys.contains(StatementColumnKey.moneyOut);
    final single = keys.contains(StatementColumnKey.amount);
    if (columns.isNotEmpty && split == single) {
      problems.add(
        'columns: use "money_in" and "money_out", or one "amount" column',
      );
    }
    if (keys.contains(StatementColumnKey.marker) && !single) {
      problems.add('columns: a "marker" column needs an "amount" column');
    }

    final timeFormat = _rowTimeFormat(columns, problems);

    final orderText = r.string('order', optional: true);
    final order = orderText == null
        ? RowOrder.detect
        : RowOrder.values.where((o) => o.code == orderText).firstOrNull;
    if (orderText != null && order == null) {
      problems.add('order: must be newest_first, oldest_first or detect');
    }
    final completed = _regex(doc, 'completed_status', problems, optional: true);
    final skip = _regexList(doc, 'skip', problems, optional: true) ?? const [];

    FeeRows? fees;
    final feesNode = doc['fees'];
    if (feesNode != null) {
      if (feesNode is! YamlMap) {
        problems.add('fees: must be a mapping');
      } else {
        YamlFieldReader(
          feesNode,
          problems,
          prefix: 'fees.',
        ).checkKeys(const {'description'});
        final pattern = _regex(feesNode, 'description', problems, at: 'fees.');
        if (pattern != null) fees = FeeRows(pattern);
        if (!keys.contains(StatementColumnKey.reference)) {
          problems.add('fees: needs a "reference" column to link fee rows');
        }
      }
    }

    final amount = _readAmountStyle(doc['amount'], problems);
    if (single) {
      final hasMarker = keys.contains(StatementColumnKey.marker);
      if (amount == null) {
        problems.add('amount: required with a single "amount" column');
      } else if (hasMarker != (amount.markerOut != null)) {
        problems.add(
          'amount: set marker_out and marker_in with a "marker" column, '
          'or negative_is without one',
        );
      }
    } else if (amount != null) {
      problems.add('amount: only applies to a single "amount" column');
    }

    final rules = _readRules(doc['rules'], problems);
    final hint = r.string('password_hint', pattern: _idPattern, optional: true);

    if (problems.isNotEmpty) throw PackFormatException(source, problems);
    return StatementPack(
      id: id!,
      institution: institution!,
      name: name!,
      version: version!,
      minEngineVersion: minEngine,
      currency: currency!,
      utcOffset: utcOffset!,
      detect: List.unmodifiable(detect!),
      period: period,
      periodFormat: periodFormat,
      columns: List.unmodifiable(columns),
      timeFormat: timeFormat!,
      rowStartsWith: rowStart!,
      order: order!,
      completedStatus: completed,
      skip: List.unmodifiable(skip),
      fees: fees,
      amount: amount,
      rules: List.unmodifiable(rules),
      passwordHint: hint,
    );
  }

  /// Stable identifier, e.g. `mpesa_statement`.
  final String id;

  /// The SMS pack id of the same institution, e.g. `mpesa`. Transactions
  /// read with this pack carry it as their pack id, so they match SMS.
  final String institution;

  /// Display name.
  final String name;

  /// Semantic version.
  final String version;

  /// The oldest engine version that can read this pack.
  final String minEngineVersion;

  /// ISO 4217 code of the statement's amounts.
  final String currency;

  /// Offset of the times printed on the statement.
  final Duration utcOffset;

  /// Any of these matching the first page's text selects this pack.
  final List<RegExp> detect;

  /// Finds the statement period, with `start` and `end` groups.
  final RegExp? period;

  /// How to read [period] dates.
  final MessageTimeFormat? periodFormat;

  /// Table columns, left to right.
  final List<StatementColumn> columns;

  /// How to read a row's date (and time column, if any) as one value.
  final MessageTimeFormat timeFormat;

  /// A line starts a new row when this column has text; other lines
  /// continue the row above.
  final StatementColumnKey rowStartsWith;

  /// The order rows are printed in.
  final RowOrder order;

  /// Matches statuses that moved money; null when every row counts.
  final RegExp? completedStatus;

  /// Lines to drop, such as page numbers and disclaimers.
  final List<RegExp> skip;

  /// Charge rows to fold into their payment.
  final FeeRows? fees;

  /// How a single amount column shows direction.
  final AmountStyle? amount;

  /// Description rules, first match wins.
  final List<StatementRule> rules;

  /// Key of the app's approved password hint for this statement.
  final String? passwordHint;

  /// The column for [key], or null when the statement has none.
  StatementColumn? column(StatementColumnKey key) =>
      columns.where((c) => c.key == key).firstOrNull;

  /// Whether [firstPageText] looks like this pack's statement.
  bool matches(String firstPageText) =>
      detect.any((p) => p.hasMatch(firstPageText));

  static List<StatementColumn> _readColumns(
    Object? node,
    List<String> problems,
  ) {
    if (node is! YamlList || node.isEmpty) {
      problems.add('columns: a non-empty list is required');
      return const [];
    }
    final columns = <StatementColumn>[];
    final seen = <StatementColumnKey>{};
    for (var i = 0; i < node.length; i++) {
      final at = 'columns[$i]';
      final item = node[i];
      if (item is! YamlMap) {
        problems.add('$at: must be a mapping');
        continue;
      }
      final before = problems.length;
      final r = YamlFieldReader(item, problems, prefix: '$at.');
      r.checkKeys(const {'key', 'header', 'format', 'negative', 'align'});
      final keyText = r.string('key');
      final key = keyText == null ? null : StatementColumnKey.fromCode(keyText);
      if (keyText != null && key == null) {
        problems.add('$at.key: unknown column "$keyText"');
      }
      if (key != null && !seen.add(key)) {
        problems.add('$at.key: "${key.code}" appears twice');
      }
      final header = _regex(item, 'header', problems, at: '$at.');
      String? format;
      if (key == StatementColumnKey.date || key == StatementColumnKey.time) {
        format = r.string('format');
      } else if (item['format'] != null) {
        problems.add('$at.format: only date and time columns have a format');
      }
      final negative = r.boolean('negative') ?? false;
      final alignText = r.string('align', optional: true);
      final align = switch (alignText) {
        null || 'left' => ColumnAlign.left,
        'right' => ColumnAlign.right,
        _ => null,
      };
      if (align == null) problems.add('$at.align: must be left or right');
      if (problems.length > before) continue;
      columns.add(
        StatementColumn(
          key: key!,
          header: header!,
          format: format,
          negative: negative,
          align: align!,
        ),
      );
    }
    return columns;
  }

  // The date column's format, joined with the time column's when there is
  // one. Without a time, rows fall at midnight.
  static MessageTimeFormat? _rowTimeFormat(
    List<StatementColumn> columns,
    List<String> problems,
  ) {
    String? of(StatementColumnKey key) =>
        columns.where((c) => c.key == key).firstOrNull?.format;
    final date = of(StatementColumnKey.date);
    if (date == null) return null;
    final time = of(StatementColumnKey.time);
    final pattern = time == null ? date : '$date $time';
    try {
      return MessageTimeFormat(pattern);
    } on FormatException {
      if (time != null) {
        problems.add(
          'columns: the date and time formats together must make a full '
          'date and time ("$pattern")',
        );
        return null;
      }
    }
    try {
      return MessageTimeFormat(pattern, dateOnly: true);
    } on FormatException catch (e) {
      problems.add('columns: date format "$pattern": ${e.message}');
      return null;
    }
  }

  static AmountStyle? _readAmountStyle(Object? node, List<String> problems) {
    if (node == null) return null;
    if (node is! YamlMap) {
      problems.add('amount: must be a mapping');
      return null;
    }
    final r = YamlFieldReader(node, problems, prefix: 'amount.');
    r.checkKeys(const {'negative_is', 'marker_out', 'marker_in'});
    final negativeText = r.string('negative_is', optional: true);
    final negativeIsOut = switch (negativeText) {
      null => null,
      'out' => true,
      'in' => false,
      _ => null,
    };
    if (negativeText != null && negativeIsOut == null) {
      problems.add('amount.negative_is: must be in or out');
    }
    final out = _regex(
      node,
      'marker_out',
      problems,
      at: 'amount.',
      optional: true,
    );
    final into = _regex(
      node,
      'marker_in',
      problems,
      at: 'amount.',
      optional: true,
    );
    if ((out == null) != (into == null)) {
      problems.add('amount: set both marker_out and marker_in');
    }
    if ((negativeIsOut == null) == (out == null)) {
      problems.add('amount: set either negative_is or the two markers');
    }
    return AmountStyle(
      negativeIsOut: negativeIsOut,
      markerOut: out,
      markerIn: into,
    );
  }

  static List<StatementRule> _readRules(Object? node, List<String> problems) {
    if (node == null) return const [];
    if (node is! YamlList) {
      problems.add('rules: must be a list');
      return const [];
    }
    final rules = <StatementRule>[];
    final seen = <String>{};
    for (var i = 0; i < node.length; i++) {
      final at = 'rules[$i]';
      final item = node[i];
      if (item is! YamlMap) {
        problems.add('$at: must be a mapping');
        continue;
      }
      final before = problems.length;
      final r = YamlFieldReader(item, problems, prefix: '$at.');
      r.checkKeys(const {'id', 'type', 'pattern', 'ignore_case'});
      final id = r.string('id', pattern: _idPattern);
      if (id != null && !seen.add(id)) {
        problems.add('$at.id: duplicate rule id "$id"');
      }
      final typeText = r.string('type');
      final type = typeText == null ? null : TransactionType.fromCode(typeText);
      if (typeText != null && type == null) {
        problems.add('$at.type: unknown type "$typeText"');
      }
      final pattern = _regex(
        item,
        'pattern',
        problems,
        at: '$at.',
        ignoreCase: r.boolean('ignore_case') ?? true,
      );
      if (pattern != null) {
        final extra = _groups(pattern.pattern).difference(_ruleGroups);
        if (extra.isNotEmpty) {
          problems.add(
            '$at.pattern: groups $extra are not one of $_ruleGroups',
          );
        }
      }
      if (problems.length > before) continue;
      rules.add(StatementRule(id: id!, type: type!, pattern: pattern!));
    }
    return rules;
  }

  static RegExp? _regex(
    YamlMap map,
    String key,
    List<String> problems, {
    String at = '',
    bool optional = false,
    bool ignoreCase = true,
  }) {
    final value = map[key];
    if (value == null) {
      if (!optional) problems.add('$at$key: is required');
      return null;
    }
    if (value is! String || value.isEmpty) {
      problems.add('$at$key: must be a non-empty string');
      return null;
    }
    try {
      return RegExp(value, caseSensitive: !ignoreCase);
    } on FormatException catch (e) {
      problems.add('$at$key: does not compile: ${e.message}');
      return null;
    }
  }

  static List<RegExp>? _regexList(
    YamlMap map,
    String key,
    List<String> problems, {
    bool optional = false,
    bool multiLine = false,
  }) {
    final value = map[key];
    if (value == null) {
      if (!optional) problems.add('$key: is required');
      return null;
    }
    if (value is! YamlList) {
      problems.add('$key: must be a list of patterns');
      return null;
    }
    final result = <RegExp>[];
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is! String || item.isEmpty) {
        problems.add('$key[$i]: must be a non-empty string');
        continue;
      }
      try {
        result.add(RegExp(item, caseSensitive: false, multiLine: multiLine));
      } on FormatException catch (e) {
        problems.add('$key[$i]: does not compile: ${e.message}');
      }
    }
    return result;
  }

  static Set<String> _groups(String pattern) => RegExp(
    r'\(\?<([A-Za-z_][A-Za-z0-9_]*)>',
  ).allMatches(pattern).map((m) => m.group(1)!).toSet();

  static const _ruleGroups = {'counterparty', 'account'};
  static final _idPattern = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _semver = RegExp(
    r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
  );
}

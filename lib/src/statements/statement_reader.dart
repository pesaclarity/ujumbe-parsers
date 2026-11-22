import '../money.dart';
import '../pack.dart';
import '../parser.dart';
import 'page_text.dart';
import 'statement_pack.dart';
import 'table_layout.dart';

/// One statement row, read.
class StatementLine {
  /// Creates a line.
  const StatementLine({
    required this.time,
    required this.description,
    required this.moneyInMinor,
    required this.moneyOutMinor,
    required this.rawHash,
    this.reference,
    this.status,
    this.balanceMinor,
    this.kind,
  });

  /// The transaction type as printed in its own column, if the statement
  /// has one.
  final String? kind;

  /// When it happened, in UTC.
  final DateTime time;

  /// The institution's reference, upper-cased.
  final String? reference;

  /// The description, wrapped lines joined.
  final String description;

  /// The status as printed, if the statement has a status column.
  final String? status;

  /// Money in and out, in minor units, both zero or positive.
  final int moneyInMinor, moneyOutMinor;

  /// Balance after the row, if printed.
  final int? balanceMinor;

  /// [hashMessageBody] of the row's text.
  final String rawHash;

  /// Signed change to the balance.
  int get netMinor => moneyInMinor - moneyOutMinor;
}

/// A row whose printed balance does not follow from the row before it.
class StatementBalanceBreak {
  /// Creates a break.
  const StatementBalanceBreak({
    required this.reference,
    required this.time,
    required this.expectedBalanceMinor,
    required this.statedBalanceMinor,
  });

  /// The row's reference, if it has one.
  final String? reference;

  /// The row's time.
  final DateTime time;

  /// Previous balance plus this row's net amount.
  final int expectedBalanceMinor;

  /// The balance printed on the row.
  final int statedBalanceMinor;

  /// Money unaccounted for between this row and the one before.
  int get gapMinor => statedBalanceMinor - expectedBalanceMinor;
}

/// A statement read with a [StatementPack].
class ParsedStatement {
  /// Creates a statement.
  const ParsedStatement({
    required this.pack,
    required this.periodStart,
    required this.periodEnd,
    required this.lines,
    required this.transactions,
    required this.openingBalanceMinor,
    required this.closingBalanceMinor,
    required this.balanceBreaks,
    required this.unreadLines,
    this.statedOpeningBalanceMinor,
    this.statedClosingBalanceMinor,
  });

  /// The opening and closing balances the statement's summary prints, when
  /// its pack reads them.
  final int? statedOpeningBalanceMinor, statedClosingBalanceMinor;

  /// Whether the balances the summary prints, if read, are the ones the
  /// rows start from and end at.
  bool get matchesSummary =>
      (statedOpeningBalanceMinor == null ||
          statedOpeningBalanceMinor == openingBalanceMinor) &&
      (statedClosingBalanceMinor == null ||
          statedClosingBalanceMinor == closingBalanceMinor);

  /// The pack that read it.
  final StatementPack pack;

  /// First and last day of the period, at midnight UTC, if printed.
  final DateTime? periodStart, periodEnd;

  /// Every row read, oldest first, including rows that did not complete.
  final List<StatementLine> lines;

  /// Completed rows as transactions, oldest first, with charge rows folded
  /// into their payment so each matches the SMS for the same reference.
  final List<ParsedTransaction> transactions;

  /// Balance before the first completed row, if balances are printed.
  final int? openingBalanceMinor;

  /// Balance after the last completed row, if balances are printed.
  final int? closingBalanceMinor;

  /// Where printed balances do not add up.
  final List<StatementBalanceBreak> balanceBreaks;

  /// Rows that could not be read. Hold them for review, then discard them.
  final List<String> unreadLines;

  /// Whether every row was read, every balance follows from the last, and
  /// the first and last balances are the ones the summary prints.
  bool get reconciles =>
      balanceBreaks.isEmpty && unreadLines.isEmpty && matchesSummary;
}

/// Picks the pack whose `detect` patterns match the first page, or null.
StatementPack? detectStatementPack(
  List<StatementPage> pages,
  Iterable<StatementPack> packs,
) {
  if (pages.isEmpty) return null;
  final first = pages.first.text;
  for (final pack in packs) {
    if (pack.matches(first)) return pack;
  }
  return null;
}

/// Reads statements laid out as [pack] describes.
class StatementReader {
  /// Creates a reader for [pack].
  const StatementReader(this.pack);

  /// The layout this reader reads.
  final StatementPack pack;

  /// Reads [pages], the statement's pages in order.
  ParsedStatement read(List<StatementPage> pages) {
    final table = readTable(pages, pack);
    // Joined, so a period or balance printed over several lines is found.
    final outside = table.outside.join('\n');
    final (periodStart, periodEnd) = _period(outside);

    var lines = <StatementLine>[];
    final unread = <String>[];
    for (final row in table.rows) {
      final line = _line(row);
      if (line == null) {
        unread.add(row.textIn(pack.columns));
      } else {
        lines.add(line);
      }
    }
    final newestFirst = switch (pack.order) {
      RowOrder.newestFirst => true,
      RowOrder.oldestFirst => false,
      RowOrder.detect =>
        lines.length > 1 && lines.first.time.isAfter(lines.last.time),
    };
    // Reversing, rather than sorting, keeps same-second rows in the order
    // their balances were applied.
    if (newestFirst) lines = lines.reversed.toList();

    final completed = _chainSameTime(lines.where(_isCompleted).toList());
    final breaks = <StatementBalanceBreak>[];
    for (var i = 1; i < completed.length; i++) {
      final before = completed[i - 1].balanceMinor;
      final stated = completed[i].balanceMinor;
      if (before == null || stated == null) continue;
      final expected = before + completed[i].netMinor;
      if (expected != stated) {
        breaks.add(
          StatementBalanceBreak(
            reference: completed[i].reference,
            time: completed[i].time,
            expectedBalanceMinor: expected,
            statedBalanceMinor: stated,
          ),
        );
      }
    }

    final first = completed.firstOrNull;
    final last = completed.lastOrNull;
    return ParsedStatement(
      pack: pack,
      periodStart: periodStart,
      periodEnd: periodEnd,
      lines: List.unmodifiable(lines),
      transactions: List.unmodifiable(_transactions(completed)),
      openingBalanceMinor: first?.balanceMinor == null
          ? null
          : first!.balanceMinor! - first.netMinor,
      closingBalanceMinor: last?.balanceMinor,
      balanceBreaks: List.unmodifiable(breaks),
      unreadLines: List.unmodifiable(unread),
      statedOpeningBalanceMinor: _stated(pack.openingBalance, outside),
      statedClosingBalanceMinor: _stated(pack.closingBalance, outside),
    );
  }

  static int? _stated(RegExp? pattern, String outside) {
    final m = pattern?.firstMatch(outside);
    if (m == null) return null;
    final money = _money(m.namedGroup('amount')!);
    return money == null || !money.$2 ? null : money.$1;
  }

  /// Puts rows that share a time in the order their balances follow.
  ///
  /// Statements print rows from the same second in no reliable order (an
  /// overdraft draw, the payment it funds and the fee can come in any
  /// order). Each such group is put in the order where the most rows have
  /// a printed balance equal to the previous balance plus their amount.
  static List<StatementLine> _chainSameTime(List<StatementLine> rows) {
    final result = <StatementLine>[];
    var start = 0;
    while (start < rows.length) {
      var end = start;
      while (end < rows.length && rows[end].time == rows[start].time) {
        end++;
      }
      final group = rows.sublist(start, end);
      result.addAll(
        group.length == 1
            ? group
            : _chain(group, result.lastOrNull?.balanceMinor),
      );
      start = end;
    }
    return result;
  }

  /// Groups larger than this keep their printed order: searching every
  /// order would take too long, and such groups are rare.
  static const _maxChainedGroup = 8;

  /// The order of [group] in which the most rows follow from the balance
  /// before them, starting from [before] when it is known. Ties keep the
  /// printed order.
  static List<StatementLine> _chain(List<StatementLine> group, int? before) {
    if (group.length > _maxChainedGroup) return group;
    bool follows(int? previous, StatementLine row) =>
        previous != null &&
        row.balanceMinor != null &&
        previous + row.netMinor == row.balanceMinor;

    var best = group;
    var bestLinks = -1;
    final used = List.filled(group.length, false);
    final path = <StatementLine>[];

    // Depth-first over orders, trying linking rows first; stops at the
    // first order where every row links.
    bool search(int? previous, int links) {
      if (path.length == group.length) {
        if (links > bestLinks) {
          bestLinks = links;
          best = [...path];
        }
        return links == group.length - (before == null ? 1 : 0);
      }
      final order = [
        for (var i = 0; i < group.length; i++)
          if (!used[i] && follows(previous, group[i])) i,
        for (var i = 0; i < group.length; i++)
          if (!used[i] && !follows(previous, group[i])) i,
      ];
      for (final i in order) {
        used[i] = true;
        path.add(group[i]);
        final linked = follows(previous, group[i]) ? 1 : 0;
        if (search(group[i].balanceMinor, links + linked)) return true;
        path.removeLast();
        used[i] = false;
      }
      return false;
    }

    search(before, 0);
    return best;
  }

  (DateTime?, DateTime?) _period(String outside) {
    final pattern = pack.period;
    final format = pack.periodFormat;
    if (pattern == null || format == null) return (null, null);
    for (final m in pattern.allMatches(outside)) {
      // Period dates are calendar days, so they stay at midnight UTC.
      final start = format.parse(
        m.namedGroup('start')!,
        utcOffset: Duration.zero,
      );
      final end = format.parse(m.namedGroup('end')!, utcOffset: Duration.zero);
      if (start != null && end != null) return (start, end);
    }
    return (null, null);
  }

  StatementLine? _line(TableRow row) {
    final hasTime = pack.column(StatementColumnKey.time) != null;
    final timeText = hasTime
        ? '${row[StatementColumnKey.date]} ${row[StatementColumnKey.time]}'
        : row[StatementColumnKey.date];
    final time = pack.timeFormat.parse(timeText, utcOffset: pack.utcOffset);
    if (time == null) return null;

    final int moneyIn, moneyOut;
    if (pack.column(StatementColumnKey.amount) == null) {
      final into = _money(row[StatementColumnKey.moneyIn]);
      final out = _money(row[StatementColumnKey.moneyOut]);
      if (into == null || out == null) return null;
      if (into.$1 < 0 && !_negativeAllowed(StatementColumnKey.moneyIn) ||
          out.$1 < 0 && !_negativeAllowed(StatementColumnKey.moneyOut)) {
        return null;
      }
      (moneyIn, moneyOut) = (into.$1.abs(), out.$1.abs());
      if (moneyIn > 0 && moneyOut > 0 || !into.$2 && !out.$2) return null;
    } else {
      final amount = _money(row[StatementColumnKey.amount]);
      if (amount == null || !amount.$2) return null;
      final style = pack.amount!;
      final bool isOut;
      if (style.markerOut != null) {
        final marker = row[StatementColumnKey.marker];
        if (style.markerOut!.hasMatch(marker)) {
          isOut = true;
        } else if (style.markerIn!.hasMatch(marker)) {
          isOut = false;
        } else {
          return null;
        }
      } else {
        isOut = (amount.$1 < 0) == style.negativeIsOut!;
      }
      final value = amount.$1.abs();
      (moneyIn, moneyOut) = isOut ? (0, value) : (value, 0);
    }

    int? balance;
    if (pack.column(StatementColumnKey.balance) != null) {
      final parsed = _money(row[StatementColumnKey.balance]);
      if (parsed == null || !parsed.$2) return null;
      balance = parsed.$1;
    }

    final reference = row[StatementColumnKey.reference];
    final status = row[StatementColumnKey.status];
    final kind = row[StatementColumnKey.kind];
    return StatementLine(
      kind: kind.isEmpty ? null : kind,
      time: time,
      reference: reference.isEmpty ? null : reference.toUpperCase(),
      description: row[StatementColumnKey.description],
      status: status.isEmpty ? null : status,
      moneyInMinor: moneyIn,
      moneyOutMinor: moneyOut,
      balanceMinor: balance,
      rawHash: hashMessageBody(row.textIn(pack.columns)),
    );
  }

  bool _negativeAllowed(StatementColumnKey key) =>
      pack.column(key)?.negative ?? false;

  // Reads a printed amount: the signed value in minor units, and whether
  // the cell held one at all. Empty cells read as (0, false); text that is
  // not an amount reads as null.
  static (int, bool)? _money(String text) {
    final clean = text.trim();
    if (clean.isEmpty || clean == '-') return (0, false);
    final negative = clean.startsWith('-') || clean.startsWith('(');
    final digits = clean.replaceAll(RegExp(r'^[-(]|\)$'), '').trim();
    final value = parseMinorUnits(digits);
    if (value == null) return null;
    return (negative ? -value : value, true);
  }

  bool _isCompleted(StatementLine line) {
    final pattern = pack.completedStatus;
    if (pattern == null) return true;
    return pattern.hasMatch(line.status ?? '');
  }

  bool _isCharge(StatementLine line) {
    final fees = pack.fees;
    if (fees == null || line.moneyOutMinor <= 0) return false;
    return (fees.description?.hasMatch(line.description) ?? true) &&
        (fees.kind?.hasMatch(line.kind ?? '') ?? true);
  }

  List<ParsedTransaction> _transactions(List<StatementLine> completed) {
    final byReference = <String, List<StatementLine>>{};
    for (final line in completed) {
      final ref = line.reference;
      if (ref != null) (byReference[ref] ??= []).add(line);
    }
    final reversals = _reversals(byReference.values);
    final reversed = reversals.values.toSet();
    bool isFee(StatementLine l) => _isCharge(l) && !reversed.contains(l);

    final result = <ParsedTransaction>[];
    for (final line in completed) {
      final group = line.reference == null
          ? [line]
          : byReference[line.reference]!;
      final charges = group.where(isFee).toList();
      final payments = group
          .where((l) => !isFee(l) && !reversals.containsKey(l))
          .toList();
      if (isFee(line) && payments.isNotEmpty) continue;

      int? fee;
      var balance = line.balanceMinor;
      // Fold charge rows into the payment that shares their reference. With
      // several rows on one reference (an overdraft draw and the payment it
      // funds), the first outgoing one takes the fee. A charge the bank gave
      // back stays apart, as does the row giving it back.
      final payer =
          payments.where((l) => l.moneyOutMinor > 0).firstOrNull ??
          payments.firstOrNull;
      if (charges.isNotEmpty && identical(line, payer)) {
        fee = charges.fold<int>(0, (sum, c) => sum + c.moneyOutMinor);
        balance = group.last.balanceMinor;
      }

      final undone = reversals[line];
      final (ruleId, type, counterparty, account) = undone != null
          ? ('reversal', TransactionType.reversal, null, line.reference)
          : _classify(line);
      result.add(
        ParsedTransaction(
          packId: pack.institution,
          packVersion: pack.version,
          ruleId: 'statement_$ruleId',
          type: type,
          direction: line.netMinor >= 0
              ? Direction.incoming
              : Direction.outgoing,
          amountMinor: line.moneyInMinor + line.moneyOutMinor,
          currency: pack.currency,
          time: line.time,
          timeFromMessage: true,
          rawHash: line.rawHash,
          feeMinor: fee,
          balanceMinor: balance,
          // The reversal prints the reference of what it undoes, which is
          // kept as its account, as for a reversal message.
          receipt: undone != null ? null : line.reference,
          counterparty: counterparty,
          account: account,
        ),
      );
    }
    return result;
  }

  /// Rows that undo an earlier row printed with the same reference: the
  /// same type (or description, without a type column) and amount, the
  /// other way. Maps each such row to the row it undoes.
  static Map<StatementLine, StatementLine> _reversals(
    Iterable<List<StatementLine>> groups,
  ) {
    final result = <StatementLine, StatementLine>{};
    for (final group in groups) {
      if (group.length < 2) continue;
      final undone = <StatementLine>{};
      for (var i = 1; i < group.length; i++) {
        final later = group[i];
        for (final earlier in group.take(i)) {
          if (undone.contains(earlier) || result.containsKey(earlier)) continue;
          final sameKind = later.kind != null
              ? later.kind == earlier.kind
              : later.description == earlier.description;
          if (sameKind &&
              later.netMinor != 0 &&
              later.netMinor == -earlier.netMinor) {
            result[later] = earlier;
            undone.add(earlier);
            break;
          }
        }
      }
    }
    return result;
  }

  (String, TransactionType, String?, String?) _classify(StatementLine line) {
    if (_isCharge(line)) return ('charge', TransactionType.bank, null, null);
    for (final rule in pack.rules) {
      if (rule.kind != null && !rule.kind!.hasMatch(line.kind ?? '')) {
        continue;
      }
      final direction = line.netMinor >= 0
          ? Direction.incoming
          : Direction.outgoing;
      if (rule.direction != null && rule.direction != direction) continue;
      final pattern = rule.pattern;
      final m = pattern?.firstMatch(line.description);
      if (pattern != null && m == null) continue;
      String? group(String name) {
        if (m == null || !m.groupNames.contains(name)) return null;
        final value = m.namedGroup(name)?.trim();
        return value == null || value.isEmpty ? null : value;
      }

      return (rule.id, rule.type, group('counterparty'), group('account'));
    }
    return ('other', TransactionType.bank, null, null);
  }
}

import 'money.dart';
import 'pack.dart';
import 'parser.dart';
import 'time_format.dart';

/// Version of the M-Pesa statement layout reader, reported as the
/// [ParsedTransaction.packVersion] of statement transactions.
const mpesaStatementParserVersion = '0.1.0';

/// One row of the detailed statement table, as printed.
class StatementRow {
  /// Creates a row.
  const StatementRow({
    required this.receipt,
    required this.completedAt,
    required this.details,
    required this.status,
    required this.paidInMinor,
    required this.withdrawnMinor,
    required this.balanceMinor,
    required this.rawHash,
  });

  /// Receipt number, e.g. `TJA0000001`. Fee rows share their payment's.
  final String receipt;

  /// Completion time in UTC.
  final DateTime completedAt;

  /// The details column, with wrapped lines joined by single spaces.
  final String details;

  /// Transaction status as printed, e.g. `Completed`.
  final String status;

  /// Paid in, in minor units (zero when the column is empty).
  final int paidInMinor;

  /// Withdrawn, in minor units and positive (zero when empty).
  final int withdrawnMinor;

  /// Balance after this row, in minor units.
  final int balanceMinor;

  /// [hashMessageBody] of the row's text.
  final String rawHash;

  /// Whether the row moved money. Only completed rows count.
  bool get isCompleted => status.toLowerCase() == 'completed';

  /// Signed change to the balance.
  int get netMinor => paidInMinor - withdrawnMinor;
}

/// A completed row whose printed balance does not follow from the row
/// before it, which usually means rows are missing from the text.
class BalanceBreak {
  /// Creates a break.
  const BalanceBreak({
    required this.receipt,
    required this.expectedBalanceMinor,
    required this.statedBalanceMinor,
  });

  /// Receipt of the row whose balance does not follow.
  final String receipt;

  /// Previous balance plus this row's net amount.
  final int expectedBalanceMinor;

  /// The balance printed on the row.
  final int statedBalanceMinor;

  /// Money unaccounted for between this row and the one before it.
  int get gapMinor => statedBalanceMinor - expectedBalanceMinor;
}

/// The result of reading an M-Pesa statement's text.
class MpesaStatement {
  /// Creates a statement.
  const MpesaStatement({
    required this.periodStart,
    required this.periodEnd,
    required this.rows,
    required this.transactions,
    required this.openingBalanceMinor,
    required this.closingBalanceMinor,
    required this.balanceBreaks,
    required this.unreadLines,
  });

  /// First day of the statement period, as a UTC date at midnight, or
  /// `null` if the text does not state one.
  final DateTime? periodStart;

  /// Last day of the statement period; see [periodStart].
  final DateTime? periodEnd;

  /// Every row read, in chronological order, including rows that did not
  /// complete.
  final List<StatementRow> rows;

  /// Completed rows as transactions, in chronological order. Fee rows are
  /// folded into the payment they belong to, so each transaction matches
  /// the SMS for the same receipt, [ParsedTransaction.dedupeKey] included.
  final List<ParsedTransaction> transactions;

  /// Balance before the first completed row, or `null` if there is none.
  final int? openingBalanceMinor;

  /// Balance after the last completed row, or `null` if there is none.
  final int? closingBalanceMinor;

  /// Where the printed balances do not add up.
  final List<BalanceBreak> balanceBreaks;

  /// Table text that looked like a row but could not be read. Hold it for
  /// review like an unmatched SMS, then discard it.
  final List<String> unreadLines;

  /// Whether every row was read and every balance follows from the last.
  bool get reconciles => balanceBreaks.isEmpty && unreadLines.isEmpty;
}

/// Reads the text of an M-Pesa full statement.
///
/// The app extracts the text from the PDF (and handles its password);
/// this parser only sees text. It expects the detailed table's columns in
/// the published order: receipt number, completion time, details,
/// transaction status, paid in, withdrawn (printed negative) and balance.
/// Details may wrap over several lines, before or after the line holding
/// the amounts, and rows may continue across page breaks. Page headers,
/// footers and the summary table are skipped.
class MpesaStatementParser {
  /// Creates a parser.
  const MpesaStatementParser();

  /// Statement times are East Africa Time.
  static const utcOffset = Duration(hours: 3);

  /// Parses [text], the statement's extracted text with pages in order.
  MpesaStatement parse(String text) {
    DateTime? periodStart, periodEnd;
    final pending = <List<String>>[];
    var inTable = false;

    for (final raw in text.split(_lineBreak)) {
      final line = raw.trim().replaceAll(_spaces, ' ');
      if (line.isEmpty) continue;
      final period = _period.firstMatch(line);
      if (period != null && periodStart == null) {
        periodStart = _date(period.group(1)!);
        periodEnd = _date(period.group(2)!);
        continue;
      }
      if (_columnHeader.hasMatch(line)) {
        inTable = true;
      } else if (_pageChrome.hasMatch(line)) {
        inTable = false;
      } else if (_rowStart.hasMatch(line)) {
        pending.add([line]);
        inTable = true;
      } else if (inTable && pending.isNotEmpty) {
        pending.last.add(line);
      }
    }

    final rows = <StatementRow>[];
    final unread = <String>[];
    for (final parts in pending) {
      final row = _readRow(parts.join(' '));
      if (row == null) {
        unread.add(parts.join(' '));
      } else {
        rows.add(row);
      }
    }
    if (rows.length > 1 &&
        rows.first.completedAt.isAfter(rows.last.completedAt)) {
      // Statements list newest first; reversing keeps same-second rows in
      // the order their balances were applied.
      final reversed = rows.reversed.toList();
      rows
        ..clear()
        ..addAll(reversed);
    }

    final completed = rows.where((r) => r.isCompleted).toList();
    final breaks = <BalanceBreak>[];
    for (var i = 1; i < completed.length; i++) {
      final expected = completed[i - 1].balanceMinor + completed[i].netMinor;
      if (expected != completed[i].balanceMinor) {
        breaks.add(
          BalanceBreak(
            receipt: completed[i].receipt,
            expectedBalanceMinor: expected,
            statedBalanceMinor: completed[i].balanceMinor,
          ),
        );
      }
    }

    return MpesaStatement(
      periodStart: periodStart,
      periodEnd: periodEnd,
      rows: List.unmodifiable(rows),
      transactions: List.unmodifiable(_transactions(completed)),
      openingBalanceMinor: completed.isEmpty
          ? null
          : completed.first.balanceMinor - completed.first.netMinor,
      closingBalanceMinor: completed.isEmpty
          ? null
          : completed.last.balanceMinor,
      balanceBreaks: List.unmodifiable(breaks),
      unreadLines: List.unmodifiable(unread),
    );
  }

  StatementRow? _readRow(String text) {
    final start = _rowStart.firstMatch(text)!;
    final completedAt = _timeFormat.parse(
      start.group(2)!,
      utcOffset: utcOffset,
    );
    if (completedAt == null) return null;
    final rest = text.substring(start.end);
    final amounts = _amounts.allMatches(rest).lastOrNull;
    if (amounts == null) return null;

    int? money(String? text) =>
        text == null ? null : parseMinorUnits(text.replaceFirst('-', ''));
    final first = money(amounts.namedGroup('first'));
    final second = money(amounts.namedGroup('second'));
    final balanceText = amounts.namedGroup('balance')!;
    final balance = money(balanceText);
    if (first == null || balance == null) return null;
    if (amounts.namedGroup('second') != null && second == null) return null;

    final int paidIn, withdrawn;
    if (second != null) {
      (paidIn, withdrawn) = (first, second);
    } else if (amounts.namedGroup('first')!.startsWith('-')) {
      (paidIn, withdrawn) = (0, first);
    } else {
      (paidIn, withdrawn) = (first, 0);
    }

    final details = [
      rest.substring(0, amounts.start),
      rest.substring(amounts.end),
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
    return StatementRow(
      receipt: start.group(1)!.toUpperCase(),
      completedAt: completedAt,
      details: details,
      status: amounts.namedGroup('status')!,
      paidInMinor: paidIn,
      withdrawnMinor: withdrawn,
      balanceMinor: balanceText.startsWith('-') ? -balance : balance,
      rawHash: hashMessageBody(text),
    );
  }

  List<ParsedTransaction> _transactions(List<StatementRow> completed) {
    final byReceipt = <String, List<StatementRow>>{};
    for (final row in completed) {
      (byReceipt[row.receipt] ??= []).add(row);
    }

    final result = <ParsedTransaction>[];
    for (final row in completed) {
      final group = byReceipt[row.receipt]!;
      final charges = group.where(_isCharge).toList();
      final payments = group.where((r) => !_isCharge(r)).toList();
      if (_isCharge(row) && payments.isNotEmpty) continue;

      int? fee;
      var balance = row.balanceMinor;
      // A payment's fee row sits beside it with the same receipt; fold it in
      // so the result matches the SMS, which states the fee and the balance
      // after it. With several rows on one receipt (a Fuliza draw and the
      // payment it funds), the first outgoing one takes it.
      final payer =
          payments.where((r) => r.withdrawnMinor > 0).firstOrNull ??
          payments.firstOrNull;
      if (charges.isNotEmpty && identical(row, payer)) {
        fee = charges.fold<int>(0, (sum, c) => sum + c.withdrawnMinor);
        balance = group.last.balanceMinor;
      }

      final kind = _classify(row);
      result.add(
        ParsedTransaction(
          packId: 'mpesa',
          packVersion: mpesaStatementParserVersion,
          ruleId: 'statement_${kind.rule}',
          type: kind.type,
          direction: row.netMinor >= 0
              ? Direction.incoming
              : Direction.outgoing,
          amountMinor: row.paidInMinor + row.withdrawnMinor,
          currency: 'KES',
          time: row.completedAt,
          timeFromMessage: true,
          rawHash: row.rawHash,
          feeMinor: fee,
          balanceMinor: balance,
          receipt: row.receipt,
          counterparty: kind.counterparty,
          account: kind.account,
        ),
      );
    }
    return result;
  }

  static bool _isCharge(StatementRow row) =>
      row.withdrawnMinor > 0 && _charge.hasMatch(row.details);

  static _Kind _classify(StatementRow row) {
    if (_isCharge(row)) return const _Kind('charge', TransactionType.bank);
    for (final (pattern, rule, type) in _detailRules) {
      final m = pattern.firstMatch(row.details);
      if (m == null) continue;
      String? group(String name) =>
          m.groupNames.contains(name) ? m.namedGroup(name)?.trim() : null;
      return _Kind(
        rule,
        type,
        counterparty: group('counterparty'),
        account: group('account'),
      );
    }
    return const _Kind('other', TransactionType.bank);
  }

  static DateTime? _date(String text) {
    final m = _dateParts.firstMatch(text);
    if (m == null) return null;
    final month = _months.indexOf(m.group(2)!.toLowerCase()) + 1;
    if (month == 0) return null;
    final day = int.parse(m.group(1)!);
    final date = DateTime.utc(int.parse(m.group(3)!), month, day);
    return date.day == day ? date : null;
  }

  static final _timeFormat = MessageTimeFormat('yyyy-MM-dd HH:mm:ss');
  static final _lineBreak = RegExp(r'\r\n|[\r\n\f]');
  static final _spaces = RegExp(r'\s+');
  static final _rowStart = RegExp(
    r'^([A-Z0-9]{10}) (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?= |$)',
  );
  static final _amounts = RegExp(
    r'(?:^| )(?<status>Completed|Failed|Cancelled|Declined|Expired|Pending)'
    r' (?<first>-?[\d,]+\.\d{2})(?: (?<second>-?[\d,]+\.\d{2}))?'
    r' (?<balance>-?[\d,]+\.\d{2})(?= |$)',
    caseSensitive: false,
  );
  static final _columnHeader = RegExp(
    r'^Receipt No\.? Completion Time',
    caseSensitive: false,
  );
  static final _pageChrome = RegExp(
    r'^(?:Page \d+ of \d+|Disclaimer\b)',
    caseSensitive: false,
  );
  static final _period = RegExp(
    r'Statement Period:? (\d{1,2} [A-Za-z]{3} \d{4}) - '
    r'(\d{1,2} [A-Za-z]{3} \d{4})',
    caseSensitive: false,
  );
  static final _dateParts = RegExp(r'^(\d{1,2}) ([A-Za-z]{3}) (\d{4})$');
  static final _charge = RegExp(r'^[A-Za-z ]+ Charge$', caseSensitive: false);

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  // Detail wording from the public statement layout. First match wins.
  static final List<(RegExp, String, TransactionType)> _detailRules = [
    (
      _detail(
        r'^Pay Bill(?: Online| Fuliza M-?Pesa)? to \d+ - '
        r'(?<counterparty>.+?) Acc\.? ?(?<account>\S.*)$',
      ),
      'paybill',
      TransactionType.paybill,
    ),
    (
      _detail(
        r'^Merchant Payment(?: Online| Fuliza M-?Pesa)? to \d+ - '
        r'(?<counterparty>.+)$',
      ),
      'till',
      TransactionType.till,
    ),
    (
      _detail(
        r'^Customer Transfer(?: Fuliza M-?Pesa)? to (?<account>\S+) - '
        r'(?<counterparty>.+)$',
      ),
      'sent',
      TransactionType.sent,
    ),
    (
      _detail(
        r'^(?:Funds received|Business Payment) from (?<account>\S+) - '
        r'(?<counterparty>.+?)(?: via API.*)?$',
      ),
      'received',
      TransactionType.received,
    ),
    (
      _detail(
        r'^Customer Withdrawal At Agent Till (?<account>\d+) - '
        r'(?<counterparty>.+)$',
      ),
      'withdrawal',
      TransactionType.withdrawal,
    ),
    (
      _detail(r'^(?:Airtime Purchase|Recharge for Customer|Buy Bundles?)\b'),
      'airtime',
      TransactionType.airtime,
    ),
    (
      _detail(r'^OverDraft of Credit Party\b'),
      'fuliza',
      TransactionType.fuliza,
    ),
    (
      _detail(r'^OD Loan Repayment\b'),
      'fuliza_repayment',
      TransactionType.fulizaRepayment,
    ),
    (
      _detail(r'\bReversal\b(?:.* of (?<account>[A-Z0-9]{10})\b)?'),
      'reversal',
      TransactionType.reversal,
    ),
  ];

  static RegExp _detail(String pattern) =>
      RegExp(pattern, caseSensitive: false);
}

class _Kind {
  const _Kind(this.rule, this.type, {this.counterparty, this.account});

  final String rule;
  final TransactionType type;
  final String? counterparty;
  final String? account;
}

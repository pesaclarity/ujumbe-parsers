import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'money.dart';
import 'pack.dart';

/// An SMS as read from the phone's inbox.
class SmsMessage {
  /// Creates a message from [sender] with [body], received at [receivedAt].
  const SmsMessage({
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  /// The sender ID or number, e.g. `MPESA`.
  final String sender;

  /// The full message text.
  final String body;

  /// When the phone received the message. Used as the transaction time
  /// when the message itself prints none (Fuliza notices, for example).
  final DateTime receivedAt;
}

/// The outcome of parsing one message.
sealed class ParseResult {
  const ParseResult();
}

/// The sender is not one of the user's selected accounts. The message must
/// be dropped without being stored.
final class Ignored extends ParseResult {
  /// Creates an ignored result.
  const Ignored();
}

/// The sender is selected, but no rule matched. The message goes to the
/// review inbox so the user can tag its fields once.
final class Unmatched extends ParseResult {
  /// Creates an unmatched result.
  const Unmatched({
    required this.packId,
    required this.message,
    required this.rawHash,
    required this.reason,
  });

  /// The pack that owns the sender.
  final String packId;

  /// The original message, kept only until the user reviews it.
  final SmsMessage message;

  /// [hashMessageBody] of the body.
  final String rawHash;

  /// Why no transaction was produced, for the review inbox and debugging.
  final String reason;
}

/// A message parsed into a transaction. Holds no raw text.
final class ParsedTransaction extends ParseResult {
  /// Creates a parsed transaction.
  const ParsedTransaction({
    required this.packId,
    required this.packVersion,
    required this.ruleId,
    required this.type,
    required this.direction,
    required this.amountMinor,
    required this.currency,
    required this.time,
    required this.timeFromMessage,
    required this.rawHash,
    this.feeMinor,
    this.balanceMinor,
    this.receipt,
    this.counterparty,
    this.account,
  });

  /// The pack and version that produced this result.
  final String packId;

  /// See [packId].
  final String packVersion;

  /// The rule that matched.
  final String ruleId;

  /// The kind of transaction.
  final TransactionType type;

  /// Which way money moved.
  final Direction direction;

  /// Amount in minor units (cents). Never a floating-point value.
  final int amountMinor;

  /// ISO 4217 currency code.
  final String currency;

  /// Transaction time in UTC.
  final DateTime time;

  /// Whether [time] came from the message text rather than the time the
  /// phone received it.
  final bool timeFromMessage;

  /// SHA-256 of the message body, so the raw text can be discarded.
  final String rawHash;

  /// Transaction cost in minor units, if the message states one.
  final int? feeMinor;

  /// Account balance after the transaction in minor units, if stated.
  final int? balanceMinor;

  /// The institution's reference, e.g. an M-Pesa receipt number.
  final String? receipt;

  /// The other party as printed (name, till or paybill name).
  final String? counterparty;

  /// A phone number, account number or paybill account reference, as
  /// printed (often masked by the institution).
  final String? account;

  /// Key for matching this SMS against later statement imports: receipt,
  /// amount and time to the minute (statements rarely carry seconds).
  String get dedupeKey =>
      dedupeKeyFor(receipt: receipt, amountMinor: amountMinor, time: time);
}

/// Builds the dedupe key shared by SMS and statement imports.
String dedupeKeyFor({
  required String? receipt,
  required int amountMinor,
  required DateTime time,
}) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final minute =
      '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-'
      '${two(t.day)}T${two(t.hour)}:${two(t.minute)}Z';
  return '${receipt?.toUpperCase() ?? ''}|$amountMinor|$minute';
}

/// SHA-256 (hex) of a message body as UTF-8.
String hashMessageBody(String body) =>
    sha256.convert(utf8.encode(body)).toString();

/// Routes messages to packs by sender. Senders not covered are ignored.
class SenderFilter {
  /// Builds a filter for the selected [packs].
  ///
  /// Throws [ArgumentError] if two packs claim the same sender ID.
  SenderFilter(Iterable<ParserPack> packs) {
    for (final pack in packs) {
      for (final sender in pack.senders) {
        final key = normalise(sender);
        final existing = _bySender[key];
        if (existing != null && existing.id != pack.id) {
          throw ArgumentError(
            'Sender "$sender" is claimed by both ${existing.id} and ${pack.id}',
          );
        }
        _bySender[key] = pack;
      }
    }
  }

  final _bySender = <String, ParserPack>{};

  /// The pack for [sender], or `null` if the message should be ignored.
  ParserPack? packFor(String sender) => _bySender[normalise(sender)];

  /// Sender IDs compare case-insensitively and ignore surrounding spaces.
  static String normalise(String sender) => sender.trim().toUpperCase();
}

/// Parses messages from the user's selected accounts.
class SmsParser {
  /// Creates a parser for the selected [packs] (one per ticked account).
  SmsParser(Iterable<ParserPack> packs) : _filter = SenderFilter(packs);

  final SenderFilter _filter;

  /// Parses [message] into a [ParsedTransaction], an [Unmatched] message
  /// for the review inbox, or [Ignored] when the sender is not selected.
  ParseResult parse(SmsMessage message) {
    final pack = _filter.packFor(message.sender);
    if (pack == null) return const Ignored();
    final rawHash = hashMessageBody(message.body);

    for (final rule in pack.rules) {
      final match = rule.pattern.firstMatch(message.body);
      if (match == null) continue;
      return _build(pack, rule, match, message, rawHash);
    }
    return Unmatched(
      packId: pack.id,
      message: message,
      rawHash: rawHash,
      reason: 'No rule in ${pack.id} ${pack.version} matched',
    );
  }

  ParseResult _build(
    ParserPack pack,
    PackRule rule,
    RegExpMatch match,
    SmsMessage message,
    String rawHash,
  ) {
    String? group(String name) {
      if (!match.groupNames.contains(name)) return null;
      final value = match.namedGroup(name)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    Unmatched fail(String reason) => Unmatched(
      packId: pack.id,
      message: message,
      rawHash: rawHash,
      reason: '${pack.id}/${rule.id}: $reason',
    );

    final amountText = group('amount');
    final amount = amountText == null ? null : parseMinorUnits(amountText);
    if (amount == null) return fail('unreadable amount "$amountText"');

    int? optionalMoney(String name) {
      final text = group(name);
      return text == null ? null : parseMinorUnits(text);
    }

    final fee = optionalMoney('fee');
    final balance = optionalMoney('balance');
    if (group('fee') != null && fee == null) return fail('unreadable fee');
    if (group('balance') != null && balance == null) {
      return fail('unreadable balance');
    }

    var direction = rule.direction;
    if (direction == null) {
      final text = group('direction')?.toLowerCase();
      direction = text == null ? null : rule.directionValues[text];
      if (direction == null) return fail('unknown direction "$text"');
    }

    var time = message.receivedAt.toUtc();
    final timeText = group('time');
    final format = rule.timeFormat;
    if (timeText != null && format != null) {
      final parsed = format.parse(timeText, utcOffset: pack.utcOffset);
      if (parsed == null) return fail('unreadable time "$timeText"');
      time = parsed;
    }

    return ParsedTransaction(
      packId: pack.id,
      packVersion: pack.version,
      ruleId: rule.id,
      type: rule.type,
      direction: direction,
      amountMinor: amount,
      currency: pack.currency,
      time: time,
      timeFromMessage: timeText != null,
      rawHash: rawHash,
      feeMinor: fee,
      balanceMinor: balance,
      receipt: group('receipt'),
      // Names are often printed with two spaces between words.
      counterparty: group('counterparty')?.replaceAll(_spaces, ' '),
      account: group('account'),
    );
  }
}

final _spaces = RegExp(r'\s+');

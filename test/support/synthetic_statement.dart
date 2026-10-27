/// Synthetic M-Pesa statement rows for tests. Every name, number and
/// receipt is made up; never paste a real statement here. The details
/// follow the real statement's wording, such as
/// `Customer Transfer to - 0700***001 JANE DOE`.
library;

/// One synthetic statement row, in East Africa Time.
class SyntheticEntry {
  /// Creates an entry. Give one of [paidIn] or [withdrawn], in cents.
  const SyntheticEntry(
    this.receipt,
    this.time,
    this.details, {
    this.paidIn = 0,
    this.withdrawn = 0,
    this.status = 'Completed',
  });

  /// Receipt number.
  final String receipt;

  /// `yyyy-MM-dd HH:mm:ss`.
  final String time;

  /// Details column text.
  final String details;

  /// Paid in, cents.
  final int paidIn;

  /// Withdrawn, cents (positive).
  final int withdrawn;

  /// Transaction status.
  final String status;
}

/// Formats cents as `1,234.50`, negative with a leading minus.
String money(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  return '$sign$whole.${(abs % 100).toString().padLeft(2, '0')}';
}

/// Opening balance of [syntheticOctober], in cents.
const syntheticOpening = 500000;

/// A synthetic October: every row type, a fee row per payment that has
/// one, and a failed row.
const syntheticOctober = [
  SyntheticEntry(
    'TJA0000003',
    '2026-10-26 08:02:10',
    'Funds received from - 0700***002 JOHN KAMAU',
    paidIn: 200000,
  ),
  SyntheticEntry(
    'TJA0000001',
    '2026-10-26 09:15:42',
    'Customer Transfer to - 0700***001 JANE DOE',
    withdrawn: 150000,
  ),
  SyntheticEntry(
    'TJA0000001',
    '2026-10-26 09:15:42',
    'Customer Transfer of Funds Charge',
    withdrawn: 1500,
  ),
  SyntheticEntry(
    'TJA0000002',
    '2026-10-26 11:30:05',
    'Pay Bill Online to 888880 - EXAMPLE POWER LTD Acc. 1234567890',
    withdrawn: 120000,
  ),
  SyntheticEntry(
    'TJA0000002',
    '2026-10-26 11:30:05',
    'Pay Bill Charge',
    withdrawn: 1500,
  ),
  SyntheticEntry(
    'TJA0000004',
    '2026-10-26 13:45:00',
    'Merchant Payment Online to 5000001 - EXAMPLE GROCERS',
    withdrawn: 35000,
  ),
  SyntheticEntry(
    'TJA0000005',
    '2026-10-26 17:10:30',
    'Customer Withdrawal At Agent Till 123456 - EXAMPLE AGENT SHOP NAIROBI',
    withdrawn: 100000,
  ),
  SyntheticEntry(
    'TJA0000005',
    '2026-10-26 17:10:30',
    'Withdrawal Charge',
    withdrawn: 2900,
  ),
  SyntheticEntry(
    'TJA0000006',
    '2026-10-26 19:00:00',
    'Airtime Purchase',
    withdrawn: 10000,
  ),
  SyntheticEntry(
    'TJA0000011',
    '2026-10-26 20:00:00',
    'Customer Transfer to - 0700***003 MARY WANJIRU',
    withdrawn: 50000,
    status: 'Failed',
  ),
  SyntheticEntry(
    'TJA0000010',
    '2026-10-27 08:05:00',
    'Business Payment from 400001 - EXAMPLE SACCO via API',
    paidIn: 500000,
  ),
];

/// Closing balance of [syntheticOctober], in cents.
const syntheticClosing = 779100;

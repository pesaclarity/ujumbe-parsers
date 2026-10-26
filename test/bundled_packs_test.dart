import 'dart:io';

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import '../tool/bundle_packs.dart';
import '../tool/src/pack_files.dart';

void main() {
  test('the bundled M-Pesa pack loads and parses a message', () {
    final mpesa = loadBundledPack('mpesa');
    expect(mpesa.id, 'mpesa');
    expect(mpesa.senders, contains('MPESA'));

    final result = SmsParser([mpesa]).parse(
      SmsMessage(
        sender: 'MPESA',
        body:
            'TJA0000001 Confirmed. Ksh1,500.00 sent to JANE DOE 0700***001 '
            'on 26/10/26 at 9:15 AM. New M-PESA balance is Ksh3,250.00. '
            'Transaction cost, Ksh15.00.',
        receivedAt: DateTime.utc(2026, 10, 26, 6, 16),
      ),
    );
    expect(result, isA<ParsedTransaction>());
    final t = result as ParsedTransaction;
    expect(t.amountMinor, 150000);
    expect(t.receipt, 'TJA0000001');
  });

  test('every pack is bundled and loads', () {
    expect(bundledPackIds, containsAll(['im_bank', 'kcb', 'mpesa']));
    final packs = loadBundledPacks();
    expect(packs.map((p) => p.id), bundledPackIds);
    expect(() => SmsParser(packs), returnsNormally);
  });

  test('the bundled index matches packs/', () {
    final current = File(bundlePath).readAsStringSync();
    expect(
      current,
      renderBundle(packDirectories(Directory('packs'))),
      reason: 'Run: dart run tool/bundle_packs.dart',
    );
  });

  test('an unknown pack id is an error', () {
    expect(() => loadBundledPack('nope'), throwsArgumentError);
  });
}

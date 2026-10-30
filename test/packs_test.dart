import 'dart:io';

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';

import '../tool/src/pack_files.dart';

/// Every pack under packs/ must load and pass all of its fixtures.
void main() {
  final dirs = packDirectories(Directory('packs'));

  test('the starter packs are present', () {
    final names = dirs.map((d) => d.uri.pathSegments.reversed.skip(1).first);
    expect(names, containsAll(['mpesa', 'im_bank', 'kcb', 'equity']));
  });

  for (final dir in dirs) {
    test('pack ${dir.path} passes its fixtures', () {
      final loaded = PackDirectory.load(dir);
      final report = loaded.fixtures.run(loaded.pack);
      expect(report.failures, isEmpty);
    });
  }

  test('no two packs claim the same sender', () {
    final packs = [for (final d in dirs) PackDirectory.load(d).pack];
    expect(() => SmsParser(packs), returnsNormally);
  });
}

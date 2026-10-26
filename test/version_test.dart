import 'dart:io';

import 'package:test/test.dart';
import 'package:ujumbe/ujumbe.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('engineVersion matches pubspec.yaml', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(engineVersion, pubspec['version']);
  });

  test('compares by semantic version precedence', () {
    const ordered = [
      '0.1.0',
      '0.2.0-alpha',
      '0.2.0-alpha.1',
      '0.2.0-alpha.beta',
      '0.2.0-beta.2',
      '0.2.0-beta.11',
      '0.2.0',
      '0.10.0',
      '1.0.0',
    ];
    for (var i = 0; i < ordered.length; i++) {
      for (var j = 0; j < ordered.length; j++) {
        expect(
          compareVersions(ordered[i], ordered[j]).sign,
          i.compareTo(j),
          reason: '${ordered[i]} vs ${ordered[j]}',
        );
      }
    }
    expect(compareVersions('1.0.0+build.1', '1.0.0'), 0);
    expect(() => compareVersions('1.0', '1.0.0'), throwsFormatException);
  });
}

import 'dart:io';

import 'src/pack_files.dart';

/// Path of the generated page, relative to the repository root.
const examplesPath = 'docs/MESSAGES.md';

/// Writes [examplesPath]: every sample message in `packs/*/fixtures.yaml`,
/// by pack, with the rule that reads it. All samples are synthetic.
///
///     dart run tool/message_examples.dart          # regenerate
///     dart run tool/message_examples.dart --check  # fail if it is out of date
void main(List<String> args) {
  final check = args.contains('--check');
  if (args.any((a) => a != '--check')) {
    stderr.writeln('Usage: dart run tool/message_examples.dart [--check]');
    exitCode = 64;
    return;
  }

  final String page;
  try {
    page = renderExamples([
      for (final dir in packDirectories(Directory('packs')))
        PackDirectory.load(dir),
    ]);
  } on Exception catch (e) {
    stderr.writeln(e);
    exitCode = 1;
    return;
  }

  final file = File(examplesPath);
  if (check) {
    final current = file.existsSync() ? file.readAsStringSync() : null;
    if (current != page) {
      stderr.writeln(
        '$examplesPath is out of date. Run: dart run tool/message_examples.dart',
      );
      exitCode = 1;
    } else {
      stdout.writeln('$examplesPath is up to date.');
    }
    return;
  }
  file.writeAsStringSync(page);
  stdout.writeln('Wrote $examplesPath.');
}

/// Renders the page for [packs].
String renderExamples(List<PackDirectory> packs) {
  final out = StringBuffer()
    ..writeln('# Example messages')
    ..writeln()
    ..writeln(
      'Every sample message the packs are tested with, generated from '
      '`packs/*/fixtures.yaml` by `tool/message_examples.dart`. Do not edit; '
      'regenerate with `dart run tool/message_examples.dart`.',
    )
    ..writeln()
    ..writeln(
      'All samples are synthetic: fake names, masked fake numbers and '
      'made-up receipts, written in the shape of real alerts. "Review inbox" '
      'means no rule reads the message, so the person checks it once.',
    )
    ..writeln();
  for (final p in packs) {
    out.writeln('- [${p.pack.name}](#${_anchor(p.pack.name)})');
  }
  for (final p in packs) {
    final pack = p.pack;
    final rules = pack.rules.isEmpty
        ? 'none yet (review-only)'
        : pack.rules.map((r) => '`${r.id}`').join(', ');
    out
      ..writeln()
      ..writeln('## ${pack.name}')
      ..writeln()
      ..writeln(
        'Pack `${pack.id}` ${pack.version} · senders '
        '${pack.senders.map((s) => '`$s`').join(', ')} · rules $rules',
      );
    for (final sample in p.fixtures.samples) {
      final expected = sample.expected;
      final result = expected == null
          ? 'review inbox'
          : '`${expected['rule']}` · ${expected['direction'] == 'in' ? 'money in' : 'money out'}';
      out
        ..writeln()
        ..writeln('**${sample.name}** (`${sample.message.sender}` → $result)')
        ..writeln()
        ..writeln('```text')
        ..writeln(sample.message.body)
        ..writeln('```');
    }
  }
  return out.toString();
}

String _anchor(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 -]'), '')
    .replaceAll(' ', '-');

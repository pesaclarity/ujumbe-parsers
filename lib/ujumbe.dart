/// SMS parser packs and the parsing engine for Pesa Clarity.
///
/// Load the packs shipped with this package with [loadBundledPack], other
/// packs with [ParserPack.fromYaml] (or [PackVerifier.loadVerified] for
/// downloaded packs), then parse messages with [SmsParser]. Check over-the-air
/// pack releases with [PackUpdateVerifier].
///
/// Statement PDFs: the app extracts each page's words with their positions
/// ([StatementPage]); [detectStatementPack] picks the layout and
/// [StatementReader] reads it with a [StatementPack].
library;

import 'src/bundled_packs.dart';
import 'src/pack.dart';
import 'src/pack_updates.dart';
import 'src/parser.dart';
import 'src/signing.dart';
import 'src/statements/page_text.dart';
import 'src/statements/statement_pack.dart';
import 'src/statements/statement_reader.dart';

export 'src/bundled_packs.dart';
export 'src/fixtures.dart';
export 'src/money.dart' show parseMinorUnits;
export 'src/pack.dart';
export 'src/pack_updates.dart';
export 'src/parser.dart';
export 'src/signing.dart';
export 'src/statements/bundled_statement_packs.dart';
export 'src/statements/page_text.dart';
export 'src/statements/statement_fixtures.dart';
export 'src/statements/statement_pack.dart';
export 'src/statements/statement_reader.dart';
export 'src/statements/table_layout.dart';
export 'src/time_format.dart';
export 'src/version.dart';

# ujumbe-parsers

SMS parser packs and the pure Dart engine that reads them (and M-Pesa statements), for [Pesa Clarity](https://github.com/pesaclarity/docs). Each institution (M-Pesa, Airtel Money, Co-operative Bank, Equity, I&M, KCB, Loop, Standard Chartered and, with your help, many more) gets a YAML pack of regex rules with synthetic sample messages. The engine reads only the senders a user has selected, turns each message into a typed transaction with amounts in integer cents, keeps a hash instead of the raw text, drops messages a pack knows are not transactions (such as a declined card payment), and sends anything else it cannot read to the user's review inbox. It has no Flutter dependency, so it runs in phone isolates and with plain Dart on any machine.

**Codename:** ujumbe, Swahili for "message".

**Status:** pre-alpha. The pack format may still change before 1.0.

The product spec and brand live in [pesaclarity/docs](https://github.com/pesaclarity/docs); see "SMS parser engine" and "Rules that keep the numbers honest".

## Quick start

Needs the Dart SDK 3.8 or newer.

```sh
dart pub get
dart run tool/check_packs.dart   # validate every pack and run its fixtures
dart test
```

Depending on it from the app (pin a release tag):

```yaml
dependencies:
  ujumbe:
    git:
      url: https://github.com/pesaclarity/ujumbe-parsers
      ref: v0.1.0
```

Using the engine:

```dart
import 'package:ujumbe/ujumbe.dart';

final mpesa = loadBundledPack('mpesa'); // or ParserPack.fromYaml(yaml)
final parser = SmsParser([mpesa]); // only the accounts the user ticked

switch (parser.parse(SmsMessage(sender: from, body: text, receivedAt: at))) {
  case ParsedTransaction t:
    // Store t's fields, t.rawHash and t.dedupeKey; discard the raw text.
  case Unmatched u:
    // Known sender, no rule matched: hold for the review inbox.
  case KnownNotice n:
    // Known sender, known not to be a transaction (n.noticeId, such as
    // declined_card_payment): drop it, never store it or ask the user.
  case Ignored():
    // Not a selected sender: drop it, never store it.
}
```

`KnownNotice` is a subtype of `Ignored`, so code that predates notices drops them as it drops other senders' messages. Match it before `Ignored` to count notices, or to take a message an older pack left in the review inbox back out of it by `n.rawHash`.

Statements backfill history and check balances. The app extracts each page's words with their positions from the PDF (and handles its password); the engine picks the layout and reads it:

```dart
final pack = detectStatementPack(pages, loadBundledStatementPacks());
final statement = StatementReader(pack!).read(pages);
statement.transactions;        // same dedupeKey as the matching SMS
statement.openingBalanceMinor; // and closingBalanceMinor, periodStart, periodEnd
if (!statement.reconciles) {
  // statement.balanceBreaks and statement.unreadLines show the gap.
}
```

Over-the-air pack updates are checked before use; only correctly signed, compatible packs newer than the installed ones come back:

```dart
final updates = PackUpdateVerifier(pinnedPublicKeys);
final result = await updates.verify(
  indexBytes: indexJson,          // index.json from the release
  indexSignature: indexSig,       // index.json.sig
  packs: {'mpesa': PackDownload(packBytes, packSig)},
);
for (final update in result.accepted) {
  // Store update.packBytes and update.signature; use update.pack.
}
for (final rejection in result.rejected) {
  // rejection.reason: hashMismatch, signatureInvalid, notNewer, ...
}
```

A stored pack is verified again on load with `PackVerifier([...]).loadVerified(bytes, signature)`.

## Project layout

```
lib/
  ujumbe.dart            public API
  src/bundled_packs.dart load the packs shipped with the package
  src/bundled_packs.g.dart generated from packs/; do not edit
  src/pack.dart          pack model and validation
  src/parser.dart        sender filter, parsing, dedupe key, raw-text hash
  src/statements/        statement packs: positioned page text, table layout,
                         pack format, reader, fixtures and the typesetter
  src/fixtures.dart      runs a pack's samples; a pack is valid only if all pass
  src/signing.dart       Ed25519 pack signing and verification
  src/pack_updates.dart  signed pack index and over-the-air update checks
  src/version.dart       engine version and SemVer 2.0 comparison
  src/money.dart         amounts to integer minor units
  src/time_format.dart   locale-free date patterns for message times
packs/<institution>/
  pack.yaml              the rules
  fixtures.yaml          synthetic samples and expected fields
  statement.yaml         optional: how to read the institution's statement PDF
  statement_fixtures.yaml synthetic statements and what they must read as
schema/                  JSON Schema for the pack, fixture and statement files and the release index.json
tool/
  check_packs.dart       validate packs and run all fixtures
  bundle_packs.dart      regenerate lib/src/bundled_packs.g.dart (--check in tool/check)
  message_examples.dart  regenerate docs/MESSAGES.md (--check in tool/check)
  sign_pack.dart         sign a pack (and generate a signing key)
  build_release.dart     build and sign a release: packs, index.json and signatures
docs/MESSAGES.md         every sample message, by pack (generated)
docs/RELEASING.md        release steps, key custody and rotation
test/                    engine unit tests and a test over every pack
  support/               synthetic statement generators (text and positioned pages)
```

## Adding an institution

New banks, SACCOs and wallets are the main way to contribute. Every pack is gated by its own samples.

1. **Create the directory.** `packs/<id>/` where `<id>` is lower case with underscores, e.g. `co_op_bank` or `airtel_money`. The pack's `id` must match.
2. **Write `pack.yaml`.** Copy `packs/kcb/pack.yaml` as a start. Set `senders` to the exact sender IDs the institution uses, `currency` (for messages that print none), `utc_offset` and a `time_format`. If no real wording is known yet, `rules: []` makes a review-only pack: its senders are read and every message goes to the review inbox. Otherwise add one rule per message type (`sent`, `received`, `paybill`, `till`, `withdrawal`, `airtime`, `fuliza`, `fuliza_repayment`, `loan_repayment`, `reversal`, or `bank` for plain debit and credit alerts). Each rule's `pattern` is a regex using these named groups only:

   | Group | Meaning |
   | --- | --- |
   | `amount` | Required. Digits with optional commas and decimals; becomes integer cents |
   | `receipt` | The institution's reference |
   | `direction` | Captured word such as "debited", mapped by `direction_values` (otherwise set a fixed `direction: in` or `out`) |
   | `counterparty` | The other party as printed |
   | `account` | The other side's phone, account or paybill reference, as printed (usually masked) |
   | `own_account` | The account holder's own account number, as printed (`0170*****4321`); tells two accounts at the same bank apart |
   | `currency` | The currency printed with the amount (`USD`, `EUR`; `Ksh` and `Kshs` read as KES). Without it, amounts are in the pack's `currency` |
   | `balance`, `fee` | Money after the transaction, and its cost |
   | `time` | Date and time as printed, read with `time_format` |
   | `owed` | A debt's total still owed after this message, such as Fuliza's outstanding amount |
   | `due` | When that debt is due, a date read with the rule's `due_format` |

   Rules are tried in order and the first match wins, so put specific shapes before general ones. When a message describes money moving on another institution's account, such as a bank's confirmation of an M-Pesa payment into it, set `institution` on the rule to that institution's pack id (`institution: mpesa`); the app then records it on that account, and the bank's own alert records the other side. Set `ignore_case: true` on a rule when the institution's wording changes case (`M-PESA` and `M-Pesa`). Sender IDs always compare without case, so `AirtelMoney` matches `airtelmoney`. If a message prints no time, the engine uses the time the phone received it. Then set `min_engine` if the pack uses a newer feature (see Engine versions below).

   **Notices.** Some messages from a selected sender are known not to be transactions: a declined card payment, a balance enquiry printed like a card transaction of KES 0. Rather than leave them in the review inbox, list them under `notices`, each with an `id` and a `pattern` (and `ignore_case` if needed):

   ```yaml
   notices:
     - id: declined_card_payment
       pattern: '^[A-Z]{3} ?[\d,]+\.\d{2} transaction made on KCB card [\d*]+ at .+? has been declined\.'
   ```

   Notices are tried only after every rule has failed to match, so a notice never hides a transaction. A match parses as a `KnownNotice` naming the notice's `id`, and the app drops it without storing it or asking the person. A notice reads no fields, so its pattern has no named groups. Anchor it with `^` and keep it narrow: unlike an unmatched message, a notice is never reviewed. Only add one for a shape known from real messages (as a synthetic sample), never for a guessed format.

   **Engine versions.** `min_engine` (a [SemVer 2.0](https://semver.org) version, default `0.1.0`) names the oldest engine that can read the pack. An older engine refuses the whole pack with a `PackEngineException` (over the air: a `PackRejection` with reason `engineTooOld`), so the phone keeps its current copy instead of reading the pack half-way. Pre-releases count as older than their release: `0.4.0-beta.1` does not meet `min_engine: 0.4.0`. The engine also refuses a pack whose `min_engine` is lower than a feature it uses needs, so set at least:

   | Feature | `min_engine` |
   | --- | --- |
   | `own_account` or `currency` group, or `rules: []` (review-only) | `0.2.0` |
   | `owed` or `due` group, or `due_format` | `0.3.0` |
   | `min_engine` on a rule | `0.3.1` (the first release after 0.3.0) |
   | `loan_repayment` type, `institution` on a rule, or `notices` | `0.4.0` |

   To add a rule for a newer engine without cutting older phones off the rest of the pack, give that rule its own `min_engine`. An older engine skips just that rule, lists it in `ParserPack.skippedRules`, and sends its messages to the review inbox; it reads the rest of the pack as usual.

3. **Write `fixtures.yaml`.** At least one sample per rule and per notice, plus samples that must stay `unmatched` (promotions, service notices, balance enquiries). Every field the rule captures must appear in `expect`; a field left out must parse as absent. A sample a notice must drop has `expect: {notice: <id>}`, with no other fields.
4. **Check it.** `dart run tool/check_packs.dart packs/<id>`, then `dart run tool/bundle_packs.dart` to ship it with the package, `dart run tool/message_examples.dart` to list its samples in [docs/MESSAGES.md](docs/MESSAGES.md), then `dart test`. Your editor can also validate against `schema/` through the `yaml-language-server` comment at the top of each file.
5. **Open a pull request** naming the institution and which message types you covered.

Bump a pack's `version` whenever its rules change. Maintainers sign released packs; contributors never need a key.

### Adding a statement layout

Statement PDFs are read from each word's position on the page, so columns and wrapped descriptions survive. The app extracts the words; a statement pack says how to read them. The full design is in the [statement import spec](https://github.com/pesaclarity/docs/blob/main/spec/statement-import.md).

1. **Write `packs/<id>/statement.yaml`.** Copy `packs/mpesa/statement.yaml`. Set `institution` to the SMS pack's id, `detect` patterns that match the first page, the `period`, and one entry under `columns` per table column, left to right, each with a `header` pattern. Amounts and balances are `align: right`. Use `money_in` and `money_out`, or one `amount` column with `amount: { negative_is: out }` or a `marker` column with `marker_out` and `marker_in` (`DR` and `CR`). `row_starts_with` names the column that is filled only on a row's first line, usually the date. Add `skip` patterns for page chrome, `fees` if charges are separate rows, and description `rules` to set the transaction type, `counterparty` and `account`.

   Statements laid out like KCB's (see `packs/kcb/statement.yaml`) need engine `0.5.0` (`min_engine: 0.5.0`) for these:

   | Field | What it does |
   | --- | --- |
   | `kind` and `value_date` columns | A transaction type printed in its own column, which rules (`kind:`) and `fees` (`kind:`) can match; a value date beside the date, not read. |
   | `direction` on a rule | The rule matches only rows moving money that way (`in` or `out`). |
   | `wrap: centered` | Cells are centred in their rows, so wrapped text sits above and below the line that starts a row. Rows are told apart by the space between them, and a row cut by a page break continues on the next page. |
   | `table_end` | A matching line, such as a page footer, ends the table on its page. |
   | `header_on_every_page` | Pages without the header row (a closing summary) are not part of the table. |
   | `max_word_height` | Words taller than this many times the page's median word height (large header text overlaid on the table) are dropped. |
   | `opening_balance`, `closing_balance` | Read the summary's balances (an `amount` group); the statement then reconciles only if its rows start and end at them. |

   A row that gives back an earlier row with the same reference (same type, or description, and amount, the other way) is read as its reversal, with the reference as its `account`.
2. **Write `statement_fixtures.yaml`.** Typeset synthetic pages: `columns` gives each column's left edge (or `">"` and its right edge for amounts), and each line is free text or a list of cells. Cover every rule, a row wrapping across a page break, and the expected balances.
3. **Check it** with `dart run tool/check_packs.dart packs/<id>` and `dart run tool/bundle_packs.dart`.

Never build fixtures from a real statement by copying its text. Write the rows by hand in the same shape, as for SMS samples.

### The synthetic-data rule

Never commit a real message, statement, name, phone number, account number or receipt. Rewrite a real message by hand into a synthetic one with the same shape: names like `JANE DOE` or `EXAMPLE GROCERS`, numbers like `0700***001` or `****0001`, receipts like `TJA0000001`, and round made-up amounts. A pull request that contains real data will be closed and its history purged, so please check before you push.

## Signing packs

Phones accept a downloaded pack only if its Ed25519 signature verifies against a key built into the app. The signature is detached: base64 of the signature over the exact bytes of `pack.yaml`, written to `pack.yaml.sig`.

```sh
dart run tool/sign_pack.dart --generate-key /secure/place/ujumbe.seed
dart run tool/sign_pack.dart --key-file /secure/place/ujumbe.seed packs/mpesa
# or: UJUMBE_SIGNING_KEY=<base64 seed> dart run tool/sign_pack.dart packs/mpesa
```

The tool refuses to sign a pack whose fixtures fail. Private keys stay outside the repo, in a hardware key or secrets manager; tests generate throwaway keys.

Releases are signed by a GitHub Actions workflow: pushing a `v*` tag runs `tool/build_release.dart` to sign each pack and write a signed `index.json` listing them, then uploads them to the GitHub release for phones to download. A pack that needs a newer engine sets `min_engine: x.y.z` in `pack.yaml`, and older apps skip it (see "Engine versions" under [Adding an institution](#adding-an-institution)). See [docs/RELEASING.md](docs/RELEASING.md) for the steps, key custody, rotation and where the app pins its keys.

## Regenerating generated files

Two files are generated from `packs/` and committed, so the package works without file access and reviewers can read every sample. `tool/check` (and so the pre-push hook) runs both generators with `--check` and fails, naming the command, when either is out of date. Regenerate, then commit the result with the change that caused it:

| Run | After you change | It rewrites |
| --- | --- | --- |
| `dart run tool/bundle_packs.dart` | any `packs/*/pack.yaml` or `packs/*/statement.yaml`, or add or remove a pack | `lib/src/bundled_packs.g.dart`, the byte-for-byte copy behind `loadBundledPack` and `loadBundledStatementPack` |
| `dart run tool/message_examples.dart` | any `packs/*/fixtures.yaml`, or a pack's `name`, `version`, `senders` or rule ids | `docs/MESSAGES.md`, every sample message by pack |

Both validate every pack first and write nothing if one is invalid. Engine changes under `lib/` need neither, unless they change how packs are read or what the pages show; if so, `tool/check --fast` tells you. Never edit either file by hand.

## Contributing

1. Branch from `dev`, which is where all work lands; `main` holds only released code.
2. Make each commit a [Conventional Commits](https://www.conventionalcommits.org) title (`feat: add Equity Bank pack`, `fix(engine): …`, `feat!: …` for a breaking change). Pull requests into `dev` are rebase-merged, so every commit lands as written and release-please reads each one for the next version and the changelog. Tidy history before review; no `fixup!` or `squash!` commits.
3. Run `tool/setup-hooks` once; every push then checks the titles and runs `tool/check`.
4. Open the pull request against `dev`.

Maintainers then promote `dev` to `main` through a pull request merged with a merge commit, release-please on `main` tags `vX.Y.Z`, and the tag signs and publishes the packs. See [docs/RELEASING.md](docs/RELEASING.md) for that flow and [CONTRIBUTING.md](CONTRIBUTING.md) for the rest of the ground rules.

## Testing

```sh
tool/setup-hooks     # once: run the checks before every push
tool/check --fast    # format, analyse, generated files, pack fixtures
tool/check           # all of that, plus dart test and the JSON Schema checks
```

Checks run on your machine, not on GitHub; see [CONTRIBUTING.md](CONTRIBUTING.md#checks-run-on-your-machine).

## Get involved

- **Star [the app](https://github.com/pesaclarity/pesaclarity-app)** so more people find a private money app that runs on their phone.
- The easiest way in: add a pack for a bank, Sacco or wallet you use. See [Adding an institution](#adding-an-institution); no Flutter needed.
- **Pick a first issue:** [good first issues](https://github.com/pesaclarity/ujumbe-parsers/issues?q=is%3Aopen+label%3A%22good+first+issue%22) or [help wanted](https://github.com/pesaclarity/ujumbe-parsers/issues?q=is%3Aopen+label%3A%22help+wanted%22).
- **Read [CONTRIBUTING.md](CONTRIBUTING.md)** before your first pull request. Never include real messages, statements or phone numbers.

## Licence

Apache-2.0, see [LICENSE](LICENSE). Packs and fixtures are under the same licence so banks, fintechs and other projects can use them freely. The Pesa Clarity name and logo are trademarks and are not covered by this licence.

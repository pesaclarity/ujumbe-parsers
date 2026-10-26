# ujumbe-parsers

SMS parser packs and the pure Dart engine that reads them, for [Pesa Clarity](https://github.com/pesaclarity/docs). Each institution (M-Pesa, I&M, KCB and, with your help, many more) gets a YAML pack of regex rules with synthetic sample messages. The engine reads only the senders a user has selected, turns each message into a typed transaction with amounts in integer cents, keeps a hash instead of the raw text, and sends anything it cannot read to the user's review inbox. It has no Flutter dependency, so it runs in phone isolates and in CI with plain Dart.

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
  case Ignored():
    // Not a selected sender: drop it, never store it.
}
```

Downloaded packs are verified before use:

```dart
final verifier = PackVerifier([trustedPublicKey]);
final pack = await verifier.loadVerified(packBytes, signatureBase64);
```

## Project layout

```
lib/
  ujumbe.dart            public API
  src/bundled_packs.dart load the packs shipped with the package
  src/bundled_packs.g.dart generated from packs/; do not edit
  src/pack.dart          pack model and validation
  src/parser.dart        sender filter, parsing, dedupe key, raw-text hash
  src/fixtures.dart      runs a pack's samples; a pack is valid only if all pass
  src/signing.dart       Ed25519 pack signing and verification
  src/money.dart         amounts to integer minor units
  src/time_format.dart   locale-free date patterns for message times
packs/<institution>/
  pack.yaml              the rules
  fixtures.yaml          synthetic samples and expected fields
schema/                  JSON Schema for pack.yaml and fixtures.yaml
tool/
  check_packs.dart       validate packs and run all fixtures
  bundle_packs.dart      regenerate lib/src/bundled_packs.g.dart (--check in CI)
  sign_pack.dart         sign a pack (and generate a signing key)
test/                    engine unit tests and a test over every pack
```

## Adding an institution

New banks, SACCOs and wallets are the main way to contribute. Every pack is gated by its own samples.

1. **Create the directory.** `packs/<id>/` where `<id>` is lower case with underscores, e.g. `equity` or `airtel_money`. The pack's `id` must match.
2. **Write `pack.yaml`.** Copy `packs/kcb/pack.yaml` as a start. Set `senders` to the exact sender IDs the institution uses, `currency`, `utc_offset` and a `time_format`. Then add one rule per message type (`sent`, `received`, `paybill`, `till`, `withdrawal`, `airtime`, `fuliza`, `fuliza_repayment`, `reversal`, or `bank` for plain debit and credit alerts). Each rule's `pattern` is a regex using these named groups only:

   | Group | Meaning |
   | --- | --- |
   | `amount` | Required. Digits with optional commas and decimals; becomes integer cents |
   | `receipt` | The institution's reference |
   | `direction` | Captured word such as "debited", mapped by `direction_values` (otherwise set a fixed `direction: in` or `out`) |
   | `counterparty` | The other party as printed |
   | `account` | Phone, account or paybill reference, as printed (usually masked) |
   | `balance`, `fee` | Money after the transaction, and its cost |
   | `time` | Date and time as printed, read with `time_format` |

   Rules are tried in order and the first match wins, so put specific shapes before general ones. If a message prints no time, the engine uses the time the phone received it.
3. **Write `fixtures.yaml`.** At least one sample per rule, plus samples that must stay `unmatched` (promotions, notices, balance enquiries). Every field the rule captures must appear in `expect`; a field left out must parse as absent.
4. **Check it.** `dart run tool/check_packs.dart packs/<id>`, then `dart run tool/bundle_packs.dart` to ship it with the package, then `dart test`. Your editor can also validate against `schema/` through the `yaml-language-server` comment at the top of each file.
5. **Open a pull request** naming the institution and which message types you covered.

Bump a pack's `version` whenever its rules change. Maintainers sign released packs; contributors never need a key.

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

TODO: release pipeline (which key, where signed packs are published, how the app fetches them).

## Testing

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart run tool/bundle_packs.dart --check
dart run tool/check_packs.dart
dart test
```

CI runs the same steps on every pull request, and also validates the packs against the JSON Schema.

## Licence

Apache-2.0, see [LICENSE](LICENSE). Packs and fixtures are under the same licence so banks, fintechs and other projects can use them freely. The Pesa Clarity name and logo are trademarks and are not covered by this licence.

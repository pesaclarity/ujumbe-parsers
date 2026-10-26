# Changelog

All notable changes to this package are listed here. Versions follow [semantic versioning](https://semver.org); until 1.0 a minor version may break the pack format or the API.

## Unreleased

- `MpesaStatementParser` reads the text of an M-Pesa full statement (extracted from the PDF by the app) into transactions with the same dedupe key as SMS, folds fee rows into their payments, and reports the statement period, opening and closing balances, and any balance that does not follow from the row before it.

## 0.1.0

First release, for the Pesa Clarity app to depend on by git tag.

- Pack format (schema 1) with JSON Schema for `pack.yaml` and `fixtures.yaml`.
- Parsing engine: sender filter, first-match rules, amounts in integer cents, locale-free message times, SHA-256 of the raw text, and a dedupe key shared with statement imports.
- Fixture runner; a pack is valid only when all its synthetic samples pass.
- Ed25519 pack signing and verification for downloaded packs.
- Starter packs for M-Pesa, I&M Bank and KCB.
- Packs ship inside the package: `loadBundledPack`, `loadBundledPacks` and `bundledPackSources`, generated from `packs/` by `tool/bundle_packs.dart`.

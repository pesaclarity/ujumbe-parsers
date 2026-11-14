# Changelog

All notable changes to this package are listed here. Versions follow [semantic versioning](https://semver.org); until 1.0 a minor version may break the pack format or the API.

## [0.2.0](https://github.com/pesaclarity/ujumbe-parsers/compare/v0.1.0...v0.2.0) (2026-11-14)


### Features

* add Airtel Money as a review-only pack ([#23](https://github.com/pesaclarity/ujumbe-parsers/issues/23)) ([cc36266](https://github.com/pesaclarity/ujumbe-parsers/commit/cc36266ee8d3f8129324330a82389ad1b87a8242))
* add an Equity Bank pack ([#19](https://github.com/pesaclarity/ujumbe-parsers/issues/19)) ([ae48f0e](https://github.com/pesaclarity/ujumbe-parsers/commit/ae48f0e52da655a25c501a1bb431a916a803dd2b))
* add Loop as a review-only pack and list every sample message ([#21](https://github.com/pesaclarity/ujumbe-parsers/issues/21)) ([15dbbd2](https://github.com/pesaclarity/ujumbe-parsers/commit/15dbbd2088038ba2baab7cd5b3c8002d3d5774a4))
* promote dev to main (currency and own account from each message) ([79b08ed](https://github.com/pesaclarity/ujumbe-parsers/commit/79b08ed02bb29c7faa54c0a8e99dd7cee65cfc85))
* read more M-PESA and KCB message shapes ([#17](https://github.com/pesaclarity/ujumbe-parsers/issues/17)) ([b7dacf4](https://github.com/pesaclarity/ujumbe-parsers/commit/b7dacf4ca57b2a41769d1f220239811af731b2de))
* read the currency and own account from each message ([#34](https://github.com/pesaclarity/ujumbe-parsers/issues/34)) ([acf3dfd](https://github.com/pesaclarity/ujumbe-parsers/commit/acf3dfdd3dc798c9a1f80901b1f63f5b7da8a5b4))
* read the total Fuliza owed and its due date ([#42](https://github.com/pesaclarity/ujumbe-parsers/issues/42)) ([492ee2f](https://github.com/pesaclarity/ujumbe-parsers/commit/492ee2f621b82af67be9ca7b139be04652efa060))
* standard chartered card payments ([#38](https://github.com/pesaclarity/ujumbe-parsers/issues/38)) ([e744805](https://github.com/pesaclarity/ujumbe-parsers/commit/e74480501a73af012f6c7b6dc0857f959aba5165))
* standard chartered deposit alerts ([#37](https://github.com/pesaclarity/ujumbe-parsers/issues/37)) ([98bf68e](https://github.com/pesaclarity/ujumbe-parsers/commit/98bf68ec67f73c87ff6ed46ae6182f84db824f74))

## 0.1.0

First release, for the Pesa Clarity app to depend on by git tag.

- Pack format (schema 1) with JSON Schema for `pack.yaml` and `fixtures.yaml`.
- Parsing engine: sender filter, first-match rules, amounts in integer cents, locale-free message times, SHA-256 of the raw text, and a dedupe key shared with statement imports.
- Fixture runner; a pack is valid only when all its synthetic samples pass.
- Ed25519 pack signing and verification for downloaded packs.
- Starter packs for M-Pesa, I&M Bank and KCB.
- Packs ship inside the package: `loadBundledPack`, `loadBundledPacks` and `bundledPackSources`, generated from `packs/` by `tool/bundle_packs.dart`.
- Statement packs (`packs/<id>/statement.yaml`, schema 1, with JSON Schema): read statement PDFs from positioned words. `readTable` rebuilds the table from the header row (multi-word headers, right-aligned amounts, wrapped cells, rows across page breaks, skipped page chrome); `StatementReader` turns rows into transactions with the SMS dedupe key, folds fee rows into their payment, and checks every balance; `detectStatementPack` picks the layout.
- The M-Pesa statement as the first statement pack, with rules for the wording of the real statement (transfers, Pochi la Biashara, bank transfers in and out, unit trusts, M-Shwari, bundles, Fuliza).
- Column boundaries follow the gutters in the table body, so headers centred over their columns work; a column can carry a value `pattern`, and lines far below a row are not taken as its continuation, so page footers stay out.
- Rows that share a second are put in the order their balances follow, since statements print them in no reliable order.
- Removed `MpesaStatementParser`, the text-only reader the statement packs replace.
- Statement fixtures typeset synthetic rows into pages (`typesetPage`), run by `tool/check_packs.dart`; statement packs are bundled as `bundledStatementPackSources`.
- `MessageTimeFormat(..., dateOnly: true)` for dates without a time, such as a statement period.
- Signed pack releases for over-the-air updates: a signed `index.json` (with JSON Schema) lists each pack's version, minimum engine version, SHA-256 and signature file.
- `PackUpdateVerifier` accepts only packs that are correctly signed, match the index, suit this engine and are newer than the installed copy, and gives a typed `PackRejectionReason` for the rest.
- Optional `min_engine` field in `pack.yaml`; `engineVersion` and `compareVersions`.
- `tool/build_release.dart` and a release workflow that signs with the `UJUMBE_SIGNING_KEY` secret and uploads the assets on `v*` tags.
- Signing tools no longer echo a malformed key in their error output.

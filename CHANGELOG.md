# Changelog

All notable changes to this package are listed here. Versions follow [semantic versioning](https://semver.org); until 1.0 a minor version may break the pack format or the API.

## Unreleased

- Signed pack releases for over-the-air updates: a signed `index.json` (with JSON Schema) lists each pack's version, minimum engine version, SHA-256 and signature file.
- `PackUpdateVerifier` accepts only packs that are correctly signed, match the index, suit this engine and are newer than the installed copy, and gives a typed `PackRejectionReason` for the rest.
- Optional `min_engine` field in `pack.yaml`; `engineVersion` and `compareVersions`.
- `tool/build_release.dart` and a release workflow that signs with the `UJUMBE_SIGNING_KEY` secret and uploads the assets on `v*` tags.
- Signing tools no longer echo a malformed key in their error output.

## 0.1.0

First release, for the Pesa Clarity app to depend on by git tag.

- Pack format (schema 1) with JSON Schema for `pack.yaml` and `fixtures.yaml`.
- Parsing engine: sender filter, first-match rules, amounts in integer cents, locale-free message times, SHA-256 of the raw text, and a dedupe key shared with statement imports.
- Fixture runner; a pack is valid only when all its synthetic samples pass.
- Ed25519 pack signing and verification for downloaded packs.
- Starter packs for M-Pesa, I&M Bank and KCB.
- Packs ship inside the package: `loadBundledPack`, `loadBundledPacks` and `bundledPackSources`, generated from `packs/` by `tool/bundle_packs.dart`.

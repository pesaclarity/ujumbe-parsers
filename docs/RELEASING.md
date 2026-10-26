# Releasing packs

Each release of this package is also an over-the-air pack release: phones download the signed packs from the GitHub release and use them without waiting for an app update. This page covers how a release is made, how the signing key is kept, how to rotate it, and how the app trusts it.

## What a release contains

`tool/build_release.dart` writes these files, and the release workflow uploads them as assets of the GitHub release:

| File | What |
| --- | --- |
| `<id>.pack.yaml` | The exact bytes of `packs/<id>/pack.yaml` |
| `<id>.pack.yaml.sig` | Base64 Ed25519 signature over that file |
| `index.json` | Every pack's id, version, minimum engine version (`min_engine`), SHA-256 and asset names; see `schema/index.schema.json` |
| `index.json.sig` | Base64 Ed25519 signature over `index.json` |

A phone fetches `index.json` and its signature, calls `PackUpdateVerifier.verifyIndex`, asks `offered` which packs are worth downloading, fetches those, and passes everything to `PackUpdateVerifier.verify`. A pack is accepted only when:

1. the index signature verifies against a key pinned in the app;
2. the pack's SHA-256 matches the signed index;
3. the pack's own signature verifies against a pinned key;
4. this engine is at least the pack's `min_engine`;
5. the pack is newer than the copy on the phone (the bundled copy by default), so a replayed old release cannot downgrade it;
6. the pack parses and its id, version and `min_engine` agree with the index.

Everything else comes back as a `PackRejection` with a typed `PackRejectionReason`. The app stores accepted packs with their signatures and verifies them again on load with `PackVerifier.loadVerified`.

## Making a release

1. Bump `version` in `pubspec.yaml` and `engineVersion` in `lib/src/version.dart` together (a test checks they match), and add a `CHANGELOG.md` entry.
2. Bump the `version` of every pack whose rules changed. If a pack relies on an engine feature added in this release, set its `min_engine` to this version, so older apps skip it instead of failing on it.
3. Run the checks in the README and merge to `main`.
4. Tag the merge commit and push the tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

5. The **Release packs** workflow runs every CI check, confirms the tag matches `pubspec.yaml`, builds and signs the release with the `UJUMBE_SIGNING_KEY` secret, validates `index.json` against its schema and uploads the assets. It prints the public key it signed with; check it is one the app pins.

To re-run a release (for example after fixing the secret), start **Release packs** by hand from the Actions tab and pick the tag, not a branch, under "Use workflow from". The workflow never runs on pull requests, so code from a fork cannot reach the key.

The workflow job uses the `release` environment. Add required reviewers to that environment in the repository settings so that a second maintainer approves each signing run.

## Key custody

The private key is a 32-byte Ed25519 seed, stored base64-encoded. It never enters the repository (`.gitignore` blocks `*.seed` and `.env`) and no tool prints it.

- **The master copy** lives offline: on a hardware key or in the organisation's secrets manager, with access limited to release maintainers. Keep one sealed backup in a second place.
- **CI** gets a copy only as the repository secret `UJUMBE_SIGNING_KEY`, exposed to the one step that signs.
- **Signing locally**, if CI is unavailable, reads the key from a file outside the repo or from the environment:

  ```sh
  dart run tool/build_release.dart --key-file /secure/place/ujumbe.seed --out build/release
  ```

Generate a new key on a trusted machine:

```sh
dart run tool/sign_pack.dart --generate-key /secure/place/ujumbe.seed
```

It prints the public key, which is safe to share.

If the key may have leaked, treat it as compromised: rotate at once (below), and ship an app update that drops the old public key.

## Rotating the key

`PackVerifier` and `PackUpdateVerifier` accept any of several pinned keys, so rotation needs no flag day:

1. Generate a new key and store it as above.
2. Add its public key to the app's pinned list, next to the old one, and ship that app update.
3. Once most phones run that update, replace `UJUMBE_SIGNING_KEY` with the new seed. Releases are now signed with the new key; updated phones accept them.
4. In a later app update, remove the old public key. Destroy the old seed.

Phones that never update keep trusting only the old key, so after step 3 they stop receiving pack updates but keep working with the packs they have.

## Where the app pins public keys

The app ([pesaclarity-app](https://github.com/pesaclarity/pesaclarity-app)) compiles the trusted public keys into its source as a constant list of base64 strings and passes them to `PackUpdateVerifier`. The keys are never downloaded or read from settings, because a key that can be swapped at run time protects nothing. Changing the list is a reviewed code change that ships in an app release.

Packs bundled inside the package need no signature check; they arrive in the app binary, which has its own signing.

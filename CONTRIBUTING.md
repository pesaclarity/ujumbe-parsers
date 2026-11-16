# Contributing to ujumbe-parsers

Thank you for helping. The code of conduct, security policy and general contribution terms are the organisation defaults in [pesaclarity/.github](https://github.com/pesaclarity/.github). Please report security issues privately as described there, not in public issues.

## Setup

Install the Dart SDK 3.8 or newer, then:

```sh
dart pub get
```

## Checks run on your machine

GitHub only builds and publishes releases; the checks run locally. Once per clone, turn on the git hook:

```sh
tool/setup-hooks
```

Then every `git push` first checks that the titles of the commits being pushed follow Conventional Commits, then runs the full `tool/check`: format, analyse, generated files, pack fixtures, `dart test` and the JSON Schema checks. Run `tool/check` by hand at any time, or `tool/check --fast` to skip the tests and schema checks while you work. The schema checks need [uv](https://docs.astral.sh/uv/) or `check-jsonschema` on your PATH; without them they are skipped with a notice. In an emergency, push with `git push --no-verify`, then fix and re-run `tool/check`.

## Parser packs

Adding or fixing an institution's pack is the most useful contribution. Follow "Adding an institution" in the [README](README.md).

- Synthetic data only. Never commit a real message, name, phone number, account number or receipt, even partly masked.
- Every rule needs at least one sample, and a pack is accepted only when all its samples pass.
- Bump the pack's `version` when its rules change, and run `dart run tool/bundle_packs.dart` so the packaged copy matches.

## Engine changes

- Amounts stay as integer minor units; no `double` anywhere money is handled.
- Raw message text must not outlive parsing, except for unmatched messages waiting in the review inbox.
- Add or update tests with every change.

## Commits and pull requests

- Small, focused pull requests against `dev`, with a short description of what changed and why. `main` takes only `dev` and release pull requests (see [docs/RELEASING.md](docs/RELEASING.md)).
- Pull request titles follow [Conventional Commits](https://www.conventionalcommits.org): `feat: add Equity Bank pack`, `fix: …`, `feat!: …` for a breaking change. They set the next version and the changelog.
- Commit messages: one short line in the same Conventional Commits form, e.g. `feat: add Equity Bank pack` (the pre-push hook checks it).
- New dependencies need a reason in the pull request; the engine must stay free of Flutter.

## Releases

Maintainers cut releases and sign packs as described in [docs/RELEASING.md](docs/RELEASING.md). Contributors never need a signing key.

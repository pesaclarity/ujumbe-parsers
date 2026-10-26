# Contributing to ujumbe-parsers

Thank you for helping. The code of conduct, security policy and general contribution terms are the organisation defaults in [pesaclarity/.github](https://github.com/pesaclarity/.github). Please report security issues privately as described there, not in public issues.

## Setup

Install the Dart SDK 3.8 or newer, then:

```sh
dart pub get
```

## Before you open a pull request

```sh
dart format .
dart analyze --fatal-infos
dart run tool/check_packs.dart
dart test
```

All four must pass; CI runs the same checks.

## Parser packs

Adding or fixing an institution's pack is the most useful contribution. Follow "Adding an institution" in the [README](README.md).

- Synthetic data only. Never commit a real message, name, phone number, account number or receipt, even partly masked.
- Every rule needs at least one sample, and a pack is accepted only when all its samples pass.
- Bump the pack's `version` when its rules change.

## Engine changes

- Amounts stay as integer minor units; no `double` anywhere money is handled.
- Raw message text must not outlive parsing, except for unmatched messages waiting in the review inbox.
- Add or update tests with every change.

## Commits and pull requests

- Small, focused pull requests with a short description of what changed and why.
- Commit messages: one short line in the imperative, e.g. "Add Equity Bank pack".
- New dependencies need a reason in the pull request; the engine must stay free of Flutter.

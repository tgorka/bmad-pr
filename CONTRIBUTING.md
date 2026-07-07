# Contributing

## Development Setup

1. Requirements: `bash` ≥ 4, `git`, `jq`. Optional but recommended:
   `shellcheck` (CI enforces it), `gh` for manual end-to-end testing.
2. Clone; there is nothing to install — `tests/run.sh` vendors a pinned
   bats-core into `tests/.vendor/` on first run.
3. Verify the gate: `scripts/check.sh` should exit 0.
4. Enable the pre-commit hook: `git config core.hooksPath .githooks`.

## PR Flow

1. Create a feature branch off `main`.
2. Make changes following `AGENTS.md` conventions; add/update bats tests
   for any behavior change.
3. Run `scripts/check.sh` locally — must exit 0.
4. Add an entry under `## Unreleased` in `CHANGELOG.md` for user-visible
   changes.
5. Open a PR using the template at `.github/PULL_REQUEST_TEMPLATE.md`.
6. CI runs on push; green CI required. cubic.dev reviews PRs — address its
   findings or resolve them with a stated reason (this plugin dogfoods that
   exact cycle).

## Release Process

Manual and lightweight: collect `## Unreleased` into a version heading in
`CHANGELOG.md`, bump `version` in `.claude-plugin/plugin.json` and
`module.yaml`, tag `vX.Y.Z`, push the tag, create a GitHub Release.

## Code Style

See `AGENTS.md` (the single source of truth for conventions). Highlights:
`set -euo pipefail`, shellcheck-clean at warning severity, snake_case
functions, frozen exit-code contract, atomic ledger writes, no network in
tests.

# Changelog

## Unreleased

## 1.0.0 — 2026-07-06

Ground-up rewrite as a BMAD-style Claude Code plugin (bash + markdown; the
TypeScript/Bun CLI is archived at tag `v0-ts-cli`).

### Added

- Claude plugin packaging: `.claude-plugin/plugin.json` + marketplace
  manifest; skills `/bmad-pr`, `/bmad-pr-loop`, `/bmad-pr-setup`.
- Stacked PR shipping: story PRs open as drafts based on the previous
  story's open PR — `gt` native, `gh` emulated (explicit `--base`/`--head`),
  bare-git fallback; `retarget` repairs the stack after the parent merges.
- CI + reviewer monitoring: `watch` polls check buckets and the reviewer
  lifecycle (check-run or bot-review completion), with timeout/absent
  verdicts.
- Reviewer providers as config profiles: cubic.dev built in (configurable
  trigger, default `@cubic-dev re-review`; `PR score: N/10` contract),
  `generic` profile for CodeRabbit/Greptile/etc.
- Findings bridge: unresolved reviewer threads + failing checks become
  BMAD `[Review][Patch]` items in `_bmad-output/pr/<key>-findings.md`;
  `rereview --resolve-addressed` resolves exactly the checked-off threads
  and re-triggers the reviewer (SHA-deduped).
- After-review placement: quick-dev + dev-auto `workflow.on_complete`
  overrides and a bmad-loop `pre_commit_gate` plugin, installed by
  `/bmad-pr-setup`.
- Git-safety preflight ported from v0 (CH1/CH2/CH3/CH5) with bounded
  `--auto-fix`; `--dry-run` never mutates.
- Repo gate: `scripts/check.sh` (bash -n, shellcheck, manifest checks,
  77-test bats suite), pre-commit hook, GitHub Actions CI.

### Removed

- TypeScript/Bun implementation, Biome, changesets tooling (`v0-ts-cli`).

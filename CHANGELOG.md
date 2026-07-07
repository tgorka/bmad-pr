# Changelog

## Unreleased

### Added

- DW-1: PR body templates — `BMAD_PR_TEMPLATE` (default
  `.github/bmad-pr-template.md`) with literal `{{story}}`/`{{phase}}`/
  `{{artifact}}`/`{{parent_pr}}`/`{{run_id}}`/`{{timestamp}}` substitution
  (never shell-evaluated); `BMAD_PR_TITLE_FORMAT` (`bmad` | `conventional`),
  optional phase-emoji title prefix (`BMAD_PR_TITLE_EMOJI`), and
  `BMAD_PR_LABELS` applied on PR creation.
- DW-2: planning-phase stacks — `ship --planning` uses
  `<prefix>/planning/<phase>` branches and defaults the ledger key to
  `planning-<phase>`; planning PRs chain like story PRs.
- DW-3: `BMAD_PR_REMOTE` (push remote) and fork flows — an `upstream`
  remote becomes the base repo for all GitHub queries and `gh pr create`
  targets it with a fork-qualified head.
- DW-8: `BMAD_PR_STAGE_MODE=tracked` restricts the CH3 auto-fix to tracked
  modifications (`git add -u`).

### Changed

- DW-4: the CH2 refusal in gt-initialized repos now hints `gt continue` /
  `gt rebase --abort` (a raw `git rebase --continue` can desync gt).
- DW-5: ledger writes are best-effort durable (`sync -d` before and after
  the atomic rename).
- DW-6: `ledger_update` runs under a portable per-entry mkdir lock
  (concurrent worktree invocations no longer interleave read-modify-write).
- DW-9: CH1 auto-fix branch names carry the PID (`<sha>-<epoch>-<pid>`).
- DW-7 closed as superseded: idempotent ship/amend + re-review dedupe make
  re-running after an outage drain naturally; no queue state added.

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

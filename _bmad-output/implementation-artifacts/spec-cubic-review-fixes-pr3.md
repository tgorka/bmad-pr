---
title: 'Apply cubic review (PR #3): repo-root resolution, cwd plumbing, ENOENT-only catch, test-await fixes'
type: 'bugfix'
created: '2026-05-17'
status: 'done'
route: 'one-shot'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-bmad-pr-core-and-ledger.md'
---

# Apply cubic review (PR #3)

## Intent

**Problem:** cubic.dev's automated review of PR #3 surfaced 1 P1 + 7 P2 issues on the G1+G3 slice — a real bug (ledger written relative to caller's CWD, not the repo root), three plumbing gaps (`cwd` not forwarded into runner/driver calls), a refusal-vs-fail miscategorisation (unparseable stored URL was exit 1, spec says exit 2), an over-broad spawn-error catch (all errors mapped to exit 127, not just ENOENT), and three missing `await`s on `.rejects` test assertions.

**Approach:** Patch each finding in place on the same branch. Introduce a `resolveRepoRoot` helper that calls `git rev-parse --show-toplevel` and threads the result through every subsequent runner call and the ledger path. Add `RunnerOpts`/`DriverOpts` to `pr/types.ts` for shared typing. Tighten the runner's `isBinaryNotFound` to typed `code === "ENOENT"` first and a narrow textual fallback. Add focused tests for every new behavior (not-in-git-repo refusal, unparseable URL refusal under both default and `--dry-run`, ENOENT mapping via absolute non-existent path, driver `cwd` forwarding, end-to-end CLI-level `cwd` capture).

## Suggested Review Order

**Primary fix (cubic P1) — repo root resolution**

- New helper runs at the top of `execute()` before any driver call.
  [`bmad-pr.ts:resolveRepoRoot`](../../src/cli/bmad-pr.ts#L197)

- All subsequent calls thread `repoRoot` as `cwd`; ledger path is rooted on it.
  [`bmad-pr.ts:execute`](../../src/cli/bmad-pr.ts#L110)

**Cubic P2 — cwd plumbing through the driver**

- Every gh-driver function now accepts and forwards `DriverOpts`.
  [`gh-driver.ts:detectGhOnPath`](../../src/pr/gh-driver.ts#L4)
  [`gh-driver.ts:pushBranch`](../../src/pr/gh-driver.ts#L12)
  [`gh-driver.ts:createDraftPr`](../../src/pr/gh-driver.ts#L23)
  [`gh-driver.ts:editPrBody`](../../src/pr/gh-driver.ts#L43)

- Shared opts type lifted into `types.ts`.
  [`types.ts:DriverOpts`](../../src/pr/types.ts#L40)

**Cubic P2 — refuse vs fail**

- Unparseable stored PR URL is malformed-ledger input → refuse (exit 2), not fail.
  [`bmad-pr.ts:execute amend-path`](../../src/cli/bmad-pr.ts#L141)

**Cubic P2 — ENOENT-only catch**

- Prefer typed `code === "ENOENT"`; narrow textual fallback for Bun versions without `.code`.
  [`runner.ts:isBinaryNotFound`](../../src/pr/runner.ts#L15)

**Tests (cubic P2 await-fixes + new coverage)**

- Three `.rejects` assertions now properly awaited (cubic #6, #7, #8).
  [`ledger.test.ts:113`](../../src/pr/ledger.test.ts#L113)
  [`ledger.test.ts:268`](../../src/pr/ledger.test.ts#L268)
  [`gh-driver.test.ts:103`](../../src/pr/gh-driver.test.ts#L103)

- CLI harness captures `cwd` per call; new assertion that every driver/runner call sees `cwd=repoRoot`.
  [`bmad-pr.test.ts:Call type + harness`](../../src/cli/bmad-pr.test.ts#L8)

- New refusal tests: not-in-git-repo, unparseable URL (default + `--dry-run`).
  [`bmad-pr.test.ts:not inside a git repository`](../../src/cli/bmad-pr.test.ts#L290)

- New driver test: opts.cwd is forwarded into the runner for all four functions.
  [`gh-driver.test.ts:driver opts.cwd forwarding`](../../src/pr/gh-driver.test.ts#L125)

- New runner test: absolute non-existent path → exit 127 (deterministic, no PATH dependency).
  [`runner.test.ts:ENOENT spawn failure`](../../src/pr/runner.test.ts#L22)

## Review Findings Disposition

Adversarial review pass identified 10 follow-up items.

**Applied as patches in this commit:**
- Tighten `isBinaryNotFound` regex (medium)
- CLI test harness now captures `cwd` per call (medium)
- `resolveRepoRoot` rejects empty stdout from a misbehaving `git` (low)
- Hoist `DriverOpts` into `types.ts` (low)
- Runner ENOENT test uses absolute path, not PATH-style name (low)
- Dry-run unparseable-URL refusal now covered by a test (low)

**Rejected (by design):**
- macOS `/tmp` vs `/private/tmp` after `git rev-parse --show-toplevel` — that's git's standard symlink-resolution behavior; cross-ecosystem consistency wins over preserving the symlinked path.
- `detectBranch` still throws `fail`, not `refuse` — by that point `resolveRepoRoot` has already confirmed we're in a repo; rev-parse failing afterwards is unexpected, not a precondition.
- `realpathSync` on toplevel — out of scope; tests verify only the documented path.
- `detectBranch(runner, cwd)` style inconsistency with `DriverOpts` — stylistic, not functional.

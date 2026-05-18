---
title: 'G2 — Git-safety preflight (CH1/CH2/CH3/CH5) with --auto-fix'
type: 'feature'
created: '2026-05-17'
status: 'done'
baseline_commit: '40444cb32dc2a6e7f6af5e8c0c3838f909bd10b6'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/bmad-brainstorming.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-bmad-pr-core-and-ledger.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `bmad-pr` currently pushes and edits PRs without checking whether the local git state is sane — detached HEAD, mid-rebase/merge, an unrelated dirty tree, or a divergent remote turn successful runs into surprises or data loss. The brainstorming earmarked CH1–CH5 as v1 safety gates; this slice implements four (CH4 stays deferred to G4 with `gt`).

**Approach:** Add a `runPreflight` module — four detectors in order (CH1, CH2, CH3, CH5), first failure wins, each returns a typed `PreflightResult`. Wire it into the CLI right after `detectBranch` and before any state-changing op. Add `--auto-fix`: when set, attempts the three safe fixes (CH1 branch from HEAD, CH3 stage `_bmad-output/` only, CH5 `git pull --rebase`), re-runs preflight once. CH2 is refusal-only. Auto-fix scope is bounded: never touches non-BMAD files, never force-pushes, never resolves merge conflicts.

## Boundaries & Constraints

**Always:**
- Preflight runs after `detectBranch`, before the first state-changing call (push/create/edit). Runs under `--dry-run` too.
- All preflight git calls go through the injected `Runner` with `cwd: repoRoot`.
- Refusals follow BMAD AR22: exit 2, single line on stderr starting with `Refuse: `. When auto-fix is available, the hint ends with `Try: bmad-pr --auto-fix`.
- Auto-fix re-runs preflight after the fix; if anything still fails, refuse with that detector's hint. No recursion, no second auto-fix per invocation.
- CH3's auto-fix only stages paths under `_bmad-output/`. Never `git add -A`, never `git add .`.
- CH5 auto-fix on conflict: `git rebase --abort`, then refuse — never leave the repo half-rebased.

**Ask First:** (none — every contingency above is decidable from the matrix)

**Never:**
- No `git push --force` / `--force-with-lease`.
- No CH4 (`gt`-mid-restack) — deferred to G4.
- No CH6–CH14 (token/rate/remote/state chaos) — deferred per brainstorming.
- No interactive rebase resolution. CH2 always refuses, even with `--auto-fix`.
- No bypassing preflight via env var or hidden flag.

## I/O & Edge-Case Matrix

| Scenario | Trigger | Behavior |
|----------|---------|----------|
| CH1 refuse | `git rev-parse --abbrev-ref HEAD` returns `HEAD` | Exit 2; `Refuse: detached HEAD. Try: bmad-pr --auto-fix to branch from current HEAD.` |
| CH1 auto-fix | Same + `--auto-fix` | Run `git switch -c bmad-pr/<short-sha>-<unix-seconds>` (matches `^bmad-pr/[0-9a-f]{7,}-\d+$`); re-run preflight; proceed |
| CH2 mid-rebase | `.git/rebase-merge/` OR `.git/rebase-apply/` exists | Exit 2; `Refuse: interactive rebase in progress. Run: git rebase --continue (or --abort).` Auto-fix never tried |
| CH2 mid-merge | `.git/MERGE_HEAD` exists | Exit 2; `Refuse: merge in progress. Run: git merge --continue (or --abort).` Auto-fix never tried |
| CH3 refuse | `git status --porcelain` shows any path NOT under `_bmad-output/` | Exit 2; `Refuse: unstaged changes outside _bmad-output/. Try: bmad-pr --auto-fix to stage only _bmad-output/ paths.` |
| CH3 auto-fix happy | Same + `--auto-fix` AND only `_bmad-output/` changes remain after staging | `git add _bmad-output/`; re-run preflight; proceed |
| CH3 auto-fix residue | `--auto-fix` but non-BMAD changes remain | Exit 2; `Refuse: CH3 auto-fix could not clean tree; non-BMAD changes remain.` |
| CH3 tolerable | Tree dirty only inside `_bmad-output/` (with or without `--auto-fix`) | Preflight passes |
| CH5 refuse | Upstream configured AND `git rev-list --count HEAD..@{u}` > 0 | Exit 2; `Refuse: remote has new commits ahead of local. Try: bmad-pr --auto-fix to rebase first.` |
| CH5 auto-fix happy | Same + `--auto-fix`, rebase clean | `git pull --rebase`; re-run preflight; proceed |
| CH5 auto-fix conflict | Rebase non-zero exit | `git rebase --abort`; Exit 2; `Refuse: CH5 auto-fix produced conflicts; aborted. Resolve manually first.` Never push |
| No upstream | `@{u}` resolution fails | CH5 no-op; preflight passes |
| `--dry-run` happy | All detectors pass | stdout has `preflight: ok` then existing dry-run plan; exit 0 |
| `--dry-run` refusal | Any detector trips | Same refusal (exit 2); no state-changing probes run |

</frozen-after-approval>

## Code Map

- `src/pr/preflight.ts` -- `runPreflight(runner, opts)`, per-detector helpers, `runAutoFix`
- `src/pr/preflight.test.ts` -- table-driven detector tests with stubbed Runner
- `src/cli/bmad-pr.ts` -- `--auto-fix` flag; call preflight after `detectBranch`; route through `reportError`; emit `preflight: ok` in dry-run
- `src/cli/bmad-pr.test.ts` -- end-to-end test per matrix row touching CLI flow
- `src/pr/types.ts` -- `PreflightCode`, `PreflightResult`
- `.claude/skills/bmad-pr/SKILL.md` -- short "Preflight refusals" subsection so future Claudes don't second-guess CH1–CH5 hints
- `.changeset/bmad-pr-g2-preflight.md` -- minor-bump entry

## Tasks & Acceptance

**Execution:**
- [ ] `src/pr/types.ts` -- add `PreflightCode = "CH1"|"CH2"|"CH3"|"CH5"` and `PreflightResult = {ok:true} | {ok:false; code; hint; autoFixable}`
- [ ] `src/pr/preflight.ts` + test -- four detectors in declared order, first failure wins; `runAutoFix` for CH1/CH3/CH5 only
- [ ] `src/cli/bmad-pr.ts` + test -- parse `--auto-fix`; call preflight after `detectBranch`; on `autoFixable && --auto-fix` run fix + re-check once; emit `preflight: ok` under dry-run
- [ ] `.claude/skills/bmad-pr/SKILL.md` -- "Preflight refusals" subsection summarising the four cases
- [ ] `.changeset/bmad-pr-g2-preflight.md` -- minor-bump

**Acceptance Criteria:**
- Given detached HEAD, no `--auto-fix`: exit 2, stderr is the single CH1 hint exactly as in the matrix.
- Given detached HEAD + `--auto-fix`: runner is called with `git switch -c bmad-pr/<7+hex>-<digits>`, preflight re-runs and passes, the open/amend path proceeds.
- Given `.git/rebase-merge/` exists, with or without `--auto-fix`: exit 2 with the CH2 mid-rebase hint; auto-fix never attempted.
- Given a non-`_bmad-output/` path is dirty + `--auto-fix`: `git add _bmad-output/` is called exactly once; if the non-BMAD change remains, exit 2 with the CH3 residue hint.
- Given upstream is ahead + `--auto-fix` and `git pull --rebase` exits non-zero: `git rebase --abort` is invoked, exit 2 with the CH5 conflict hint, and **the runner is never asked to push or create**.
- Given all detectors pass + `--dry-run`: stdout begins with `preflight: ok` and exit 0.
- Given `bun run check` and `bunx tsc --noEmit`: both exit 0.

## Design Notes

**Order is intentional.** CH1 first because the others give weird signals on a detached HEAD. CH2 next because mid-rebase pollutes porcelain. CH3 third. CH5 last because it's the only one that costs a network round-trip (read of `@{u}` is local; we do not run `git fetch` by default — `--fetch-first` is a deferred follow-up).

**Auto-fix branch name (CH1):** `bmad-pr/<short-sha>-<unix-seconds>` — stable, unique, easy to grep, lands as a real branch via `git switch -c`.

**Result shape (frozen):**

```ts
type PreflightCode = "CH1" | "CH2" | "CH3" | "CH5";
type PreflightResult =
  | { ok: true }
  | { ok: false; code: PreflightCode; hint: string; autoFixable: boolean };
```

## Verification

**Commands:**
- `bun run check` -- expected: exits 0
- `bunx tsc --noEmit` -- expected: exits 0
- `bun src/cli/bmad-pr.ts --story 3.2 --phase dev-story --dry-run` -- expected: stdout begins with `preflight: ok`, exits 0 (when local state is clean)

## Suggested Review Order

**Detectors**

- The whole feature lives here — first failure wins; CH2 uses the real git-dir (worktree-safe); CH3 reads NUL-framed porcelain so filenames with newlines/quotes can't fool it.
  [`preflight.ts:runPreflight`](../../src/pr/preflight.ts#L7)

- Worktree-aware git-dir resolver (replaces hard-coded `<repoRoot>/.git`).
  [`preflight.ts:resolveGitDir`](../../src/pr/preflight.ts#L22)

- Porcelain `-z` parser (each record's xy + path; rename/copy advances one extra NUL field for the source).
  [`preflight.ts:parsePorcelainZ`](../../src/pr/preflight.ts#L80)

**Auto-fix path**

- CH5 calls `git pull --rebase`, then defensively re-runs CH2 to confirm the rebase didn't leave residue (and aborts if it did).
  [`preflight.ts:autoFixCH5`](../../src/pr/preflight.ts#L160)

- CH1 branches as `bmad-pr/<short-sha>-<unix-seconds>`.
  [`preflight.ts:autoFixCH1`](../../src/pr/preflight.ts#L120)

- CH3 stages only `_bmad-output/`. Never `-A`, never non-BMAD paths.
  [`preflight.ts:autoFixCH3`](../../src/pr/preflight.ts#L145)

**CLI wiring**

- Preflight gate runs after `detectBranch`, before any state-changing call. The post-fix branch strips the `Try: bmad-pr --auto-fix` tail so the user isn't told to retry a flag they already passed.
  [`bmad-pr.ts:preflightOrRefuse`](../../src/cli/bmad-pr.ts#L209)

- `--auto-fix` flag (and help text describing its scope).
  [`bmad-pr.ts:parseArgs`](../../src/cli/bmad-pr.ts#L256)

**Tests, skill, and follow-up**

- 19 preflight unit tests + 6 CLI-level end-to-end tests for the matrix, including a quoted-path regression guard and the CH5 conflict path that asserts NO push happens after `git rebase --abort`.
  [`preflight.test.ts`](../../src/pr/preflight.test.ts#L1)
  [`bmad-pr.test.ts:preflight describe`](../../src/cli/bmad-pr.test.ts#L450)

- SKILL.md "Preflight refusals" subsection so future Claudes don't second-guess CH1–CH5 hints.
  [`.claude/skills/bmad-pr/SKILL.md`](../../.claude/skills/bmad-pr/SKILL.md)

- Follow-up specs (G4 with CH4, plus the polish defers the review surfaced).
  [`deferred-work.md`](./deferred-work.md)

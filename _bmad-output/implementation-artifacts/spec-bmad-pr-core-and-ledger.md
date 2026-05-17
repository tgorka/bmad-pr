---
title: '/bmad-pr core CLI + stories-file PR ledger (G1+G3)'
type: 'feature'
created: '2026-05-17'
status: 'done'
baseline_commit: '0767fa501d3a789df871ce7fec3660a6e6b97ab0'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/bmad-brainstorming.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** BMAD steps produce artifacts that must be PR'd by hand today. The repo has no `src/`. We need the thinnest end-to-end slice: open a draft PR from the current branch via `gh`, and persist the URL into a stories-file ledger so later phases (dev-story, code-review, retro) can find and amend it.

**Approach:** A Bun TypeScript CLI `bmad-pr` driving `gh` only. Persist a `prs:` list in the frontmatter of `_bmad-output/stories/<epic>.<story>.md` via atomic tmp+rename writes. Defer everything else (`gt`, `hub`, plain `git`, preflight, stacking, `/bmad-next` hook, template engine) per `deferred-work.md`.

## Boundaries & Constraints

**Always:**
- Atomic tmp+rename for every write under `_bmad-output/`.
- Never `git add -A`, never force-push. Only `git push -u origin HEAD`.
- Refuse on trunk (`main` or `--trunk-branch` value); require an explicit feature branch.
- Refuse if `gh` is not on PATH.
- Validate `--story` matches `^\d+\.\d+$`; refuse otherwise.
- Refuse `--amend` if no matching ledger entry exists.
- New PRs are opened as drafts.
- All CLI output goes to stderr via a `logger` module (`noConsole` is a Biome error). The resulting PR URL is the one exception — printed to stdout on success.
- Filesystem-touching tests use `mkdtemp(path.join(os.tmpdir(), "bmad-pr-<concern>-"))` and never touch `_bmad-output/`.

**Ask First:**
- Malformed ledger entry (missing `url` or `status`): HALT with `BmadPrError`. Auto-amend on a valid entry proceeds silently per brainstorming D3 — no prompt.

**Never:**
- No `gt`, no `hub`, no plain-`git`-only PR path (deferred G1-follow-up / G4).
- No git-safety preflight beyond the trunk + `gh`-on-PATH refusals (G2).
- No PR body templating beyond the fixed body in Design Notes (G6).
- No config-file reading, no `/bmad-next` hook (G5).
- No `--wip`, `--auto-fix`, `--tool` flag in this slice.
- No cross-process file lock (CH14, deferred).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Open new PR | `--story 3.2 --phase dev-story`; ledger has no matching entry; branch `feat/x`; `gh` present | Push branch; `gh pr create --draft`; append entry to story file; exit 0; URL on stdout | N/A |
| Auto-amend | Same args; ledger has open entry for `{3.2, dev-story}` | Push branch; `gh pr edit <num> --body`; bump `lastAmendedAt`; exit 0 | N/A |
| Forced amend, no match | `--amend --story 3.2 --phase dev-story`; ledger empty | Exit 2; stderr hint: drop `--amend` to open one | Refuse |
| Refusals (no side effects) | (a) branch is trunk; (b) `gh` missing; (c) `--story` malformed; (d) malformed existing ledger entry | Exit 2; stderr: single-line actionable hint per case | Refuse |
| Dry run | `--dry-run` with any valid args | Print would-run commands + would-write ledger diff to stdout; exit 0; zero git/gh/file side effects | N/A |
| Story file absent / no frontmatter | `_bmad-output/stories/3.2.md` missing or has no `---` block | Create or upgrade file with `epic`, `story`, `prs:` frontmatter; preserve any existing body | N/A |

</frozen-after-approval>

## Code Map

- `src/cli/bmad-pr.ts` -- flag parsing, dispatch, exit codes
- `src/cli/bmad-pr.test.ts` -- end-to-end with mocked Runner + temp ledger
- `src/pr/gh-driver.ts` -- `detectGhOnPath`, `pushBranch`, `createDraftPr`, `editPrBody`
- `src/pr/gh-driver.test.ts` -- driver tests with stub Runner
- `src/pr/ledger.ts` -- `resolveStoryPath`, `loadLedger`, `findEntry`, `appendEntry`, `updateEntry`
- `src/pr/ledger.test.ts` -- temp-file tests for every matrix row touching the ledger
- `src/pr/runner.ts` -- `Bun.spawn` wrapper; exports `Runner` type for injection
- `src/pr/runner.test.ts` -- smoke test against `git --version`
- `src/pr/types.ts` -- `LedgerEntry`, `BmadPrError`, `PrTool`, `RunnerResult`
- `src/util/logger.ts` -- stderr-only `info|warn|error`
- `package.json` -- add `"bmad-pr": "bun src/cli/bmad-pr.ts"` script
- `.changeset/bmad-pr-core-and-ledger.md` -- user-visible change entry

## Tasks & Acceptance

**Execution:**
- [x] `src/pr/types.ts` -- define shared types; `BmadPrError` extends `Error` with `code: "refuse" | "fail"`
- [x] `src/util/logger.ts` -- stderr writer using `process.stderr.write`
- [x] `src/pr/runner.ts` + test -- `Bun.spawn` wrapper; export `Runner` callable type
- [x] `src/pr/gh-driver.ts` + test -- detect/push/create/edit; parse the URL `gh pr create` prints; non-zero exit throws `BmadPrError("fail")`
- [x] `src/pr/ledger.ts` + test -- frontmatter parsed via `Bun.YAML.parse`; serialize with stable key order; atomic via `Bun.write(tmp)` + `fs.renameSync`
- [x] `src/cli/bmad-pr.ts` + test -- parse flags, validate, branch via `git rev-parse --abbrev-ref HEAD`, dispatch open vs amend, exit `0`/`2`/`1`; cover every I/O matrix row
- [x] `package.json` -- add the `bmad-pr` script
- [x] `.changeset/bmad-pr-core-and-ledger.md` -- minor-bump entry describing the CLI

**Acceptance Criteria:**
- Given a feature branch with `gh` present and no prior ledger entry for `{3.2, dev-story}`, when `bmad-pr --story 3.2 --phase dev-story` runs, then exit code is 0, stdout contains the PR URL, and `_bmad-output/stories/3.2.md` has one `prs:` entry with `status: open`, valid ISO `openedAt`, and `lastAmendedAt == openedAt`.
- Given the same command runs a second time with the entry already `open`, when it completes, then no new entry is created and the entry's `lastAmendedAt` advances to a later ISO timestamp.
- Given `--dry-run`, when the command runs, then no state-changing `Bun.spawn` call is issued and no file writes occur; stdout shows the would-run commands and the would-write ledger diff.
- Given `bun run check` and `bunx tsc --noEmit` run after implementation, then both exit 0.

## Design Notes

**Runner injection.** Every shell-touching module takes a `Runner` (`(cmd, args, opts?) => Promise<RunnerResult>`). Production passes the real `Bun.spawn` wrapper; tests pass a stub that records calls. Lets us exhaust the matrix without a real `gh`/`git`.

**Ledger entry (frozen for this slice):**

```yaml
prs:
  - url: https://github.com/owner/repo/pull/42
    phase: dev-story
    runId: 2026-05-17T14-22-03Z    # omit field when --run-id absent
    status: open                    # open | merged | closed
    openedAt: 2026-05-17T14:22:03Z
    lastAmendedAt: 2026-05-17T14:22:03Z
```

**PR body (fixed; template engine = G6):**

```
BMAD slice for story <epic>.<story> phase <phase>.
See: _bmad-output/stories/<epic>.<story>.md
BMAD-Run-Id: <runId or "none">
```

**Auto vs `--amend`.** Default = ledger lookup decides (open if no entry, amend if open entry exists). `--amend` forces the amend path and refuses if no entry exists — useful only for retry-after-failure when the ledger was rolled back.

## Verification

**Commands:**
- `bun run check` -- expected: exits 0 (Biome + `bun test`)
- `bunx tsc --noEmit` -- expected: exits 0
- `bun src/cli/bmad-pr.ts --help` -- expected: prints flag list, exits 0
- `bun src/cli/bmad-pr.ts --story 3.2 --phase dev-story --dry-run` -- expected: prints would-run commands + ledger diff, exits 0, no side effects

## Suggested Review Order

**Orchestration & contract**

- The whole feature in one function — read this first to grasp the open/amend dispatch, refusals, dry-run, and runId-on-amend behavior.
  [`bmad-pr.ts:run`](../../src/cli/bmad-pr.ts#L64)

- Flag parsing with `--value`-starting-with-`--` rejection.
  [`bmad-pr.ts:parseArgs`](../../src/cli/bmad-pr.ts#L216)

- Help text — documents the auto-amend default and the runId preservation rule.
  [`bmad-pr.ts:HELP_TEXT`](../../src/cli/bmad-pr.ts#L37)

**Ledger (G3)**

- Story-ID validation (rejects `0.1`, `-1.2`, `foo`, `3`, `3.2.1`).
  [`ledger.ts:parseStoryId`](../../src/pr/ledger.ts#L22)

- Frontmatter parsing — regex anchors closing `---` to line start; refuses malformed entries with `refuse`.
  [`ledger.ts:loadLedger`](../../src/pr/ledger.ts#L45)

- Append/update — atomic tmp+rename with UUID-randomized tmp name and try/finally cleanup.
  [`ledger.ts:appendEntry`](../../src/pr/ledger.ts#L72)
  [`ledger.ts:atomicWrite`](../../src/pr/ledger.ts#L254)

- YAML serializer hardening — quotes reserved words and numeric-looking strings to survive round-trip.
  [`ledger.ts:serializeScalar`](../../src/pr/ledger.ts#L238)

**gh + git driver (G1)**

- `gh --version` for detection (avoids spawning shell builtin `command`).
  [`gh-driver.ts:detectGhOnPath`](../../src/pr/gh-driver.ts#L4)

- Push always `HEAD` per spec; no branch arg, no force.
  [`gh-driver.ts:pushBranch`](../../src/pr/gh-driver.ts#L9)

- Draft PR create + URL extraction; refuses on missing URL.
  [`gh-driver.ts:createDraftPr`](../../src/pr/gh-driver.ts#L18)

**Process plumbing**

- `Bun.spawn` wrapper with try/catch → ENOENT mapped to exit 127.
  [`runner.ts:runCommand`](../../src/pr/runner.ts#L3)

- Typed error + ledger entry shape.
  [`types.ts:BmadPrError`](../../src/pr/types.ts#L3)

- Stderr-only logger (bypasses Biome `noConsole`).
  [`logger.ts:createLogger`](../../src/util/logger.ts#L13)

**Tests, config, and follow-up**

- End-to-end CLI tests covering every I/O matrix row + the new `--trunk-branch` override and `--flag --flag` rejection.
  [`bmad-pr.test.ts`](../../src/cli/bmad-pr.test.ts#L1)

- Ledger tests including YAML round-trip for reserved/numeric strings and the frontmatter-with-inline-`---` regression.
  [`ledger.test.ts`](../../src/pr/ledger.test.ts#L1)

- `bmad-pr` script wired for `bun run`.
  [`package.json:scripts`](../../package.json#L7)

- Follow-up specs to write next (G2/G4/G5/G6 + the review-surfaced defers).
  [`deferred-work.md`](./deferred-work.md)

# Architecture: bmad-pr v1 — BMAD-style Claude plugin

Status: approved spine for the ground-up rewrite (v0 TypeScript CLI archived at tag
`v0-ts-cli`). Companion docs: `research-plugin-rewrite-2026-07-06.md` (evidence),
`epics-plugin-rewrite.md` (build order).

## Product statement

bmad-pr ships each BMAD story/phase as a **draft PR stacked on the previous story's PR**
(gt native, gh emulated, bare-git fallback), **monitors** pre-submit CI checks and
external AI reviewers (cubic.dev first), **ingests** reviewer findings into BMAD's native
review-findings format so a dev session can address them, and **closes the loop** by
committing fixes, resolving threads, and re-triggering the reviewer
(default `@cubic-dev re-review`). It plugs in **after review sessions** in both the long
BMAD methodology and quick-dev.

## Decision register (R1–R14)

- **R1 Language.** Bash (bash ≥ 4) + `jq` + `git`/`gh`/`gt`. No Node/Bun/TS, no build
  step. Markdown skills orchestrate; bash scripts execute. Python is NOT a runtime
  dependency of our scripts (bmad's own runtime scripts may use it, we don't).
- **R2 Plugin shape.** Repo root is the plugin (cubic-loop shape):
  `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (`source: "./"`),
  `skills/` at root. BMAD module identity via root `module.yaml` (`code: bmad-pr`) +
  `module-help.csv`.
- **R3 Ledger.** One JSON file per story key: `_bmad-output/pr/<key>.json`, owned by `jq`,
  atomic writes (`tmp + mv`). Schema below. Supersedes v0's story-frontmatter ledger:
  no YAML parsing in bash, and PR tooling never writes into story files' frontmatter
  (write-race safety with bmad sessions).
- **R4 Backends.** `BMAD_PR_TOOL = auto|gt|gh|git`; precedence: flag > env > config >
  auto. Auto: gt iff binary + `$(git rev-parse --git-common-dir)/.graphite_repo_config`
  exists; else gh iff binary + `gh auth status` ok; else git. Non-GitHub remote → git.
  gh is used for read-only queries (checks/threads) even on the gt path.
- **R5 Stacking.** Parent resolution for story K: explicit `--base` wins; else the branch
  of the newest ledger entry whose PR is OPEN (the previous story in flight); else trunk.
  gh path: `gh pr create --draft --base <parent> --head <cur>` + pin
  `git config branch.<cur>.gh-merge-base <parent>`. gt path: `gt track --parent <parent>`
  (untracked-branch trap) + `gt submit --stack --no-interactive --draft --no-edit`.
  `retarget` subcommand handles parent-merged: gh → `gh pr edit --base` + rebase --onto +
  push --force-with-lease; gt → `gt sync -f --delete-all --no-interactive` + resubmit.
- **R6 Reviewer providers are config profiles, not code forks.** A provider =
  `{bot login regex, trigger comment, check-run regex or none, completion mode
  (check-run | bot-review-since-SHA), score regex, resolve strategy}`. `cubic` profile is
  built in and default; `generic` profile is fully env/config-driven (that's how a user
  adds CodeRabbit/Greptile without code changes). Provider files live in
  `scripts/lib/reviewers/<name>.sh` and only set profile variables + optional overrides.
- **R7 Findings bridge.** `ingest` normalizes unresolved, non-outdated reviewer threads +
  failing CI checks into `_bmad-output/pr/<key>-findings.md`:
  a frontmatter-free markdown with one `- [ ] [Review][Patch] <Title> [<file>:<line>]
  <!-- thread:<id> -->` line per finding (severity tag included when derivable), plus a
  `## Summary` section (score, check failures). The HTML comment carries the GraphQL
  thread id so `rereview --resolve-addressed` can resolve exactly the checked-off items.
  The skill layer appends open items into the story file's `### Review Findings` section
  when a story file exists (bmad-code-review convention) and instructs deferrals to be
  recorded as `DW-<seq>` entries in deferred-work.md.
- **R8 Placement after reviews.** `bmad-pr-setup` writes: (a) `_bmad/custom/
  bmad-quick-dev.toml` and `_bmad/custom/bmad-dev-auto.toml` with `[workflow]
  on_complete` invoking `/bmad-pr ship+watch` (merge-safe: only if key empty or ours);
  (b) `.bmad-loop/plugins/bmad-pr/plugin.toml` (when `.bmad-loop/` exists) with a
  `[workflows.bmad-pr]` session at `stage = "pre_commit_gate"`, `role = "dev"`,
  `blocking = false`; (c) a `bmad-pr` section in `_bmad/config.yaml` (when present) and
  a `module-help.csv` row with `preceded-by: code-review` for the long methodology's help
  ordering; (d) `_bmad/bmad-pr/config.env` — the operative script config.
- **R9 Exit codes.** Global: `0` success, `1` unexpected failure, `2` refusal
  (precondition). `watch`/`status` add: `3` reviewer findings to address, `4` CI checks
  failed, `5` timeout, `6` reviewer absent/skipped. Machine-readable JSON on stdout with
  `--json`; human text otherwise; diagnostics on stderr.
- **R10 Preflight.** CH1/CH2/CH3/CH5 ported verbatim from v0 (detached HEAD; mid-rebase/
  merge refuse-hard; dirty-tree-outside-`_bmad-output/` with stage-only auto-fix;
  upstream-ahead with `pull --rebase` auto-fix then CH2 re-check). `--auto-fix` is
  bounded, single-attempt; `--dry-run` never mutates and never auto-fixes.
- **R11 PR shape.** Draft by default (`--publish` opt-out). Title
  `BMAD: <key> <phase>`. Body: one-line summary, artifact link, `Stacked on: #<parent>`
  when stacked, `BMAD-Run-Id: <runId>` trailer. Amend = push commits + wholesale body
  refresh + ledger `lastAmendedAt`; never rewrites history, never force-pushes (except
  `retarget`'s `--force-with-lease` rebase).
- **R12 Re-review dedupe.** Only post the trigger comment when the provider's latest
  check run is `completed`/missing AND HEAD SHA differs from `lastReviewedSha` in the
  ledger — unless threads were just resolved with no code change (prod allowed via
  `--force`).
- **R13 Tests & gates.** bats-core (pinned, vendored on demand into `tests/.vendor/` by
  `tests/vendor.sh`), stub `gh`/`gt` binaries on PATH, real throwaway git repos for
  preflight tests. `scripts/check.sh` = the gate: shellcheck (if available or CI),
  `bash -n` on all scripts, plugin manifest validation, bats suite. Git hook via
  `.githooks/pre-commit` + `git config core.hooksPath .githooks`. CI: GitHub Actions
  running the same `check.sh`.
- **R14 Config.** Flat, shell-sourceable `_bmad/bmad-pr/config.env` (committed) with
  `BMAD_PR_*` keys; env vars override file; flags override env. No YAML/TOML parsing in
  bash. Defaults live in `scripts/lib/config.sh` so the tool works unconfigured.

## Repository layout

```
.claude-plugin/{plugin.json, marketplace.json}
module.yaml                     # BMAD module identity (code: bmad-pr)
module-help.csv                 # help rows, phase-ordered after code-review
skills/
  bmad-pr/SKILL.md              # ship/amend/status/retarget — the slash command
  bmad-pr-loop/SKILL.md         # watch → ingest → address → rereview cycle
  bmad-pr-loop/references/reviewer-api.md   # verified gh/graphql/cubic recipes
  bmad-pr-setup/SKILL.md        # module registration + after-review placement
scripts/
  bmad-pr                       # CLI entry (bash): ship|status|watch|ingest|rereview|retarget|preflight
  check.sh                      # repo gate (lint + manifests + tests)
  lib/{common.sh, config.sh, ledger.sh, preflight.sh, backend.sh,
       backend-gh.sh, backend-gt.sh, backend-git.sh, checks.sh, findings.sh}
  lib/reviewers/{cubic.sh, generic.sh}
integration/
  bmad-loop/plugin.toml         # ready-to-copy .bmad-loop/plugins/bmad-pr/plugin.toml
  custom/{bmad-quick-dev.toml, bmad-dev-auto.toml}   # on_complete overrides
  config.env.example
tests/{vendor.sh, run.sh, helpers/, stubs/, *.bats}
.githooks/pre-commit
.github/workflows/ci.yml
README.md  AGENTS.md  CONTRIBUTING.md  CHANGELOG.md  cubic.yaml  LICENSE
_bmad-output/                   # this repo's own BMAD artifacts (planning + impl)
```

## Ledger schema (`_bmad-output/pr/<key>.json`)

```json
{
  "schema": 1,
  "story": "3.2",
  "branch": "bmad/story/3.2",
  "parentBranch": "bmad/story/3.1",
  "parentPr": 41,
  "pr": {"number": 42, "url": "https://github.com/o/r/pull/42", "state": "open"},
  "phase": "dev-story",
  "runId": "2026-07-06T10-00-00Z",
  "tool": "gh",
  "reviewer": {"provider": "cubic", "lastReviewedSha": "abc123",
               "lastScore": 9, "approved": false},
  "openedAt": "2026-07-06T10:00:00Z",
  "lastAmendedAt": "2026-07-06T10:00:00Z"
}
```

`<key>` = story key sanitized to `[A-Za-z0-9._-]` (epic.story like `3.2`, or free-form
for quick-dev, e.g. `quick-fix-login`). All writes go through `ledger.sh`
(`tmp.$$ + mv`), all reads through `jq`.

## Subcommand contracts

- `ship --story <key> --phase <p> [--base <br>] [--run-id <id>] [--amend] [--publish]
  [--dry-run] [--auto-fix] [--tool T] [--trunk <br>] [--json]` — preflight → resolve
  parent (R5) → ensure branch (create `bmad/story/<key>` from parent if on trunk;
  operate in place if on a matching `bmad/*` branch; refuse otherwise) → push → create or
  amend draft PR → ledger upsert. Prints PR URL.
- `status --story <key> [--json]` — ledger + live PR state + checks buckets + reviewer
  state (score, unresolved count, approved). Exit per R9.
- `watch --story <key> [--timeout N] [--json]` — poll checks (bucket aggregation,
  15 s→60 s backoff) and reviewer completion (per provider profile); on completion runs
  ingest automatically. Exit per R9.
- `ingest --story <key> [--json]` — write `<key>-findings.md` (R7); stdout summary.
- `rereview --story <key> [--resolve-addressed] [--comment <msg>] [--force]` — resolve
  threads for checked-off findings, push if commits pending, post trigger comment
  (R12), update ledger `lastReviewedSha`.
- `retarget --story <key>` — parent-merged repair (R5).
- `preflight [--auto-fix] [--dry-run] [--json]` — standalone CH checks.

## Skill flow (who does what)

- **/bmad-pr** (skill): derives `<key>`/`<phase>` from BMAD state (active story spec →
  sprint-status → newest artifact), runs `ship`, reports URL; on exit 2 explains the
  refusal + `--auto-fix` hint.
- **/bmad-pr-loop** (skill): after review sessions. `ship` (amend) → `watch` → if exit 3/4:
  read findings file, apply the bmad-code-review triage discipline (patch/defer/dismiss;
  defers → DW entries), fix code, commit, `rereview --resolve-addressed` → repeat until
  green (score ≥ threshold AND 0 unresolved AND checks pass, or provider approval), max
  `BMAD_PR_MAX_ITERATIONS` (default 5). Mirrors cubic-loop's exit conditions.
- **/bmad-pr-setup** (skill): R8 placement + config authoring, idempotent, shows diff of
  what it writes.

## Error taxonomy

`refuse` (exit 2): on trunk, no remote, tool unavailable, mid-rebase/merge, malformed
ledger, `--amend` without ledger entry. `fail` (exit 1): git/gh/gt/jq runtime errors —
stderr passthrough preserved. Watch verdicts (3/4/5/6) are states, not errors.

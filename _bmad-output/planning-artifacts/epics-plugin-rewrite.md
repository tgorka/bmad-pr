# Epics & stories: bmad-pr v1 plugin rewrite

Build order for the ground-up rewrite. Each story lands with its tests; the repo gate
(`scripts/check.sh`) stays green after every story.

## E1 — Repo reset & plugin scaffold

- **1.1 Reset.** Remove TS/Bun surface (`src/`, `package.json`, `bun.lock`,
  `bunfig.toml`, `tsconfig.json`, `biome.json`, `.changeset/`, old `.claude/skills/`).
  AC: no Bun/TS references remain outside `_bmad-output/` history docs and CHANGELOG.
- **1.2 Plugin manifests.** `.claude-plugin/plugin.json` + `marketplace.json`
  (`source: "./"`), `module.yaml`, `module-help.csv` (row `preceded-by: code-review`).
  AC: both JSON files parse with `jq`; manifest validation in `check.sh`.
- **1.3 Test harness & gates.** `tests/vendor.sh` (pinned bats-core), `tests/run.sh`,
  stub-binary helper, `scripts/check.sh` (`bash -n`, shellcheck-if-present, manifest
  checks, bats), `.githooks/pre-commit`, `.github/workflows/ci.yml` (ubuntu: shellcheck +
  check.sh). AC: `scripts/check.sh` passes on a fresh clone with zero global installs.

## E2 — Core libraries

- **2.1 common + config.** `lib/common.sh` (die/refuse/log, exit codes R9, `--json`
  emitters, `now_iso`), `lib/config.sh` (defaults; source `_bmad/bmad-pr/config.env`;
  env>file precedence). AC: bats for precedence + refuse/fail exit codes.
- **2.2 Ledger.** `lib/ledger.sh`: init/read/upsert via jq, atomic write, key
  sanitization, newest-open-entry query (stack-parent resolution input). AC: bats CRUD +
  corrupt-file refusal + concurrent tmp naming.
- **2.3 Preflight.** `lib/preflight.sh` CH1/CH2/CH3/CH5 + bounded `--auto-fix`
  (R10). AC: bats against real throwaway git repos covering every detect/fix/refuse path
  (detached HEAD, rebase-merge, rebase-apply, MERGE_HEAD, dirty in/out of
  `_bmad-output/`, upstream ahead with/without conflict).
- **2.4 Backend detection.** `lib/backend.sh` (R4) incl. worktree-safe gt probe and
  non-GitHub-remote demotion. AC: bats with stub `gt`/`gh` and fake remotes.

## E3 — Ship (stacked PR creation)

- **3.1 gh backend.** create/amend draft PR with explicit `--base`/`--head`, merge-base
  pin, PR-exists probe via `gh pr list`, body builder (R11). AC: bats with stub `gh`
  recording argv; dry-run plan output; amend path preserves runId.
- **3.2 gt backend.** track-parent + `submit --stack --no-interactive --draft --no-edit`;
  untracked-branch repair. AC: bats with stub `gt` (created/tracked/submitted argv).
- **3.3 git fallback + branch policy.** push-only + manual-PR instructions; branch
  ensure/refuse rules from R5/R10; `retarget` subcommand (gh rebase-onto path + gt sync
  path). AC: bats for trunk refusal, in-place `bmad/*` branch, retarget plan.

## E4 — Watch & ingest (CI + reviewer providers)

- **4.1 Checks poller.** `lib/checks.sh`: bucket aggregation jq, deadline + backoff,
  post-push grace. AC: bats with stub `gh` emitting scripted bucket sequences (pending →
  pass, pending → fail, empty grace).
- **4.2 Reviewer profiles.** `lib/reviewers/cubic.sh` (defaults incl. trigger
  `@cubic-dev re-review` configurable), `generic.sh` (all-env). Completion probes:
  check-run mode + bot-review-since-SHA fallback. Score extraction, approval stamp,
  unresolved-thread query (GraphQL, paginated, non-outdated). AC: bats with canned
  check-run/review/GraphQL JSON fixtures.
- **4.3 Findings bridge.** `lib/findings.sh`: threads+checks → `<key>-findings.md` (R7
  format with `<!-- thread:<id> -->`), stable ordering, severity heuristics, `## Summary`
  (score/threshold, failing checks). AC: golden-file bats tests.

## E5 — Review cycle & skills

- **5.1 rereview.** `--resolve-addressed` (checked-off findings → batched
  resolveReviewThread), dedupe rule R12, ledger `lastReviewedSha`/`lastScore` update.
  AC: bats with stub gh graphql capturing mutations; dedupe matrix (same-SHA/new-SHA ×
  completed/in-progress).
- **5.2 Skills.** `skills/bmad-pr/SKILL.md` (derivation + dispatch + exit-code table),
  `skills/bmad-pr-loop/SKILL.md` (cycle policy, triage discipline, DW handoff, exit
  conditions, max iterations), `references/reviewer-api.md` (verified recipes). AC:
  frontmatter validated in `check.sh`; skills reference only shipped paths via
  `${CLAUDE_PLUGIN_ROOT}`.
- **5.3 Setup & placement.** `skills/bmad-pr-setup/SKILL.md` + `integration/` assets
  (bmad-loop plugin.toml, custom/*.toml on_complete, config.env.example) per R8. AC:
  integration TOMLs are valid, documented, and idempotency rules spelled out in the
  skill.

## E6 — Docs & release

- **6.1 Docs.** README (install as plugin/marketplace, quickstart, subcommand table,
  provider table, placement diagram), AGENTS.md (bash conventions, test rules),
  CONTRIBUTING.md (check.sh gate, hooks), CHANGELOG 1.0.0.
- **6.2 PR.** Single PR from this branch to `main`; body links planning artifacts and tag
  `v0-ts-cli`.

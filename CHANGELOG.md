# Changelog

## 0.2.0

### Minor Changes

- c70c624: Add `bmad-pr` CLI (G1+G3 slice): opens or amends a draft pull request via
  `gh` and persists the URL into a stories-file PR ledger at
  `_bmad-output/stories/<epic>.<story>.md`. Flags: `--story`, `--phase`,
  `--run-id`, `--amend`, `--dry-run`, `--trunk-branch`, `--help`. Defaults
  auto-detect open vs amend via the ledger; `--amend` is force-amend.
  Deferred to follow-up specs: `gt` stacking, `hub`/plain-`git` adapters,
  git-safety preflight, `/bmad-next` autoPR hook, PR body template engine.
- e1f3b64: Add G2 git-safety preflight to `bmad-pr` CLI. Before any state-changing
  operation (push, gh create, gh edit), four detectors run in order:

  - **CH1** — detached HEAD
  - **CH2** — interactive rebase or merge in progress (refusal-only)
  - **CH3** — unstaged changes outside `_bmad-output/`
  - **CH5** — upstream branch ahead of HEAD

  Refusals emit a single-line `Refuse: …` hint on stderr (exit 2). The
  new `--auto-fix` flag attempts safe remediation for CH1 (branch from
  current HEAD), CH3 (stage `_bmad-output/` only; never `git add -A`),
  and CH5 (`git pull --rebase`; abort on conflict). CH2 is never
  auto-fixed; the user must resolve the rebase/merge manually. Auto-fix
  re-runs preflight once after the fix and refuses if anything still
  fails. Under `--dry-run`, stdout begins with `preflight: ok` when all
  detectors pass.

  CH4 (`gt restack` mid-flight) stays deferred to the G4 stacked-PR
  slice. CH6–CH14 remain deferred per the brainstorming.

- 7fd3209: Add the `/bmad-pr` Claude Code skill at `.claude/skills/bmad-pr/SKILL.md`. Auto-loaded for Claude Code sessions inside this repo. Wraps the existing `bmad-pr` CLI — derives `--story`, `--phase`, `--run-id`, and `--trunk-branch` from BMAD state (user message → active spec → sprint-status → most-recent artifact), then dispatches via Bash and surfaces the CLI's exit codes and refusal hints verbatim. The CLI remains the source of truth.

This file is auto-managed by [Changesets](https://github.com/changesets/changesets). Add a Changeset entry via `bun run changeset` for any user-visible change; entries are aggregated into release notes when a "Version Packages" PR merges.

## Unreleased

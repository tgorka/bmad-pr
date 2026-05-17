---
name: bmad-pr
description: Use when the user types /bmad-pr or asks to open, amend, or preview a draft pull request for the current BMAD story phase. Dispatches to the `bmad-pr` CLI which manages the per-story PR ledger.
---

# bmad-pr

## Overview

Thin wrapper around the `bmad-pr` CLI (`bun src/cli/bmad-pr.ts`). The CLI is the source of truth — refusal hints, exit codes, atomic ledger writes, gh/git plumbing. This skill's job is to (a) derive the right flags from BMAD state, (b) shell out, and (c) surface results verbatim. Do not re-implement what the CLI does.

## When to Use

- User types `/bmad-pr` (with or without args).
- User asks to "open a PR for this story", "amend the PR for story X.Y", "preview the PR body", or similar BMAD-PR-shaped phrasing.
- A `/bmad-next` step just promoted a story-scoped artifact (e.g. `bmad-dev-story` for story 3.2) and the user wants to ship it.

**Do NOT use** for non-BMAD PRs, for `git`/`gh` operations the user could do directly with one command, or to bypass the CLI's refusals (those refusals carry real preconditions).

## Required arguments

The CLI requires `--story <epic>.<story>` and `--phase <name>`. Derive them in this order — stop as soon as one source gives a confident answer:

1. **User's message**: explicit numbers/phase ("PR for 3.2 dev-story") win.
2. **Active spec frontmatter**: `_bmad-output/implementation-artifacts/spec-*.md` with `status: ready-for-dev` or `in-progress`. The spec's slug or `story_key` carries the story; `phase` matches the BMAD step (`dev-story`, `code-review`, `retro`, etc.).
3. **Sprint status**: `_bmad-output/implementation-artifacts/sprint-status.yaml` — the entry whose status is `in-progress` is almost certainly the right story.
4. **Most-recent BMAD artifact**: highest-numbered story file under `_bmad-output/stories/`, or the most-recent `_bmad-output/planning-artifacts/*.md` (for planning phases).

If you cannot determine both with confidence, ask the user ONE concise question that lists what you found. Do not guess.

## Quick reference

| Intent | Invocation |
|---|---|
| Open or amend (default) | `bun src/cli/bmad-pr.ts --story 3.2 --phase dev-story` |
| Force amend (refuse if no open entry) | `bun src/cli/bmad-pr.ts --story 3.2 --phase dev-story --amend` |
| Preview without side effects | `bun src/cli/bmad-pr.ts --story 3.2 --phase dev-story --dry-run` |
| Pass the BMAD run ID for new PRs | `bun src/cli/bmad-pr.ts --story 3.2 --phase dev-story --run-id <id>` |
| Trunk branch isn't `main` | add `--trunk-branch develop` |
| Help | `bun src/cli/bmad-pr.ts --help` |

Run via Bash. Use `cd` only if the working directory isn't the repo root — the CLI resolves the repo via `git rev-parse --show-toplevel` so any subdirectory under the repo works.

## Handling output

- **Exit 0**: stdout contains the PR URL (or, for `--dry-run`, the would-run plan). Surface the URL to the user.
- **Exit 2 (refusal)**: stderr starts with `Refuse: ` followed by a single-line hint. Show the hint to the user verbatim. Do NOT try to work around it — refusals encode preconditions (trunk branch, missing `gh`, malformed ledger, not in a repo, etc.).
- **Exit 1 (fail)**: stderr starts with `Error: ` — unexpected failure. Show it; offer to investigate.

## Default behavior — open vs amend

The CLI's default auto-detects via the ledger at `_bmad-output/stories/<epic>.<story>.md`:
- No open entry for `{story, phase}` → opens a new draft PR.
- Open entry exists → pushes the branch and amends the existing PR body. Preserves the original `runId`; only `lastAmendedAt` updates.

Use `--amend` only when you specifically want a force-amend that refuses if there's no entry. `--dry-run` is the right choice when the user wants to inspect before acting.

## Common mistakes

- **Shelling out to `gh pr create` directly.** That bypasses the ledger and risks duplicate PRs. Always go through the CLI.
- **Adding `--draft` / `--title` manually.** The CLI sets these; passing extras isn't a supported surface.
- **Re-running after a refusal without fixing the precondition.** If the CLI refused, the cause is real (trunk branch, missing `gh`, malformed ledger). Address it first.
- **Confusing the CLI's `--amend` with `git commit --amend`.** They're unrelated. The CLI never rewrites git history.

## Repo references

- CLI entry: `src/cli/bmad-pr.ts`
- Ledger schema and helpers: `src/pr/ledger.ts`
- Spec history: `_bmad-output/implementation-artifacts/spec-bmad-pr-core-and-ledger.md` and `spec-cubic-review-fixes-pr3.md`
- Deferred work for follow-up PRs (G2/G4/G5/G6, cubic defers): `_bmad-output/implementation-artifacts/deferred-work.md`

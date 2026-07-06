---
name: bmad-pr
description: Ship the current BMAD story as a draft PR stacked on the previous story's PR. Use when the user types /bmad-pr, says "ship this story", "open the story PR", "amend the story PR", or a BMAD workflow step instructs opening a PR after review sessions.
---

# bmad-pr — ship a story PR

You dispatch to the deterministic CLI at
`${CLAUDE_PLUGIN_ROOT}/scripts/bmad-pr`. Never re-implement its logic; your
job is deriving arguments, running it, and explaining the outcome.

## 1. Derive story key and phase

In priority order:

1. Explicit user input ("ship 3.2", "/bmad-pr 3.2 dev-story").
2. The story spec being worked on in this conversation (its filename:
   `_bmad-output/stories/<key>.md` or the spec's `story:` frontmatter).
3. Sprint state: `_bmad-output/sprint-status.md` (or the project's sprint
   artifact) — the story currently `in progress` / most recently `review`.
4. Newest story file: `ls -t _bmad-output/stories/*.md | head -1`.

Phase = the BMAD phase that just finished (`dev-story`, `code-review`,
`quick-dev`, ...). When invoked by a workflow hook, the hook text names the
phase. If you cannot derive a key, ask the user — do not guess.

## 2. Run

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bmad-pr" ship --story <key> --phase <phase>
```

Useful flags: `--dry-run` (preview plan), `--auto-fix` (bounded git-safety
remediation), `--base <branch>` (explicit stack parent), `--publish`
(non-draft), `--tool gt|gh|git` (override auto-detection), `--json`.

The CLI stacks automatically: the PR base is the previous story's open PR
branch (from the ledger in `_bmad-output/pr/`), falling back to trunk.

## 3. Interpret the exit code

| Exit | Meaning | Your action |
| ---- | ------- | ----------- |
| 0 | PR opened/amended; URL on stdout | Report the URL. Suggest `/bmad-pr-loop <key>` to drive review. |
| 2 | Refusal — a precondition failed | Read stderr. It names the check (detached HEAD, rebase/merge in progress, unstaged changes outside `_bmad-output/`, remote ahead, wrong branch, existing merged PR). If the message offers `--auto-fix`, ask the user or re-run with it when the fix is clearly safe. Never work around a refusal manually without telling the user what it protects against. |
| 1 | Unexpected failure | Show stderr verbatim; investigate (gh auth? network? jq?). |

## Common mistakes

- Do not create PRs with raw `gh pr create` — you would bypass the ledger,
  stacking, and preflight.
- Do not delete or hand-edit `_bmad-output/pr/*.json` unless the CLI's
  refusal message tells you to.
- `--dry-run` never mutates and never auto-fixes; use it when unsure.
- Amending happens automatically when a ledger entry exists — you do not
  need `--amend` (it only *asserts* an entry exists).

## After the parent PR merges

Run `"${CLAUDE_PLUGIN_ROOT}/scripts/bmad-pr" retarget --story <key>` to
rebase the story onto the new base and update the PR (gh backend uses the
recorded parent tip; gt backend uses `gt sync`).

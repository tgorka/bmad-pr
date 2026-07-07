---
name: bmad-pr-loop
description: Drive a BMAD story PR through CI and the external AI reviewer (cubic.dev by default) until green — watch checks, ingest reviewer findings into BMAD review format, address them, push, re-trigger review. Use when the user says "run the PR review cycle", "/bmad-pr-loop <story>", "get this PR green", or a BMAD workflow hook invokes it after review sessions.
---

# bmad-pr-loop — the address → push → re-review cycle

You orchestrate the cycle; the CLI at `${CLAUDE_PLUGIN_ROOT}/scripts/bmad-pr`
does all GitHub interaction. Command recipes and provider details:
[references/reviewer-api.md](references/reviewer-api.md).

Derive `<key>` as in the bmad-pr skill. The story must already have a PR
(`bmad-pr ship` ran); if not, ship first.

## The loop (max $BMAD_PR_MAX_ITERATIONS iterations, default 5)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bmad-pr" watch --story <key>
```

`watch` waits for CI checks, then for the reviewer to complete, then writes
`_bmad-output/pr/<key>-findings.md` and exits with the verdict:

| Exit | Verdict | Your action |
| ---- | ------- | ----------- |
| 0 | Green: checks pass, no unresolved threads, score ≥ threshold or approved | Report success. Loop ends. |
| 3 | Reviewer findings to address | Go to "Address findings". |
| 4 | CI checks failed | Findings file lists the failing checks. Fix the code/tests, commit, push, re-run `watch`. |
| 5 | Timeout | Report what is still pending; ask the user whether to keep waiting (re-run `watch`) or stop. Do not iterate blindly against a stuck check. |
| 6 | Reviewer absent/skipped | Diagnose: PR still draft with reviewer configured to skip drafts? Ignore rules? Reviewer app not installed? Report; continue without reviewer only if the user agrees. |
| 2 | Refusal | Read stderr (usually: no ledger/PR yet — run ship first). |
| 1 | Unexpected failure | Show stderr verbatim, stop the loop, and report — do not retry blindly (typical causes: gh auth, network, rate limit). |

## Address findings

Open `_bmad-output/pr/<key>-findings.md`. Each unchecked item is one
finding in BMAD code-review form:
`- [ ] [Review][Patch] <title> [<file>:<line>] <!-- thread:<id> -->`

Triage with the same discipline as bmad-code-review:

- **Patch** — the finding is real and in scope: fix the code now. Judge each
  finding on evidence; reviewers are sometimes wrong.
- **Defer** — real but out of scope for this story: append a `DW-<seq>`
  entry to `_bmad-output/implementation-artifacts/deferred-work.md`
  (`origin`/`location`/`severity`/`reason`/`status: open`), and mark the
  item `[x]` with a `(deferred: DW-<seq>)` note appended to the line.
- **Dismiss** (false positive) — mark `[x]` and append `(dismissed: <one-line
  reason>)`. The resolve step closes the thread; the reason stays in the
  findings file for audit.

If the story file exists (`_bmad-output/stories/<key>.md`), mirror open
**Patch** items into its `### Review Findings` section so the standard BMAD
dev flow sees them.

Then:

1. Fix the patched items. Run the project's own gate/tests locally.
2. Commit on the story branch (conventional message, e.g.
   `fix(<scope>): address review findings for <key>`). Do not rewrite
   history.
3. Mark fixed items `[x]` in the findings file.
4. Re-trigger:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bmad-pr" rereview --story <key> --resolve-addressed
```

This resolves the checked-off threads, pushes pending commits, and posts
the provider trigger comment (default `@cubic-dev re-review`) — deduped, so
an unchanged, already-reviewed SHA is not re-prodded unless threads were
resolved or you pass `--force`.

5. Re-run `watch`. Repeat.

## Stop conditions

- **Green** (watch exit 0) — report score, iterations used, PR URL.
- **Iteration ceiling** — stop and summarize the still-open findings; never
  loop past `BMAD_PR_MAX_ITERATIONS` without the user.
- **Oscillation** — the reviewer re-raises something you dismissed: stop and
  escalate to the user instead of arguing with the bot.

## Reporting

Always end with: PR URL, checks verdict, reviewer score (and threshold),
threads resolved this session, findings deferred (DW ids), iterations used.

# Deferred Work

Items split out of `spec-bmad-pr-core-and-ledger.md` (G1+G3) during
quick-dev step-01 routing on 2026-05-17. Each one becomes its own
spec when scheduled.

Source: `_bmad-output/planning-artifacts/bmad-brainstorming.md`
("Synthesized v1 Architecture").

## G2 — Git safety preflight (CH1–CH5)

Standalone validator with `--auto-fix`. Detects and refuses on:

- CH1 detached HEAD (auto-fix: branch from current HEAD)
- CH2 mid-rebase / mid-merge (no auto-fix; user resolves)
- CH3 dirty working tree, unrelated changes (auto-fix: stage only
  `_bmad-output/` paths)
- CH4 stacked-PR mid-rebase, gt-specific (no auto-fix; `gt restack`)
- CH5 force-pushed remote / amend race (auto-fix: `git pull --rebase`)

Refusal contract per BMAD AR22: single-line actionable hint, `--auto-fix`
offered where safe, never touches non-BMAD files, never force-pushes,
never resolves merge conflicts.

Depends on: nothing. Consumed by: G1 PR-creation path.

## G4 — Stacked-PR (gt) integration

- Branch patterns: `bmad/planning/<phase>` and `bmad/story/<epic>.<story>`
- gt stack-aware amend (push new commit, refresh body, no history rewrite)
- Prior-phase PR link block in body (C4)
- Planning stack vs story stack semantics from brainstorming D1

Depends on: G1 (PR creation), G3 (ledger lookup), G2 (mid-rebase refuse).

## G5 — /bmad-next autoPR hook + config schema

- `pr:` block in `bmad-stepper.config.yaml` (tool, autoPR, draftByDefault,
  targetRemote, template, emojiByPhase, labelMap, branchPattern,
  linearIssueKey)
- Non-blocking hook call from `/bmad-next` post-promotion
- Retry semantics on hook failure; loop does not crash

Depends on: G1. Touches bmad-stepper (out-of-repo dependency).

## G6 — PR body template engine

- `.github/bmad-pr-template.md` with handlebars-style placeholders
- Phase emoji prefix (S4): 🧠 brainstorm, 📋 prd, 🏗️ architecture,
  🎨 ux, 📝 stories, 💻 dev-story
- Conventional Commits PR titles (A1)
- Label map per phase (C2)
- `BMAD-Run-Id: <runId>` Gerrit-style trailer (A5)
- Linear/Jira issue auto-link via config (A4)

Depends on: G1.

## Review-surfaced defers (from G2 preflight review pass)

- **CH3 staging granularity** — `git add _bmad-output/` stages every untracked + modified path under that tree, including ones the user has not yet reviewed. Consider `git add -u _bmad-output/` (only tracked modifications) or document the wider behavior. Currently documented in SKILL.md.
- **CH1 race / `--trunk-branch HEAD`** — if the user sets `--trunk-branch HEAD`, the CLI refuses on the trunk check before CH1 ever runs. Currently surfaces a misleading trunk-refusal message. Tiny.
- **CH1 + CH3 retry hints when auto-fix is in flight** — when a post-fix CH5/CH3 surfaces, the user sees the detector's "Try: bmad-pr --auto-fix" hint despite already passing the flag. Partially patched (suffix is stripped); double-check after G4 lands.
- **`Date.now()` for CH1 auto-fix branch suffix** — not injectable via the CLI's `now` injector. Collision risk is real only for sub-second double-invocation. Defer.
- **Pre-existing CH3 staging of unreviewed files** — see "CH3 staging granularity" above.
- **Quoted-path corner cases under `-z`** — the new `-z` parser handles NUL framing correctly. The `unquote` helper was removed; if a future code path adds back human-readable porcelain parsing, restore the C-quote decoder.

## Review-surfaced defers (from G1+G3 review pass)

These were found during step-04 review of the G1+G3 slice. Not blockers
for that slice; each should be a follow-up spec.

- **gh-pr-create-explicit-target** — `gh pr create` is invoked without
  `--head`/`--base`/`--repo`. Multi-remote checkouts (fork-and-upstream)
  open the PR against the wrong base or fork with no diagnostic. Add
  configurable `pr.targetRemote` and a base-detection helper.
- **closed-merged-ledger-handling** — `findEntry` only matches
  `status: open`. If a closed or merged entry already exists for a
  `{story, phase}`, re-running silently opens a second PR. Decide: refuse
  with hint, or auto-link to the prior PR.
- **crash-durable-ledger-write** — `Bun.write(tmp)` + `renameSync` is
  atomic on same-filesystem but not durable across power loss. Add an
  `fsync` (or `Bun.file(tmp).flush()` if Bun gains it) before the
  rename. Couples naturally with CH14 file-lock work.

## Open questions deferred to brief/PRD

Per brainstorming "Open Questions Deferred to Brief / PRD":

- Mono-repo precedence (multiple AGENT.md): directory proximity vs
  lexical?
- gh App vs user token (auth + rate-limit implications)
- Signed commits: propagate `--gpg-sign` from repo policy?
- CI status reporter (C3): GitHub Checks API only, or generic?
- CH6–CH14 v1.x roadmap timing

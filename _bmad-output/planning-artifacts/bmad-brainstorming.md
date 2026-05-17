---
stepsCompleted: [1, 2]
inputDocuments: []
session_topic: '/bmad-pr skill design'
session_goals: 'novel features, edge cases & failure modes, integration patterns, decision-tree clarity'
selected_approach: 'ai-recommended'
techniques_used: ['Question Storming', 'SCAMPER Method', 'Chaos Engineering', 'Decision Tree Mapping']
ideas_generated: []
context_file: ''
---

# Brainstorming Session: /bmad-pr Skill Design

**Date:** 2026-05-16
**Facilitator:** BMAD Brainstorming Skill

## Session Overview

**Topic:** /bmad-pr skill design — a BMAD skill that creates pull requests
(via gt/gh/git) at key checkpoints in the BMAD workflow, invoked via the
slash-command `/bmad-pr`.

**Goals:**
- Generate novel feature ideas beyond the obvious PR-creation flow
- Surface edge cases and failure modes
- Explore integration patterns with /bmad-next, /bmad-loop, autoPR config
- Resolve open decision points (mono-repo, gt stacked PRs, amend semantics)

**Prior Art:** A 2026-05-14 archive at
`_bmad-output/archive/2026-05-14/planning-artifacts/bmad-brainstorming.md`
covers a first pass — this fresh session will go orthogonal and push past
the obvious answers.

### Session Setup

The user has indicated all four outcome categories are in scope. The
session will rotate creative domains every ~10 ideas to combat semantic
clustering, targeting 100+ ideas before any organization or convergence.

## Technique Selection

**Approach:** AI-Recommended Techniques

**Recommended Techniques (in order):**

1. **Question Storming** (deep, ~10 min) — generate questions only, no
   answers; define the problem space before locking solutions. Targets
   the "decision-tree clarity" goal.
2. **SCAMPER Method** (structured, ~20 min) — Substitute, Combine,
   Adapt, Modify, Put to other uses, Eliminate, Reverse. Targets
   "novel features beyond the obvious."
3. **Chaos Engineering** (wild, ~15 min) — deliberately break the skill
   in extreme environments. Targets "edge cases & failure modes."
4. **Decision Tree Mapping** (structured, ~15 min) — converge open
   choices into actionable decisions for the brief.

**AI Rationale:** Divergent (Phase 1-2) → adversarial (Phase 3) →
convergent (Phase 4), with creative-domain rotation every ~10 ideas to
prevent semantic clustering.

---

## Phase 1 — Question Storming

**Rule:** Only questions, no answers yet. We're defining the problem
space, not solving it.

### Seed questions (facilitator)

**State & persistence**
1. When `/bmad-pr` runs, where does the PR URL go — `state.yaml`, a `runHistory[]` entry, a separate `pr-history.yaml`, or back to the artifact's frontmatter?
2. Should `/bmad-pr` be idempotent within the same `runId`? Second call = no-op, amend, or force-update of body?
3. What happens when the verifier just promoted artifact A, but artifact B (from a prior phase) was never PR'd? Catch-up batch, or skip?

**Branch ownership**
4. Who owns the branch name when the user is already on a feature branch they care about?
5. When `gt` is the tool and a stack is mid-rebase, can `/bmad-pr` safely intervene, or must it refuse?
6. If two BMAD steps run in parallel (future feature) and both want to PR, what resolves the race?

**Environment & UX**
7. What does "the user is offline" mean for `/bmad-pr`? Queue, fail-fast, or stage locally and flush on next online run?
8. Does the PR description quote the artifact verbatim, summarize it, or link to a permalink? Each has different review-friction implications.

### User decisions (resolving seed questions)

The user chose to answer (rather than expand) the seed questions:

- **Q1 → Decided:** PR URL(s) stored in the **stories file**
  (`_bmad-output/stories/<epic>.<story>.md` frontmatter or body).
  *Not* a separate `pr-history.yaml` or `state.yaml.runHistory[]`.
  Implication: stories file becomes the authoritative PR ledger;
  `/bmad-pr` must read+write the right story file on each invocation.
  Multiple PRs per story → list under one frontmatter key.

- **Q3 → Decided:** When prior-phase artifacts were never PR'd,
  **create PRs on the stack** (via `gt` stacked-PR semantics, or a
  best-effort emulation in `gh`/`git`). Catch-up is automatic, one
  PR per missed artifact, stacked in phase order.

### Still-open seed questions (defer to Phase 4 Decision Tree)

- Q2 (idempotency within same runId)
- Q4 (branch ownership conflict with user's existing branch)
- Q5 (mid-rebase intervention)
- Q6 (parallel-step race)
- Q7 (offline behaviour)
- Q8 (PR body: verbatim / summary / permalink)

---

## Phase 2 — SCAMPER Method

Seven lenses on `/bmad-pr`. Ideas only; convergence in Phase 4.

### S — Substitute

- **S1:** Substitute *PR creation* with a *draft snapshot* — emit a
  `.bmad-pr-draft.md` file the user copies into the web UI. Zero git
  ops; useful for restrictive corporate environments.
- **S2:** Substitute `gh`/`gt` with the **host's API directly**
  (GitHub REST/GraphQL, GitLab API). Bypasses CLI install requirements;
  needs a token but no binary.
- **S3:** Substitute *branch-per-artifact* with **branch-per-epic** —
  fewer, larger PRs. Trade-off: less granular review, faster overall.
- **S4:** Substitute the PR title text with **title + phase emoji**
  (🧠 brainstorm, 📋 PRD, 🏗️ arch, 💻 dev). Visual scan in the PR list.
- **S5:** Substitute *user-as-PR-author* with `bmad-bot[bot]` (GitHub
  App). Clear non-human attribution; reviewers know it's auto-generated.

### C — Combine

- **C1:** Combine `/bmad-pr` with `/bmad-checkpoint-preview` — every PR
  opens with a self-review summary by the checkpoint skill.
- **C2:** Combine PR creation with **automatic label assignment**
  (`phase:planning`, `epic:2`, `story:3`).
- **C3:** Combine `/bmad-pr` with a **CI status reporter** — skill
  watches CI, comments on PR with status updates, blocks merge until
  pass.
- **C4:** Combine PR body with the **prior phase's PR link** — chain of
  PRs visible in each body; reviewers see the BMAD trail.
- **C5:** Combine `/bmad-pr` with **changelog generation** — each
  merged PR auto-appends to `CHANGELOG.md`.

### A — Adapt

- **A1:** Adapt **Conventional Commits** spec to PR titles
  (`feat(story-3.2): …`, `docs(prd): …`).
- **A2:** Adapt **Stacked diffs** (Phabricator / Sapling / Graphite) —
  every BMAD phase = one stack frame, automatic dependency tracking.
  Aligns with user's Q3 decision to "create PRs on the stack."
- **A3:** Adapt **Renovate Bot's templating** —
  `.github/bmad-pr-template.md` per repo, with placeholders.
- **A4:** Adapt **Linear's auto-link** to GitHub PR — embed Linear
  issue keys from a `linearIssue:` config.
- **A5:** Adapt **Gerrit's Change-Id** trailer — every BMAD PR carries
  `BMAD-Run-Id: <runId>` trailer for replay/audit.

### M — Modify

- **M1:** Magnify the PR body: include **full artifact** + **diff
  stat** + **next-phase preview** + **rollback instructions**.
- **M2:** Minify the PR body: just `BMAD: <phase> for <story>`. Force
  reviewers to open the artifact file.
- **M3:** Magnify "amend mode": amending also rewrites commit history
  (`--force-with-lease`) so the PR is always one clean commit per phase.
- **M4:** Minify "PR title" to just the story ID — `S3.2` — relying
  on label for context.
- **M5:** Magnify metadata: PR body has a machine-readable YAML block
  (`<!-- bmad-meta … -->`) for tooling consumption (telemetry,
  dashboards, downstream automation).

### P — Put to other uses

- **P1:** Use `/bmad-pr` as a **status announcement channel** — every
  PR triggers Slack/Discord notify to the product owner.
- **P2:** Use PR descriptions as **executable docs** — embed `bun run`
  snippets reviewers copy-paste to test.
- **P3:** Use **closed (rejected) PRs as a learning corpus** —
  `/bmad-retrospective` reads rejection comments to improve future
  artifacts.
- **P4:** Use `/bmad-pr --dry-run` as a **PR preview / spec verifier**
  — shows what the PR would look like without opening it.
- **P5:** Use `/bmad-pr` to also **open a Linear/Jira ticket**
  mirroring the PR — single command opens both.

### E — Eliminate

- **E1:** Eliminate branch creation when the user is already on a
  non-trunk branch — operate in-place, push to current.
- **E2:** Eliminate the `gh`/`gt`/`git` selection — just shell out to
  whichever is on PATH first, no config needed.
- **E3:** Eliminate PR opening for non-trunk-merge intent — if BMAD is
  run in a sandbox/playground, emit a "phantom PR" markdown locally.
- **E4:** Eliminate the `autoPR: true` config — make PR-creation
  per-step opt-in via a `pr:` block in `failurePolicies:`-style config.
- **E5:** Eliminate the per-phase PR pattern — collapse to **one PR
  per epic**, with each artifact a commit on it.

### R — Reverse

- **R1:** Instead of "PR created at step END", flip: **PR is created
  at step START**, populated incrementally as artifacts land.
  Reviewers see WIP throughout.
- **R2:** Instead of "tool detection at runtime", flip: tool is
  **declared in PR body itself** ("created with gt") so reviewers know
  how to interact.
- **R3:** Instead of "merge unblocks next BMAD step", flip: **next
  step doesn't run until prior PR is merged**. Hard human checkpoint.
- **R4:** Instead of "PR opens automatically", flip: **PR opens only
  if user types `/bmad-pr --commit`**. Default = local artifact only.
- **R5:** Instead of "we map BMAD → PR", flip: **we map PR → BMAD** —
  incoming PRs auto-create BMAD state ("I see a feat PR, scaffold an
  epic for it").

### SCAMPER Triage (user decisions)

**KEEP (13 — load-bearing for v1):**
- **S4** — phase emoji in PR title
- **C1** — bundle `/bmad-checkpoint-preview` self-review into PR
- **C2** — auto label assignment (`phase:*`, `epic:N`, `story:M.N`)
- **C3** — CI status reporter (skill watches CI, comments on PR)
- **C4** — prior-phase PR link in body (BMAD trail visible)
- **C5** — changelog generation on merge
- **A1** — Conventional Commits PR titles
- **A2** — stacked diffs per BMAD phase (`gt` first-class)
- **A3** — `.github/bmad-pr-template.md` with placeholders
- **A4** — Linear/Jira issue auto-link via config
- **A5** — `BMAD-Run-Id: <runId>` Gerrit-style trailer
- **P4** — `--dry-run` PR preview / spec verifier
- **R1** — PR created at step START, populated incrementally (WIP-visible)

**KILL (15 — out of scope for v1):**
- S3, S5 (branch-per-epic, bmad-bot author)
- M1, M2, M3, M4, M5 (all body-size / amend-rewrite / YAML-block extremes)
- E5 (one-PR-per-epic)
- P1, P2, P3, P5 (Slack notify, executable docs, learning corpus, Linear-ticket mirror)
- R2, R3, R5 (tool-in-body, block-step-on-merge, PR→BMAD reverse mapping)

**PARKED (7 — revisit if v1 ships clean):**
- S1 (draft-snapshot zero-git mode), S2 (host-API direct)
- E1 (no-branch when on feature branch), E2 (no-config shell-out)
- E3 (phantom-PR for sandboxes), E4 (per-step opt-in via `pr:` config)
- R4 (manual `--commit` to open vs. dry-run-default)

**Emergent decisions surfaced:**
- *PR body size* — both extremes killed; need middle-ground default
  (likely: summary + linked artifact + CI status + BMAD trail).
- *Tool selection* — stays in config (R2 killed; auto-detect chain
  from prior brainstorm is retained).
- *WIP visibility* — R1 kept conflicts with `gt` stacked-PR mid-rebase
  semantics; needs Phase-4 resolution.

---

## Phase 3 — Chaos Engineering

Deliberately break `/bmad-pr` to find robust v1 behaviour.

### Git state chaos

- **CH1: Detached HEAD.** User ran `git checkout <sha>` to inspect
  something, forgot, then BMAD step completes. `/bmad-pr` cannot push.
  **Failure mode:** push refused, no branch to PR from.
  *Question: refuse with hint, or auto-branch from current HEAD?*

- **CH2: Mid-rebase / mid-merge.** `git status` shows
  `interactive rebase in progress`. `/bmad-pr` triggers (auto from
  loop) and tries to commit/push.
  **Failure mode:** uncommitted artifact files get tangled with
  rebase conflicts; potential data loss.
  *Mitigation: hard-refuse with "Run: complete the rebase first." hint.*

- **CH3: Dirty working tree (unrelated changes).** User has
  unstaged edits in `src/foo.ts` (not BMAD output) when `/bmad-pr`
  fires for a planning artifact.
  **Failure mode:** `git add _bmad-output/...` works, but unrelated
  edits live forever in the same commit OR get force-stashed.
  *Mitigation: stage only `_bmad-output/` paths; never `git add -A`.*

- **CH4: Stacked-PR mid-rebase (gt-specific).** User has 3-frame
  stack `bmad/2/{brainstorm,prd,arch}` and ran `gt restack` mid-flight.
  `/bmad-pr` fires for `arch` while frame 2 is in conflict.
  **Failure mode:** `gt submit` partially succeeds, leaves stack in
  inconsistent remote state.
  *Mitigation: probe `gt log` for `IN_PROGRESS_RESTACK` before any push.*

- **CH5: Force-pushed remote branch.** Reviewer rebased the PR branch
  remotely; user's local is behind. `/bmad-pr --amend` runs.
  **Failure mode:** `git push --force-with-lease` rejects; or worse,
  `--force` overwrites reviewer's changes.
  *Mitigation: refuse on stale-ref; require `/bmad-pr --rebase-first`.*

### Environment chaos

- **CH6: No `gh` token / expired.** `gh pr create` returns HTTP 401.
  `/bmad-pr` config says tool=`gh`.
  **Failure mode:** PR not created, but commit IS pushed. Now user
  has a remote branch with no PR.
  *Mitigation: detect 401 early (pre-push probe); fall back to
  `git push` only + emit "Run: gh auth refresh" hint.*

- **CH7: Rate-limited mid-flow.** Loop runs 5 phases; phases 1-3
  open PRs, phase 4 hits GitHub secondary rate limit.
  **Failure mode:** partial PR set; state.yaml says step succeeded
  but no PR exists.
  *Mitigation: backoff+retry once; if still fails, write PR-pending
  marker to stories file with `pr-status: queued`.*

- **CH8: No remote at all.** Repo has `origin` removed (or never
  added). `/bmad-pr` runs.
  **Failure mode:** push fails with cryptic error.
  *Mitigation: probe remotes at skill entry; emit "Run: git remote add
  origin <url>" before any operation.*

- **CH9: Multiple remotes (fork-and-upstream).** User has both
  `origin` (their fork) and `upstream` (canonical). Which target?
  **Failure mode:** PR opens against wrong base ("merge to upstream"
  but pushed to origin).
  *Mitigation: config `pr.targetRemote: origin` + auto-detect
  preferring `upstream` if PR base is `main`.*

### State chaos

- **CH10: Corrupted state.yaml.** YAML parse error mid-loop;
  `/bmad-pr` is called by `/bmad-next` after the verifier promoted
  an artifact.
  **Failure mode:** PR fires with empty/wrong context.
  *Mitigation: skill validates state before any git op; refuses with
  "Run: /bmad-next --doctor" if invalid.*

- **CH11: Stories file missing for current story.** Loop just
  finished `bmad-create-story` but file write failed silently.
  `/bmad-pr` cannot find `_bmad-output/stories/<id>.md`.
  **Failure mode:** PR body has placeholders / blank context, or
  Q1's "store PR URL in stories file" decision silently writes
  nowhere.
  *Mitigation: refuse if target stories file absent; hint
  "Run: /bmad-next --resume" to recover.*

- **CH12: Existing PR for same story.** User manually opened a PR
  earlier for story 3.2; `/bmad-pr` runs and tries to open another.
  **Failure mode:** duplicate PRs for same story; stories-file
  PR-list grows unbounded.
  *Mitigation: stories-file PR-list lookup BEFORE creation; on hit,
  default to `--amend` against the existing PR.*

### Process chaos

- **CH13: User cancels mid-PR (Ctrl-C).** SIGINT during `gh pr create`
  HTTP call; commit pushed but PR creation interrupted.
  **Failure mode:** remote has commit, no PR. Loop's next iteration
  re-runs `/bmad-pr` and creates a duplicate.
  *Mitigation: idempotency — check for open PR matching
  `BMAD-Run-Id` trailer before creating new (A5 keep makes this
  possible).*

- **CH14: Two BMAD loops running in same repo (different worktrees).**
  Concurrent `/bmad-loop` invocations on epics 2 and 3 in separate
  worktrees both call `/bmad-pr`.
  **Failure mode:** race on stories-file write (Q1's decided storage
  location) corrupts PR ledger.
  *Mitigation: file-lock on stories file write (existing
  `.stepper/state.yaml.lock` pattern extended).*

### Chaos Triage (user decisions)

**v1 SCOPE (5 — must handle):**
- **CH1** Detached HEAD
- **CH2** Mid-rebase / mid-merge
- **CH3** Dirty working tree (unrelated changes)
- **CH4** Stacked-PR mid-rebase (`gt`-specific)
- **CH5** Force-pushed remote / amend race

**v1.x or accepted-risk (9 — deferred):**
- CH6 (gh token expired), CH7 (rate limit), CH8 (no remote),
  CH9 (multi-remote), CH10 (corrupt state.yaml), CH11 (missing
  stories file), CH12 (existing PR collision), CH13 (SIGINT mid-PR),
  CH14 (concurrent worktrees)

**Refusal contract for v1:** *Refuse + offer auto-fix.* Every CH1-CH5
detection halts the skill with a single-line actionable hint per BMAD
AR22, AND surfaces a `--auto-fix` variant per scenario:

- CH1 → `Try: /bmad-pr --auto-fix` creates a branch from current HEAD.
- CH2 → `Run: git rebase --continue` (no auto-fix; user must resolve).
- CH3 → `Try: /bmad-pr --auto-fix` stages only `_bmad-output/` paths.
- CH4 → `Run: gt restack` (no auto-fix; gt's territory).
- CH5 → `Try: /bmad-pr --auto-fix` does `git pull --rebase` first.

Auto-fix scope is bounded: never touches non-BMAD files, never
force-pushes, never resolves merge conflicts.

---

## Phase 4 — Decision Tree Mapping

Eight open decisions from prior phases. Each lists options with the
recommendation surfaced first.

### D1 — When does `/bmad-pr` fire? (PR granularity)

**Two scopes — different granularity per scope:**

**Planning phases (brainstorm, brief, prd, architecture, ux):**
- One PR per phase artifact.
- Branch: `bmad/planning/<phase>` (or `bmad/<runId>/<phase>`).
- Stacked frames in phase order via `gt`.
- These phases are not story-scoped; they apply to the whole project.

**Story-scoped phases (create-story, dev-story, code-review, retro):**
- **One PR per story**, NOT per phase.
- PR opens at `bmad-create-story` for that story (e.g., story 3.2).
- Subsequent BMAD steps for the SAME story (dev-story → code-review →
  retro) **amend** the existing PR — push new commits, refresh body
  with latest artifact state.
- Next story → next frame on the stack (depends on prior story's PR
  per `gt` stack semantics).

```
Planning stack (one-shot, per-project):
  bmad/planning/brainstorm  ◄── PR; lands first
   └─ bmad/planning/brief
       └─ bmad/planning/prd
           └─ bmad/planning/architecture
               └─ bmad/planning/ux

Story stack (per-epic, per-story):
  bmad/story/3.1   ◄── opened at create-story; amended through dev+review+retro
   └─ bmad/story/3.2   ◄── opened when create-story fires for 3.2
       └─ bmad/story/3.3
```

**Recommendation:** Per-story for story phases, per-phase for planning
phases. Aligns with code-review ergonomics — reviewers see one coherent
PR per story (full lifecycle: design → code → review fixes → retro)
instead of 3-4 fragmented phase-PRs per story.

**R1 (PR-at-start)** is now the DEFAULT for story-scoped phases — the
create-story PR is inherently WIP until retro lands. The `--wip`
opt-in flag still applies to planning phases that want incremental
visibility.

### D2 — Tool selection precedence

```
1. --tool CLI flag
2. BMAD_PR_TOOL env var
3. bmad-config.yaml → pr.tool
4. Auto-detect: gt → gh → git+hub → git plain
```

**Recommendation:** This order, ship as-is from prior brainstorm §3.2.
No new decision — confirmed.

### D3 — Idempotency / amend semantics (Q2)

Amend now spans the **story's lifecycle**, not just same-runId retries.

```
/bmad-pr called for a story that already has an open story-PR:
  ├─ A. No-op (idempotent; refuse silently)
  ├─ B. Amend existing PR (push new commit, refresh body)  ◄── REC
  └─ C. Force-update (rewrite history, --force-with-lease)
```

**Recommendation:** **B** — amend body + push new commit; never
rewrites history. Applies in BOTH cases:
1. **Same-runId retry** (e.g., user invokes `/bmad-pr` twice manually).
2. **Different BMAD step, same story** (e.g., dev-story amends the
   create-story PR; code-review amends again).

Detection: lookup by **story ID** in the stories-file `prs:` ledger
(Q1) AND by `BMAD-Run-Id` trailer (A5) as fallback. The story-ID
lookup is the primary key for story-scoped phases; the trailer is
the fallback for planning-phase retries.

Body refresh on amend: append latest phase artifact link + diff
summary to the running PR body; do NOT replace prior content (keeps
review trail visible).

### D4 — Branch naming (Q4)

Branch naming is now scope-dependent:

| Scope | Pattern | Example |
|-------|---------|---------|
| Planning phase | `bmad/planning/<phase>` | `bmad/planning/prd` |
| Story | `bmad/story/<epic>.<story>` | `bmad/story/3.2` |
| Generic fallback (no BMAD state) | `bmad/<runId>` | `bmad/2026-05-17T08-12-…` |

**Conflict resolution when user is already on a feature branch:**
- Refuse if user is on `main` / trunk → require explicit branch.
- If on a feature branch unrelated to BMAD → create the `bmad/...`
  branch off it (PR target = user's feature branch, not main).
- If on a `bmad/story/X.Y` branch matching the current story → operate
  in-place (no new branch); push to current.

Avoids polluting user's feature branch with planning artifacts; keeps
story-scoped work co-located on the story branch.

### D5 — PR body content (M1/M2 both killed → middle ground)

**Recommendation:** Default body = summary (3-line excerpt) + linked
artifact path + CI status placeholder + BMAD-trail block (C4) +
`BMAD-Run-Id` trailer (A5). No full artifact verbatim, no minimal stub.
Template lives at `.github/bmad-pr-template.md` (A3) for repo override.

### D6 — Offline / no-network behaviour (Q7)

```
Network down when /bmad-pr fires (autoPR loop):
  ├─ A. Fail-fast: refuse, halt the loop
  ├─ B. Stage locally: commit + push deferred, mark stories-file
  │     with `pr-status: queued`, flush on next online run  ◄── REC
  └─ C. Queue silently with no marker (risk: silent failure)
```

**Recommendation:** **B** — stage locally with `pr-status: queued`
marker in stories file. Aligns with Q1's "PR URLs in stories file"
decision. Next `/bmad-pr` invocation drains the queue.

### D7 — Mid-rebase intervention (Q5 / CH2 / CH4)

**Recommendation:** **Refuse hard.** No auto-fix for active rebase
(both `git rebase` and `gt restack`). Hint: `Run: git rebase
--continue` or `Run: gt restack` per detected tool. Captured in
Phase 3 triage.

### D8 — WIP visibility (R1 kept but conflicts with stacked PRs)

```
R1 PR-at-step-START vs. A2 stacked diffs per phase:
  ├─ A. Default = closed-state-final (A2 wins) ◄── REC
  ├─ B. Default = WIP (R1 wins, A2 only on submit)
  └─ C. Per-phase flag (--wip switches)
```

**Recommendation:** **A** by default with **C** as escape hatch.
`/bmad-pr --wip` opens a draft PR at step start; standard invocation
opens final PR at step end. v1 defaults to A; user opts in to WIP per
invocation.

---

## Synthesized v1 Architecture

Combining all decisions into a coherent picture.

**Invocation surface:**
```
/bmad-pr                              # standard: open or amend story/planning PR
/bmad-pr --amend                      # force-amend even if no auto-detected match
/bmad-pr --wip                        # draft at step start (default for stories)
/bmad-pr --dry-run                    # preview PR body without opening (P4)
/bmad-pr --auto-fix                   # remediate CH1/CH3/CH5 unsafe state
/bmad-pr --tool gt|gh|git             # override tool selection
```

**Config surface (`bmad-stepper.config.yaml` additions):**
```yaml
pr:
  tool: auto                          # auto | gt | gh | git
  autoPR: true                        # D1 — fire on every BMAD step
  draftByDefault: true
  targetRemote: origin                # CH9 mitigation
  template: .github/bmad-pr-template.md
  emojiByPhase:                       # S4 keep
    brainstorm: "🧠"
    prd: "📋"
    architecture: "🏗️"
    ux: "🎨"
    stories: "📝"
    dev-story: "💻"
  labelMap:                           # C2 keep
    brainstorm: "phase:planning"
    dev-story: "phase:implementation"
  branchPattern:                      # D4 scope-dependent
    planning: "bmad/planning/<phase>"
    story:    "bmad/story/<epic>.<story>"
    fallback: "bmad/<runId>"
  linearIssueKey: ""                  # A4 keep, optional
```

**State persistence (Q1 decision):**
- PR URLs stored in `_bmad-output/stories/<epic>.<story>.md`
  frontmatter under `prs:` list (story PRs) and a project-level
  `_bmad-output/planning-prs.yaml` ledger (planning PRs).
- Each entry: `{ url, phase, runId, status, openedAt, lastAmendedAt }`.
- `pr-status: queued` marker for D6 offline-queue.

**Trigger flow — story-scoped phases:**
1. `bmad-create-story` promotes story 3.2 artifact.
2. `/bmad-next` calls `/bmad-pr` as a hook if `config.pr.autoPR=true`.
3. `/bmad-pr` reads BMAD state; validates Git safety (CH1-CH5);
   looks up story 3.2 in stories-file ledger.
4. **No existing PR** → open new draft PR at `bmad/story/3.2`;
   write URL into story-file frontmatter.
5. **Existing PR** → push new commit; refresh body; do not rewrite
   history (D3 amend semantics).
6. Subsequent `bmad-dev-story`, `bmad-code-review`, `bmad-retrospective`
   for story 3.2 all hit step 5 — the same PR is amended.
7. Next story (e.g., 3.3) → step 4 opens its own PR, stacked above 3.2.

**Trigger flow — planning phases:**
1. `bmad-create-prd` promotes the PRD artifact.
2. `/bmad-pr` looks up the phase in `planning-prs.yaml` ledger.
3. **No existing PR** → open at `bmad/planning/prd`, stacked above
   `bmad/planning/brief`.
4. **Existing PR** (retry case) → amend; do not rewrite history.
5. Each planning phase = its own frame in the planning stack.

**Failure contract (v1 CH1-CH5):**
- Single-line AR22 hints with `--auto-fix` offered where safe.
- Non-Git chaos (CH6-CH14) deferred; some emit warnings, none crash
  the BMAD loop.

---

## Recommended Next Steps (Input for `/bmad-create-brief`)

1. **Define `/bmad-pr` invocation contract** with the 6 flags
   (`--amend`, `--wip`, `--dry-run`, `--auto-fix`, `--tool`, default).
2. **Specify stories-file PR ledger schema** (Q1 decision) — exact
   YAML keys, append semantics, file-lock requirements.
3. **Document Git-safety preflight** for CH1-CH5 with auto-fix paths.
4. **Spec the `/bmad-next` autoPR hook** — non-blocking call, error
   logging path, retry semantics.
5. **Prototype `gt` stacked-PR path first** (A2) — richest behaviour;
   `gh`/`git` fallbacks are degraded subsets.
6. **Define template engine** for A3 `.github/bmad-pr-template.md`
   (handlebars-style, what variables, what defaults).

## Open Questions Deferred to Brief / PRD

- **Mono-repo (multiple AGENT.md):** which one wins, by directory
  proximity or lexical precedence?
- **gh App vs. user token:** authentication and rate-limit
  implications.
- **Signed commits:** read repo policy from AGENT.md, propagate
  `--gpg-sign`?
- **CI status reporter (C3 keep):** which CI providers? GitHub Checks
  API only, or generic?
- **CH6-CH14 v1.x roadmap:** when do these get scheduled?

---

_End of brainstorming session. This document is the input for the next
BMAD step (`/bmad-create-brief` or equivalent)._













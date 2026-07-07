# Deferred Work

Canonical ledger (bmad DW format). Triaged 2026-07-07 against the v1.0.0
plugin rewrite (PR #11, tag `v1.0.0`); the pre-rewrite v0 ledger and its
resolutions are recorded at the bottom for audit.

### DW-1: PR body template engine (v0 goal G6)

origin: v0 brainstorming G6, carried through the v1 rewrite, 2026-07-07
location: scripts/bmad-pr build_body_file
severity: medium
reason: v1 ships a fixed body (summary + artifact link + Stacked-on + BMAD-Run-Id
  trailer). Templates (`.github/bmad-pr-template.md` placeholders), phase emoji,
  Conventional-Commits titles, label maps and Linear/Jira auto-links are polish
  that should wait for real usage feedback.
status: open

### DW-2: Planning-phase stacks (bmad/planning/<phase>)

origin: v0 decision D1 (per-phase PRs for planning artifacts), 2026-07-07
location: scripts/bmad-pr cmd_ship branch policy
severity: medium
reason: v1 implements story stacks only (`bmad/story/<key>`). Planning phases
  currently ship like any other story key; dedicated planning-stack semantics
  (one PR per planning phase, stacked) need D1's design carried over.
status: open

### DW-3: Multi-remote target selection (fork-and-upstream)

origin: v0 review defer gh-pr-create-explicit-target + CH9, 2026-07-07
location: scripts/lib/backend-*.sh (origin hardcoded)
severity: medium
reason: v1 always passes explicit --base/--head but assumes the `origin`
  remote. Fork workflows need a `BMAD_PR_TARGET_REMOTE` (prefer `upstream`
  when present) and a base-repo flag for gh.
status: open

### DW-4: CH4 detector — gt mid-restack state

origin: v0 chaos item CH4, 2026-07-07
location: scripts/lib/backend-gt.sh
severity: low
reason: v1 relies on gt's own failure messages when a stack is mid-restack.
  A preflight detector (parse `gt log` / rebase state) would refuse earlier
  with a cleaner hint.
status: open

### DW-5: Durable ledger writes (fsync before rename)

origin: v0 review defer crash-durable-ledger-write, 2026-07-07
location: scripts/lib/ledger.sh ledger_write
severity: low
reason: mktemp + mv is atomic on one filesystem but not durable across power
  loss. bash has no portable fsync; would need `sync -f` (coreutils ≥ 8.24)
  or a tiny helper. Couples with DW-6.
status: open

### DW-6: Concurrent-invocation file lock (CH14)

origin: v0 chaos item CH14, 2026-07-07
location: scripts/lib/ledger.sh
severity: low
reason: two bmad-pr processes (parallel worktrees) can interleave
  read-modify-write on the same ledger file. flock(1) around ledger_update
  would close it; rare in practice because keys are per-story.
status: open

### DW-7: Offline/rate-limit queueing (D6/CH7)

origin: v0 decision D6, 2026-07-07
location: scripts/bmad-pr (ship/rereview network paths)
severity: low
reason: v1 fails fast on network errors (loudly, never green). A
  `pr-status: queued` marker + drain-on-next-run was designed in v0 but adds
  state complexity disproportionate to current need.
status: open

### DW-8: CH3 staging granularity

origin: v0 review defer, 2026-07-07
location: scripts/lib/preflight.sh preflight_ch3_fix
severity: low
reason: `git add -- $scope` stages every untracked + modified path under the
  scope, including files the user has not reviewed. `git add -u` (tracked
  only) is stricter but would skip new BMAD artifacts. Current wide behavior
  is documented; revisit with usage feedback.
status: open

### DW-9: CH1 auto-fix branch-name collision window

origin: v0 review defer (Date.now suffix), 2026-07-07
location: scripts/lib/preflight.sh preflight_ch1_fix
severity: low
reason: branch suffix uses epoch seconds; sub-second double invocation could
  collide. Accepted risk — git refuses the duplicate branch, nothing corrupts.
status: open

---

## Resolved by the v1.0.0 rewrite (v0 ledger audit)

- **G2 git-safety preflight (CH1/CH2/CH3/CH5)** — done; ported with bounded
  `--auto-fix`, dry-run-never-mutates, worktree-safe CH2.
- **G4 stacked-PR gt integration** — done (gt backend: `track --parent`,
  `submit --no-interactive`, `gt sync` retarget); prior-phase PR link in
  body (C4) done via `Stacked on: #N`.
- **G5 autoPR hook + config schema** — superseded: placement now via
  `workflow.on_complete` overrides (quick-dev, dev-auto) + bmad-loop
  `pre_commit_gate` plugin; config via `_bmad/bmad-pr/config.env`
  (parsed, never sourced). The bmad-stepper-specific hook is out of scope.
- **closed-merged-ledger-handling** — done: ship refuses on a merged/closed
  entry with a removal hint.
- **CH12 existing-PR duplicate** — done: ship adopts an open PR for the
  branch (and syncs its base).
- **CH1-before-trunk-check message confusion** — resolved by design:
  preflight runs before branch policy in v1.
- **auto-fix retry-hint duplication** — resolved: post-fix failures use the
  plain message without the `--auto-fix` suffix.
- **quoted-path corner cases** — moot: v1 parses NUL-framed porcelain only.
- **`BMAD-Run-Id` trailer (A5)** — done (fixed body).
- **Open questions (auth model, signed commits, CI reporter scope,
  mono-repo AGENT.md precedence)** — remain product-brief questions, not
  implementation defers; tracked in planning artifacts.

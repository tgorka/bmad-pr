# Spec: DW backlog sweep (DW-1..DW-9) — v1.1.0

Scope: close every open entry of `deferred-work.md` (post-v1.0.0 triage).
Decisions below are the contract; each lands with tests and the gate green.

## DW-1 — PR body template engine + title/labels

- `BMAD_PR_TEMPLATE` (default `.github/bmad-pr-template.md`, in the TARGET
  repo). When present, the body is the template with literal placeholder
  substitution (no shell evaluation): `{{story}}`, `{{phase}}`,
  `{{artifact}}`, `{{parent_pr}}`, `{{run_id}}`, `{{timestamp}}`. Unknown
  placeholders pass through untouched. Absent → current fixed body.
- `BMAD_PR_TITLE_FORMAT` = `bmad` (default, `BMAD: <key> <phase>` — frozen
  v1 contract) | `conventional` (`feat(story-<key>): <phase>`).
- `BMAD_PR_TITLE_EMOJI` = `false` (default) | `true` → phase-emoji prefix
  (💻 dev/quick-dev, 📝 story authoring, 🧠 brainstorm, 📋 prd, 🏗️
  architecture, 🎨 ux, 🔍 review, 🔁 retro).
- `BMAD_PR_LABELS` = comma list applied on PR creation (`--label` per
  entry); amend leaves labels alone. Per-phase maps and issue auto-links
  are expressible in the template — not separate config.

## DW-2 — Planning-phase stacks

- `ship --planning`: branch becomes `<prefix>/planning/<sanitized-phase>`;
  when `--story` is omitted the ledger key defaults to
  `planning-<sanitized-phase>`. Stack-parent resolution is unchanged
  (newest open ledger entry), which naturally chains planning PRs (D1).

## DW-3 — Multi-remote / fork flows

- `BMAD_PR_REMOTE` (default `origin`) parametrizes every hardcoded remote:
  detection, pushes, `refs/remotes/<r>/…` lookups, fetches, retarget.
- Base-repo resolution: when a remote named `upstream` exists it is the
  base for all GitHub queries (`repo_slug` parses its URL instead of
  `gh repo view`); `gh pr create` then targets it (`--repo <base>`) with a
  fork-qualified head (`<push-owner>:<branch>`).
- Known limit (documented): PR adoption-by-branch matches on branch name
  within the base repo only.

## DW-4 — gt-aware CH2/CH4 hint

- CH2 detection already catches gt restacks (gt drives git-rebase
  machinery). In gt-initialized repos the refusal hint says
  `gt continue` / `gt rebase --abort` instead of raw git commands.

## DW-5 — Durable ledger writes

- Best-effort durability: `sync -d` the temp file before rename and the
  final path after (falls back to plain `sync`, then no-op, on platforms
  without coreutils flags). Never fails the write.

## DW-6 — Ledger lock

- `ledger_update` (the read-modify-write) takes a portable mkdir-based
  lock (`<path>.lock/`, 10 s deadline, refusal names the stale dir).
  flock(1) is not portable to macOS; mkdir is atomic everywhere.

## DW-7 — Offline queue: CLOSED as superseded

- v0's queue design predates v1's idempotent ship/amend and rereview
  dedupe: re-running after connectivity returns drains naturally, with no
  extra state. Failures stay loud (never green). No code change.

## DW-8 — CH3 staging granularity

- `BMAD_PR_STAGE_MODE` = `all` (default, current `git add -- <scope>`) |
  `tracked` (`git add -u -- <scope>`, tracked modifications only).

## DW-9 — CH1 collision window

- Auto-fix branch suffix gains the PID: `bmad-pr/<sha>-<epoch>-<pid>`.

## Non-goals

- Full per-phase label maps / issue-tracker config blocks (template covers
  the use cases; revisit only on demand).
- Fork adoption across repos; queue state (DW-7 rationale).

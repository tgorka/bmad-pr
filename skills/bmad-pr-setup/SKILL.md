---
name: bmad-pr-setup
description: Install and place bmad-pr in a BMAD project — write its config, register the module, and hook it after review sessions in quick-dev, dev-story (dev-auto) and bmad-loop. Use when the user says "setup bmad-pr", "install bmad-pr module", or "configure bmad-pr".
---

# bmad-pr-setup — registration + after-review placement

Everything you write is idempotent: re-running setup refreshes bmad-pr's own
entries and never clobbers unrelated user content. Show the user a summary
of every file you create or modify. Templates live in
`${CLAUDE_PLUGIN_ROOT}/integration/`.

## 1. Operative config (always)

Create `_bmad/bmad-pr/config.env` from
`${CLAUDE_PLUGIN_ROOT}/integration/config.env.example` if it does not exist.
Ask the user (or infer from the repo) only the values that matter:

- `BMAD_PR_TRUNK` — default branch (check `git symbolic-ref refs/remotes/origin/HEAD`).
- `BMAD_PR_REVIEWER` — `cubic` if a `cubic.yaml` exists at the repo root,
  else ask (`cubic` / `generic` / `none`).
- `BMAD_PR_REVIEWER_TRIGGER` — keep the provider default unless the team
  uses a different handle.
- Leave the rest commented (defaults apply).

## 2. BMAD module registration (when `_bmad/` exists)

- `_bmad/config.yaml`: add/replace the `bmad-pr:` section (delete any
  existing `bmad-pr:` section first — anti-zombie — then write):

```yaml
bmad-pr:
  name: BMAD PR
  version: 1.0.0
  config: _bmad/bmad-pr/config.env
```

- `_bmad/module-help.csv` (if the project keeps one): append the rows from
  `${CLAUDE_PLUGIN_ROOT}/module-help.csv`, first removing any existing
  `bmad-pr,` rows. The `preceded-by: code-review` column places bmad-pr
  after review in the long-methodology help ordering.

## 3. Placement after review sessions

**quick-dev** — write `_bmad/custom/bmad-quick-dev.toml` from
`${CLAUDE_PLUGIN_ROOT}/integration/custom/bmad-quick-dev.toml`. If the file
already exists: merge — only set `workflow.on_complete` when it is empty or
already a bmad-pr instruction; if the user has a different `on_complete`,
show both and ask how to combine (chaining both instructions in one string
is fine).

**dev-story via the unattended loop (bmad-dev-auto)** — same procedure with
`${CLAUDE_PLUGIN_ROOT}/integration/custom/bmad-dev-auto.toml` →
`_bmad/custom/bmad-dev-auto.toml`. This hook runs inside dev-auto's HALT
protocol, so it fires in unattended runs too.

**bmad-loop orchestrator** (when `.bmad-loop/` exists) — copy
`${CLAUDE_PLUGIN_ROOT}/integration/bmad-loop/plugin.toml` to
`.bmad-loop/plugins/bmad-pr/plugin.toml`. The workflow session runs at
`pre_commit_gate` (fires unconditionally before every commit, defer-safe)
with `blocking = false`; the operator can tune it via `[plugins.bmad-pr]`
in `.bmad-loop/policy.toml`.

## 4. Verify

- `bash "${CLAUDE_PLUGIN_ROOT}/scripts/bmad-pr" preflight --dry-run` inside
  the project (expect exit 0 or an explained refusal).
- `git check-ignore _bmad/custom/*.user.toml` should hold if the project
  gitignores personal overrides (recommend adding if absent).
- Report: files written, files merged, hooks installed, and the one-line
  usage reminder: "after a review session finishes, run `/bmad-pr` then
  `/bmad-pr-loop`, or let the installed hooks do it."

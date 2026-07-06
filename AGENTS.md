# AGENTS.md

The contract for AI coding agents (Claude Code, Codex, etc.) and human
contributors working on this repo.

## What this project is

A Claude Code plugin (bash + markdown, no build step) that ships BMAD
stories as stacked PRs and drives external AI review cycles. The repo root
is the plugin. BMAD artifacts under `_bmad-output/` ARE the spec — read
`_bmad-output/planning-artifacts/architecture-plugin-rewrite.md` (decision
register R1–R14) before non-trivial changes. The pre-rewrite TypeScript
implementation is archived at tag `v0-ts-cli`; do not resurrect it.

## Repo layout

- `.claude-plugin/` — plugin + marketplace manifests.
- `skills/*/SKILL.md` — the Claude-facing orchestration layer. Skills derive
  arguments and interpret exit codes; they never re-implement CLI logic.
- `scripts/bmad-pr` — the deterministic CLI. `scripts/lib/*.sh` — sourced
  modules (config, ledger, preflight, backends, reviewer engine, findings).
- `scripts/lib/reviewers/*.sh` — reviewer provider profiles (set-if-unset
  variables only; behavior lives in `reviewer.sh`).
- `integration/` — templates the setup skill installs into target projects.
- `tests/*.bats` — bats suite; helpers in `tests/helpers/`.
- `module.yaml`, `module-help.csv` — BMAD module identity/registration.
- `_bmad-output/` — this project's own BMAD artifacts (committed).

## Quality gates

Every change must satisfy `scripts/check.sh` exit 0:

- `bash -n` on every shell file; `shellcheck --severity=warning` clean.
- Plugin manifests parse; every `skills/*/SKILL.md` has `name` +
  `description` frontmatter; `module-help.csv` columns consistent.
- `tests/run.sh` green. Tests added/updated for any behavior change.

## Conventions

- Bash: `set -euo pipefail` in executables; libs are `# shellcheck
  shell=bash` sourced files. 2-space indent, `snake_case` functions,
  `BMAD_PR_*` for exported config. Beware `set -e` + `[[ ... ]] && cmd` as
  a function's last line (add `return 0`).
- Exit-code contract is frozen (R9): 0 ok, 1 unexpected, 2 refuse,
  3 findings, 4 checks failed, 5 timeout, 6 reviewer absent. `refuse()` for
  precondition failures with a how-to-proceed message; `die()` for bugs.
- All GitHub JSON goes through `jq` (never `gh --jq` with variables — it
  can't bind them). Paginated `gh api` output merges with `jq -s`.
- Ledger writes only via `ledger_write` (atomic tmp+mv). Never hand-edit
  `_bmad-output/pr/*.json` in code paths.
- Tests: throwaway git repos via `make_repo`/`add_origin`, network tools
  stubbed via `make_stub` (`tests/helpers/`). Tests must not touch the
  network or this repo's own `_bmad-output/`.
- Commits: conventional (`feat(bmad-pr): ...`); PRs to `main`; CI must be
  green.

## Do / Don't

- DO keep skills thin — argument derivation + exit-code interpretation.
- DO update `integration/config.env.example` when adding config keys.
- DON'T call `gh pr create` outside `backend-gh.sh` — stacking, ledger and
  preflight guarantees live there.
- DON'T add runtime dependencies beyond bash/git/jq/gh/gt without updating
  the architecture doc and README requirements.

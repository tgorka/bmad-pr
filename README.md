# bmad-pr

A [BMAD](https://github.com/bmad-code-org/BMAD-METHOD)-style Claude Code
plugin that closes the gap between BMAD review sessions and GitHub:

- **Ships** each story as a **draft PR stacked on the previous story's PR**
  — natively via [Graphite](https://graphite.com) (`gt`), emulated via `gh`
  (explicit `--base`), or bare `git` as a last resort.
- **Watches** pre-submit CI checks and external AI reviewers
  ([cubic.dev](https://cubic.dev) built in; CodeRabbit/Greptile via the
  `generic` provider).
- **Ingests** reviewer findings into BMAD's review-findings format
  (`- [ ] [Review][Patch] <title> [<file>:<line>]`) so the normal BMAD
  address/defer/dismiss discipline applies.
- **Closes the loop**: commits fixes, resolves the addressed review threads,
  and re-triggers the reviewer (default comment: `@cubic-dev re-review`) —
  deduped by SHA so bots aren't spammed.
- **Places itself after reviews** in both the long BMAD methodology
  (dev-auto HALT hook, bmad-loop `pre_commit_gate` plugin) and quick-dev
  (`workflow.on_complete` override).

The previous TypeScript/Bun implementation is archived at tag
[`v0-ts-cli`](https://github.com/tgorka/bmad-pr/releases/tag/v0-ts-cli).

## Install

As a Claude Code plugin (this repo is its own marketplace):

```
/plugin marketplace add tgorka/bmad-pr
/plugin install bmad-pr@bmad-pr
```

Then, inside your BMAD project: run `/bmad-pr-setup` — it writes
`_bmad/bmad-pr/config.env`, registers the module in `_bmad/config.yaml`,
and installs the after-review hooks (quick-dev, dev-auto, bmad-loop).

Runtime requirements: `bash` ≥ 4, `git`, `jq`; `gh` (authenticated) for PR
automation; `gt` optional for native stacking.

## Skills

| Skill | What it does |
| ----- | ------------- |
| `/bmad-pr` | Derive story/phase from BMAD state and ship (open/amend) the stacked draft PR |
| `/bmad-pr-loop` | Watch CI + reviewer → ingest findings → address → push → re-review, until green |
| `/bmad-pr-setup` | Register the module and place it after review sessions |

## CLI

Skills dispatch to a deterministic CLI you can also run directly:

```bash
scripts/bmad-pr ship     --story 3.2 --phase dev-story [--dry-run] [--auto-fix]
scripts/bmad-pr watch    --story 3.2 [--timeout 1800]
scripts/bmad-pr ingest   --story 3.2 [--json]
scripts/bmad-pr rereview --story 3.2 --resolve-addressed
scripts/bmad-pr retarget --story 3.2      # after the parent PR merged
scripts/bmad-pr status   --story 3.2 --json
scripts/bmad-pr preflight [--auto-fix] [--dry-run]
```

Exit codes: `0` success/green, `1` unexpected failure, `2` refusal
(precondition; message explains), `3` reviewer findings to address,
`4` CI checks failed, `5` timeout, `6` reviewer absent/skipped.

State lives in a per-story JSON ledger under `_bmad-output/pr/` (committed),
findings in `_bmad-output/pr/<key>-findings.md`.

### Git safety (preflight)

Ported from v0: CH1 detached HEAD, CH2 mid-rebase/merge (refuses hard),
CH3 unstaged changes outside `_bmad-output/`, CH5 remote ahead of local.
`--auto-fix` performs only bounded remediation (branch from HEAD, stage
BMAD paths, `pull --rebase`); `--dry-run` never mutates anything.

## Configuration

`_bmad/bmad-pr/config.env` (flat `KEY=value`; env vars override the file,
flags override env). See
[`integration/config.env.example`](integration/config.env.example) for all
keys: backend selection, trunk, reviewer provider/trigger/score threshold,
timeouts. Reviewer providers are config profiles — integrating another
bot is configuration, not code.

## Development

```bash
scripts/check.sh   # the gate: bash -n, shellcheck, manifest checks, bats suite
tests/run.sh       # just the tests (vendors a pinned bats-core on first run)
git config core.hooksPath .githooks   # pre-commit = the same gate
```

BMAD planning artifacts for this rewrite (research, architecture spine,
epics) live under
[`_bmad-output/planning-artifacts/`](_bmad-output/planning-artifacts/).

## License

MIT — see [`LICENSE`](./LICENSE).

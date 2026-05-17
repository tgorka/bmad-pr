---
title: 'Wrap bmad-pr CLI in a Claude Code skill (/bmad-pr)'
type: 'feature'
created: '2026-05-17'
status: 'done'
route: 'one-shot'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-bmad-pr-core-and-ledger.md'
---

# Wrap bmad-pr CLI in a Claude Code skill

## Intent

**Problem:** The brainstorming framed `/bmad-pr` as a Claude Code slash-command skill (LLM-driven, loaded via the Skill tool). PRs #3 shipped only the CLI binary; the skill layer that gives `/bmad-pr` the slash-command UX did not exist. Cubic stamped PR #3 with 0 issues, but users still can't actually type `/bmad-pr` in Claude Code.

**Approach:** Add `.claude/skills/bmad-pr/SKILL.md` — a thin markdown wrapper auto-discovered by Claude Code when running inside this repo. The skill teaches Claude to (a) derive `--story`/`--phase`/`--run-id`/`--trunk-branch` from BMAD state in priority order (user message → active spec → sprint-status → most-recent artifact), (b) shell out to `bun src/cli/bmad-pr.ts` via Bash, and (c) surface the CLI's exit codes and refusal hints verbatim. No reimplementation; the CLI remains the source of truth for refusal contracts, atomic ledger writes, and gh/git plumbing.

## Suggested Review Order

**The skill itself**

- The contract a future Claude reads when `/bmad-pr` fires. Includes triggers, the 4-step derivation order, the flag quick-reference table, exit-code handling, and explicit anti-patterns ("don't shell out to `gh pr create` directly").
  [`.claude/skills/bmad-pr/SKILL.md`](../../.claude/skills/bmad-pr/SKILL.md)

**Verification**

- Parses the SKILL.md frontmatter with `Bun.YAML.parse` and asserts: parseable, `name` is kebab-case, `description` starts with "Use when…", the 1024-char frontmatter budget holds, and the body documents the two non-default modes (`--amend`, `--dry-run`).
  [`skill-frontmatter.test.ts`](../../src/skill/skill-frontmatter.test.ts)

- Compliance test (executed during development, not in CI): a no-context subagent given the skill + three sample requests produced (1) the right `--story --phase` invocation, (2) an `ASK:` clarifying question when state was missing, and (3) the full four-flag invocation including `--run-id` and `--trunk-branch`. All three passed.

**Discoverability**

- README now documents both surfaces (CLI and Skill) and points readers at the SKILL.md.
  [`README.md` — /bmad-pr section](../../README.md)

## Notes on what's NOT here

- **Plugin packaging.** This is a project-local skill (`.claude/skills/`). Distributing as a plugin (`bmad-stepper` integration) is a separate scope; see deferred-work.md once `/bmad-next` autoPR (G5) starts.
- **Skill testing harness in CI.** The compliance test ran via a one-shot subagent dispatch. A real "dispatch a subagent against the live SKILL.md and assert the produced command" harness is possible but out of scope here — the frontmatter test catches the structural-regression class.
- **Auto-derive from `_bmad-output/.stepper/state.yaml`.** The skill currently walks the static artifacts (specs, sprint-status). Reading the live stepper state is a natural follow-up once G5 wires in.

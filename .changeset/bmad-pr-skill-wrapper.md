---
"bmad-pr": minor
---

Add the `/bmad-pr` Claude Code skill at `.claude/skills/bmad-pr/SKILL.md`. Auto-loaded for Claude Code sessions inside this repo. Wraps the existing `bmad-pr` CLI — derives `--story`, `--phase`, `--run-id`, and `--trunk-branch` from BMAD state (user message → active spec → sprint-status → most-recent artifact), then dispatches via Bash and surfaces the CLI's exit codes and refusal hints verbatim. The CLI remains the source of truth.

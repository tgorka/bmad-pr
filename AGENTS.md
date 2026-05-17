# AGENTS.md

The contract for AI coding agents (Claude Code, Codex, etc.) and human contributors working on this repo.

## What this project is

A BMAD-method project. Planning, implementation, and retrospective artifacts live under `_bmad-output/` and ARE the spec — read them before making non-trivial changes. Use `/bmad-next` to advance one BMAD step at a time; use `/bmad-loop` to iterate.

## Repo layout

- `_bmad-output/` — BMAD artifacts (committed). Brainstorming, planning, implementation, tests, retros. Source of truth for "what we are building and why."
- `_bmad-output/.stepper/`, `.archive/`, `.runs/` — runtime caches (gitignored, regenerable).
- `_bmad/` — BMAD shared config (`config.yaml` committed; `config.user.yaml` is per-contributor and gitignored).
- `src/` — TypeScript source (when present). Tests colocated as `<source>.test.ts`.
- `biome.json`, `tsconfig.json`, `bunfig.toml`, `package.json` — runtime + tooling config.

## Quality gates

Every change must satisfy:

- `bun run check` exits 0 (Biome lint + `bun test`).
- `bunx tsc --noEmit` exits 0.
- Tests added or updated for any behavior change.
- Changeset entry added via `bun run changeset` for user-visible changes.

## Code conventions

- Files: `kebab-case.ts`. Tests colocated, named `<source>.test.ts`.
- TypeScript: `camelCase` for functions/variables, `PascalCase` for types (no `I` prefix), `SCREAMING_SNAKE_CASE` for constants.
- No `console.log` in runtime code (Biome enforces `noConsole` as an error). Use a logger module or stderr for one-off CLI status.
- No `any`. Strict mode is on; respect `noUncheckedIndexedAccess`.
- Async = `async/await`. Prefer Bun-native APIs (`Bun.file`, `Bun.write`, `Bun.YAML.parse`, `Bun.spawn`).
- Biome 2.4 only — no ESLint/Prettier.

## State + scope discipline

- Never write outside `_bmad-output/` and standard build dirs (`dist/`, `coverage/`, `node_modules/`).
- Never write to BMAD-installed files under `~/.claude/plugins/cache/bmad-method/` — read-only inputs.
- Atomic state writes (tmp + rename) when modifying anything under `_bmad-output/.stepper/`.

## Test patterns

- Colocate tests next to source (`<source>.test.ts`). No `tests/` dir inside `src/`.
- Filesystem-touching tests use `mkdtemp(path.join(os.tmpdir(), "bmad-pr-<concern>-"))` and clean up in `afterEach`.
- Tests never touch `_bmad-output/` (the project's own BMAD state).
- Unique test ID prefix per concern (e.g., `STORY_12_*`).

## When in doubt

Read the latest planning + implementation artifacts under `_bmad-output/` to find the in-flight story or spec. If the request conflicts with an existing artifact, surface the conflict to the user rather than silently re-deciding.

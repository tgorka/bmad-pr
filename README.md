# bmad-pr

A BMAD-method project. Planning, implementation, and test artifacts live under `_bmad-output/`; runtime tooling and code live at the repo root.

## Requirements

- [Bun](https://bun.sh) >= 1.3
- macOS or Linux (Windows via WSL)

## Quick Start

```bash
bun install --frozen-lockfile
bun run check   # Biome lint + tests (release-blocker gate)
```

## Scripts

| Script              | What it does                                              |
| ------------------- | --------------------------------------------------------- |
| `bun run check`     | Biome lint (CI mode) + `bun test`. The CI gate.           |
| `bun run lint`      | Biome lint without tests.                                 |
| `bun run format`    | Biome auto-format (writes changes).                       |
| `bun run test`      | Run the test suite (passes when no tests are present).    |
| `bun run test:watch`| Run the suite in watch mode.                              |
| `bun run changeset` | Create a Changeset entry describing a user-visible change.|

## BMAD Workflow

This project uses the [BMAD method](https://github.com/bmad-code-org/BMAD-METHOD) via the [bmad-stepper](https://github.com/tgorka/bmad-stepper) plugin for Claude Code. Run `/bmad-next` to advance one step at a time, or `/bmad-loop` to iterate. Generated artifacts under `_bmad-output/` are tracked in git (planning + implementation specs are the source of truth); runtime caches under `_bmad-output/.stepper/`, `.archive/`, `.runs/` are gitignored.

## Style Checker

Biome 2.4 enforces formatting (2-space indent, double quotes, semicolons) and lint rules (`noConsole`, `noUnusedVariables`, `noImplicitAnyLet`, `useExhaustiveDependencies`). The `_bmad-output/`, `_bmad/`, and build output directories are excluded from linting — see `biome.json`.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the development setup, PR flow, and code-style conventions. The [`AGENTS.md`](./AGENTS.md) file is the contract for AI coding agents working in this repo.

## License

MIT — see [`LICENSE`](./LICENSE).

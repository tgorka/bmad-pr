# Contributing

## Development Setup

1. Install Bun >= 1.3: `curl -fsSL https://bun.sh/install | bash` or `brew install oven-sh/bun/bun`.
2. Clone and install: `git clone <repo> && cd bmad-pr && bun install --frozen-lockfile`.
3. Verify the gate: `bun run check` should exit 0.

No build step — Bun runs `.ts` directly.

## PR Flow

1. Create a feature branch off `main`.
2. Make changes following the code style below.
3. Run `bun run check` locally — must exit 0 (Biome clean + tests pass).
4. Add a Changeset entry: `bun run changeset` for any user-visible change. Skip only for docs or chore-only PRs.
5. Open a PR using the template at `.github/PULL_REQUEST_TEMPLATE.md`.
6. CI runs on push; a green CI is required.

## Release Process

This repo uses [Changesets](https://github.com/changesets/changesets) for versioning. The flow:

1. Feature PRs land on `main`; each carries a Changeset entry under `.changeset/<name>.md`.
2. `.github/workflows/release.yml` auto-opens (or updates) a "Version Packages" PR that aggregates pending Changesets into a `CHANGELOG.md` entry + version bump.
3. Merging that PR triggers `release.yml` to tag the release and create a GitHub Release.

The repository is private (`"access": "restricted"` in `.changeset/config.json`) — no npm publish.

## Code Style

- **Files:** `kebab-case.ts`. Tests colocated as `<source>.test.ts`.
- **TypeScript:** `camelCase` for functions/variables, `PascalCase` for types (no `I` prefix), `SCREAMING_SNAKE_CASE` for constants.
- **Async:** always `async/await`. Prefer Bun-native APIs (`Bun.file`, `Bun.write`, `Bun.YAML.parse`, `Bun.spawn`).
- **Errors:** throw typed `Error` subclasses; avoid `Result<T,E>` unless there is a specific reason.
- **No `console.log`** in runtime code — surface via the project's logger (or stderr for one-off CLI status).
- **Biome 2.4 only** (no ESLint/Prettier). `biome.json` enforces strict rules. Run `bun run check` to verify.

## Tests

- Colocate tests as `<source>.test.ts` next to source. No `tests/` directory inside `src/`.
- Filesystem-touching tests use `mkdtemp(path.join(os.tmpdir(), "bmad-pr-..."))` + cleanup in `afterEach`.
- Tests never touch `_bmad-output/` (the project's own BMAD state).

## BMAD Artifacts

This project dogfoods BMAD. Artifacts under `_bmad-output/` (planning, implementation, tests, retros) are the source of truth and ARE committed. Runtime caches (`_bmad-output/.stepper/`, `.archive/`, `.runs/`) are gitignored. When a PR modifies a BMAD artifact, reference the relevant story/spec ID in the PR description.

## Reporting Issues

- **Bug:** open an issue using `.github/ISSUE_TEMPLATE/bug.md`.
- **Feature request:** use `.github/ISSUE_TEMPLATE/feature.md`.
- **Security:** see `SECURITY.md` for the private channel.

## License

By contributing, you agree your contributions are licensed under MIT (see `LICENSE`).

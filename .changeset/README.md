# Changesets

This folder is managed by [`@changesets/cli`](https://github.com/changesets/changesets). Each user-visible change should add a Changeset entry via `bun run changeset` describing the change in user-facing terms. The `release.yml` workflow aggregates pending Changesets into a "Version Packages" PR; merging that PR bumps the version, updates `CHANGELOG.md`, and pushes a git tag.

This repository is **private** (`"access": "restricted"`) — Changesets manages versions and changelog only, no npm publish.

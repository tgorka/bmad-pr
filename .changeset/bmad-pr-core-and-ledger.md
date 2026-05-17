---
"bmad-pr": minor
---

Add `bmad-pr` CLI (G1+G3 slice): opens or amends a draft pull request via
`gh` and persists the URL into a stories-file PR ledger at
`_bmad-output/stories/<epic>.<story>.md`. Flags: `--story`, `--phase`,
`--run-id`, `--amend`, `--dry-run`, `--trunk-branch`, `--help`. Defaults
auto-detect open vs amend via the ledger; `--amend` is force-amend.
Deferred to follow-up specs: `gt` stacking, `hub`/plain-`git` adapters,
git-safety preflight, `/bmad-next` autoPR hook, PR body template engine.

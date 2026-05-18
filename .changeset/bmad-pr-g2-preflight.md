---
"bmad-pr": minor
---

Add G2 git-safety preflight to `bmad-pr` CLI. Before any state-changing
operation (push, gh create, gh edit), four detectors run in order:

- **CH1** — detached HEAD
- **CH2** — interactive rebase or merge in progress (refusal-only)
- **CH3** — unstaged changes outside `_bmad-output/`
- **CH5** — upstream branch ahead of HEAD

Refusals emit a single-line `Refuse: …` hint on stderr (exit 2). The
new `--auto-fix` flag attempts safe remediation for CH1 (branch from
current HEAD), CH3 (stage `_bmad-output/` only; never `git add -A`),
and CH5 (`git pull --rebase`; abort on conflict). CH2 is never
auto-fixed; the user must resolve the rebase/merge manually. Auto-fix
re-runs preflight once after the fix and refuses if anything still
fails. Under `--dry-run`, stdout begins with `preflight: ok` when all
detectors pass.

CH4 (`gt restack` mid-flight) stays deferred to the G4 stacked-PR
slice. CH6–CH14 remain deferred per the brainstorming.

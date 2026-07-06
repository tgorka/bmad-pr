# Research: bmad-pr ground-up rewrite as a BMAD-style Claude plugin

Date: 2026-07-06. Sources: locally installed plugins (bmad 6.10.0.0, cubic-loop 0.1.0,
linear-cli 2.0.0), clones of bmad-code-org/bmad-loop and bmad-code-org/bmad-automator,
cubic.dev docs + JSON schema, GitHub CLI v2.95.0 and Graphite CLI v1.8.6 (verified live),
and the archived v0 TypeScript implementation (git tag `v0-ts-cli`).

## 1. Claude plugin format (verified against installed plugins)

Minimum viable plugin — repo root **is** the plugin (cubic-loop shape):

- `.claude-plugin/plugin.json` — `{name, version, description, author, homepage,
  repository, license, keywords, "skills": "./skills/"}`. `skills`/`commands` accept a
  directory string or a path array. Official schema:
  `https://json.schemastore.org/claude-code-plugin-manifest.json`.
- `.claude-plugin/marketplace.json` — `{name, description, owner, plugins: [{name,
  source: "./", description}]}`. Lets users `claude plugin marketplace add <repo>`.
- `skills/<name>/SKILL.md` — YAML frontmatter `name` + `description` (description carries
  explicit trigger phrases). Optional `allowed-tools`. Skills may ship `references/`,
  `scripts/`, `assets/` subdirs. `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin root at
  runtime.

BMAD-module extras (bmad-loop / bmad-automator pattern): `module.yaml` at root
(`code`, `name`, `module_version`, per-variable `prompt`/`default`/`user_setting`),
`module-help.csv` (columns: `module,skill,display-name,menu-code,description,action,args,
phase,preceded-by,followed-by,required,output-location,outputs`), and a `<module>-setup`
skill that merges a module section into `_bmad/config.yaml` (anti-zombie: delete section,
rewrite) + merges `module-help.csv`.

## 2. Integration points "after reviews" (the placement requirement)

Three sanctioned mechanisms, all confirmed in installed bmad 6.10.0.0:

1. **quick-dev / dev-auto terminal hook.** Both `bmad-quick-dev` (step-05) and
   `bmad-dev-auto` (HALT protocol) end with: resolve `workflow.on_complete` via
   `_bmad/scripts/resolve_customization.py`; if non-empty, follow it as the final
   instruction. Override files: `_bmad/custom/bmad-quick-dev.toml` and
   `_bmad/custom/bmad-dev-auto.toml` with `[workflow] on_complete = "..."`.
   Three-layer TOML merge: skill `customize.toml` → `_bmad/custom/<skill>.toml` (team) →
   `_bmad/custom/<skill>.user.toml` (personal).
2. **bmad-loop orchestrator plugins.** Folder-drop `.bmad-loop/plugins/<name>/plugin.toml`
   with `[plugin] name/api_version`, `[[settings]]`, and injected workflow sessions:
   `[workflows.<x>] stage = "post_review_result" | "pre_commit_gate" | "post_dev_phase"`,
   `role = "dev"|"review"`, `prompt = "/skill {story_key}"`, `blocking = true|false`.
   `post_review_result` fires after a review verdict (only when the review loop ran);
   `pre_commit_gate` fires unconditionally before every commit and is defer-safe — the
   right stage for an external gate that must always run. Env available to hooks:
   `BMAD_LOOP_STORY_KEY`, `BMAD_LOOP_WORKTREE`, `BMAD_LOOP_SETTING_<KEY>`.
   Loop state machine: `dev → verify → review → verify → COMMITTING`; review phase ends at
   `REVIEW_VERIFY → COMMITTING`.
3. **Help-system phase ordering.** `module-help.csv` rows carry `phase`, `preceded-by`,
   `followed-by` — registering bmad-pr with `preceded-by: code-review` places it after
   reviews in the long methodology's guidance (`/bmad-help` recommendations).

## 3. BMAD review-findings formats (what our bridge must emit)

- `bmad-code-review` canonical story items (written under `### Review Findings` in the
  story file): `- [ ] [Review][Patch] <Title> [<file>:<line>]`,
  `- [ ] [Review][Decision] <Title> — <Detail>`, `- [x] [Review][Defer] <Title> ...`.
  Severity `low|medium|high` is assigned by consequence; triage buckets
  `decision_needed | patch | defer | dismiss`.
- Loop dev/review sessions append a `## Review Triage Log` to the spec (buckets
  `intent_gap | bad_spec | patch | defer | reject`) and push deferrals into
  `{implementation_artifacts}/deferred-work.md` as `### DW-<seq>:` entries
  (`origin/location/severity/reason/status`), append-only, `seen-again:` dedupe.

Emitting `[Review][Patch]`-style items plus DW-compatible defers covers both consumption
paths (interactive code-review flow and the unattended loop).

## 4. cubic.dev mechanics (primary reviewer provider)

- GitHub App `cubic-dev-ai`; review author matches `^cubic.*\[bot\]$` (GraphQL logins come
  **without** the `[bot]` suffix; REST includes it). Detect the login dynamically.
- Lifecycle: trigger → 👀 reaction → **check run named `^cubic`** (`queued` →
  `in_progress` → `completed` + conclusion) → bot PR review (state
  `COMMENTED|CHANGES_REQUESTED|APPROVED`) + inline review threads.
- Trigger: PR comment mentioning the bot handle; any phrasing works and extra text is
  forwarded as one-off review context. Official handle `@cubic-dev-ai`; this repo's
  operating convention is `@cubic-dev re-review` — **the trigger comment must be
  configurable**. Re-trigger on an unchanged, already-reviewed SHA is deduped by cubic;
  only trigger when latest check run is `completed`/missing AND HEAD SHA differs from the
  last-reviewed SHA (exception: after resolving threads with no code change, a prod
  works).
- `PR score: N/10` is **not native** — it is injected by `reviews.custom_instructions` in
  `cubic.yaml`. Treat the score as a repo-configured contract; "review completed but no
  score" = misconfiguration signal. Native analog: `merge_confidence_summary` (1–5).
- Thread resolution state is GraphQL-only (`reviewThreads.isResolved`); resolve via
  `resolveReviewThread` mutation (batchable ~20/aliased mutation; partial failures return
  per-alias errors). `resolve_threads_when_addressed: true` (default) makes cubic
  auto-resolve fixed threads on the next pass.
- Approval stamp: bot review with `state == "APPROVED"` (when `auto_approve_behavior:
  live`).
- Timing heuristics (from cubic-loop skill): settle ~5 s after push, poll check-runs every
  10 s, per-iteration timeout 1800 s, max 5 fix iterations. Skip diagnostics: "skipping
  review" comment (ignore rules), draft PR + `check_drafts: false`,
  `external_contributors_require_manual_review`.
- No public REST API for results — machine access is via GitHub (check-runs, reviews,
  review threads). `cubic.yaml` schema published at
  `https://cubic.dev/schema/cubic-repository-config.schema.json`.

## 5. Provider abstraction (cubic / CodeRabbit / Greptile)

A reviewer provider reduces to a profile:

| Field | cubic | CodeRabbit | Greptile |
|---|---|---|---|
| bot login regex | `^cubic` | `^coderabbitai` | `^greptile` |
| trigger comment | `@cubic-dev-ai` (configurable) | `@coderabbitai review` / `full review` | `@greptileai` |
| in-progress probe | check run `^cubic` | none (edits its own comment) | status check "Greptile" |
| completion probe | check run `completed` | new bot review since trigger | status check completes |
| findings | inline threads + summary review | walkthrough + inline comments | summary + inline comments |
| score extractor | `^PR score: ([0-9]+)/10` (repo contract) | "Actionable comments posted: N" | confidence score |
| resolve | GraphQL `resolveReviewThread` / auto | `@coderabbitai resolve` | GraphQL |

GraphQL `reviewThreads` + `resolveReviewThread` machinery is provider-agnostic — only the
author filter changes. CodeRabbit has no check run, so a completion detector needs the
"newest bot review after trigger timestamp" fallback path.

## 6. Stacked PRs + CI monitoring — verified command recipes

### gh backend (gh 2.95.0)
- Create stacked draft: `git push -u origin "$CUR"` then `gh pr create --draft --base
  "$PREV" --head "$CUR" --title … --body …` (always pass `--head` in scripts). Pin for
  later calls: `git config branch."$CUR".gh-merge-base "$PREV"`.
- Existing-PR probe: `gh pr list --head "$CUR" --state open --json number,baseRefName,url`
  (`gh pr view` alone resolves merged/closed PRs too; exits 1 + "no pull requests found"
  when none).
- Retarget after parent merge: `gh pr edit N --base "$NEW_BASE"` (idempotent; GitHub may
  auto-retarget when the merged head branch is deleted — expect it, don't rely on it).
  Local: `git rebase --onto origin/$NEW_BASE origin/$OLD_PARENT_HEAD $BRANCH && git push
  --force-with-lease`.
- Checks: `gh pr checks N --json name,state,bucket,link,description` — normalize on
  `bucket ∈ {pass, fail, pending, skipping, cancel}`. Exit codes: 0 pass, 1 fail, 8
  pending. `--watch` has `--interval`/`--fail-fast` but **no timeout** → poll-loop with
  deadline + backoff instead; treat `[]`/exit-8 right after push as pending (grace
  period — suites register seconds after push).
- Review threads (resolution state is GraphQL-only): `gh api graphql --paginate` on
  `reviewThreads(first:50){ pageInfo{hasNextPage endCursor} nodes{ id isResolved
  isOutdated path line comments(first:50){ nodes{ databaseId author{login __typename}
  body createdAt url }}}}` — `__typename == "Bot"` identifies bots.
- Top-level bot summaries: REST `repos/$O/$R/issues/$N/comments` (`.user.type == "Bot"`).
- Comment: `gh pr comment N --body …`. Resolve: `resolveReviewThread(input:{threadId})`.
  Thread reply: REST `pulls/$N/comments/$DATABASE_ID/replies`.
- PR state: `gh pr view N --json state,mergedAt,mergeStateStatus,mergeable,baseRefName`.
  Branch-deleted probe without API quota: `git ls-remote --exit-code --heads origin $BR`.
- Rate limits: REST 5000 req/h, GraphQL 5000 pts/h; poll ≥15 s per PR, serialize
  mutations; introspect `gh api rate_limit`.

### gt backend (gt 1.8.6)
- `gt create <name> -m "…" [-o <parent>]`; `gt submit --stack --no-interactive --draft
  --no-edit` (new PRs default draft under `--no-interactive`; bases set from tracked
  parents — never pass a base manually; `--restack` to restack first; `--dry-run`
  supported).
- After parent merge: `gt sync -f --delete-all --no-interactive` (deletes merged branches,
  reparents children) → `gt submit --stack --no-interactive` (updates PR bases). Conflicts:
  `gt add . && gt continue`.
- Untracked-branch trap: branches created outside gt fail gt ops; fix with
  `gt track --parent "$PREV"` first.
- Init detection (verified live, worktree-safe): config lives at
  `$(git rev-parse --git-common-dir)/.graphite_repo_config` (use `--git-common-dir`, NOT
  `--git-dir`, in linked worktrees). Presence of the file = repo opted into gt. Trunk:
  `jq -r .trunk` on it. Non-interactive init: `gt init --trunk main`.

### Backend selection
`gt` only when binary present AND repo gt-initialized (explicit opt-in; mixing gt/gh
mid-stack is unsafe because gt owns branch metadata and force-pushes) → else `gh` when
binary present AND `gh auth status` passes → else bare `git` (push branch, print manual
PR instructions). Non-GitHub remote → `git`. gh remains useful on the gt path for
read-only queries (checks/threads) — gt has no JSON query surface.

## 7. Decision carry-over from v0 (tag `v0-ts-cli`)

Kept verbatim: exit-code contract (0 ok / 2 refuse / 1 unexpected), preflight CH1
(detached HEAD, auto-fix `git switch -c bmad-pr/<sha>-<ts>`), CH2 (mid-rebase/merge via
`$(git rev-parse --git-dir)/rebase-merge|rebase-apply|MERGE_HEAD`, refuse hard), CH3
(dirty tree outside `_bmad-output/` via `git status --porcelain -z`, auto-fix stages only
`_bmad-output/`), CH5 (upstream ahead via `git rev-list --count HEAD..@{u}`, auto-fix
`git pull --rebase` then re-check CH2), bounded single-attempt `--auto-fix`, `--dry-run`
never auto-fixes, amend-not-recreate semantics (D3), draft-by-default (D8), title
`BMAD: <epic>.<story> <phase>`, `BMAD-Run-Id` body trailer (A5), per-story PR granularity
(D1), tool precedence flag > env > config > auto-detect (D2).

Superseded: YAML-frontmatter ledger in story files (Q1) → jq-owned JSON ledger under
`_bmad-output/pr/` (no YAML parser in bash; story files stay untouched by PR tooling to
avoid write races with bmad sessions). G4 (gt stacking) and the monitor/ingest/re-review
cycle move from "deferred" into v1 scope — they are the point of this rewrite.

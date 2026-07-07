# Reviewer & PR API recipes

Verified against gh 2.95, gt 1.8.6, cubic.dev docs (2026-07). The CLI wraps
all of this — these notes are for diagnosis when something misbehaves.

## cubic.dev lifecycle on a PR

1. **Trigger**: any PR comment mentioning the bot handle (official:
   `@cubic-dev-ai`; this plugin's default trigger comment is configurable,
   `BMAD_PR_REVIEWER_TRIGGER`, default `@cubic-dev re-review`). Extra text
   in the comment is forwarded as one-off review context.
   `@cubic-dev-ai ultrareview` runs a ~30-min deep review.
2. **In progress**: a GitHub check run named `^cubic` (case-insensitive)
   goes `queued → in_progress → completed`. Cubic also reacts 👀 to the
   trigger comment.
3. **Findings**: a bot PR review (author matches `^cubic`, type Bot; GraphQL
   logins have no `[bot]` suffix, REST logins do) plus inline review
   threads. `PR score: N/10` in the review body is NOT native cubic — it is
   injected via `reviews.custom_instructions` in the target repo's
   `cubic.yaml`. A completed review with no score means that instruction is
   missing there.
4. **Dedupe**: re-triggering an unchanged, already-reviewed SHA is a no-op
   for cubic. Exception: after resolving threads without a code change, a
   prod does work (the CLI models this: `rereview` triggers when threads
   were resolved or `--force`).
5. **Approval**: with `auto_approve_behavior: live`, cubic submits a real
   `APPROVED` review.
6. **Skips**: draft PR with `check_drafts: false` (cubic's default),
   `ignore` rules (files/branches/labels/titles), or
   `external_contributors_require_manual_review` — watch reports these as
   verdict `absent` (exit 6). Look for a "skipping review" bot comment.

## Provider matrix (for BMAD_PR_REVIEWER=generic)

| | cubic | CodeRabbit | Greptile |
|---|---|---|---|
| BOT_REGEX | `^cubic` | `^coderabbitai` | `^greptile` |
| TRIGGER | `@cubic-dev-ai` | `@coderabbitai review` | `@greptileai` |
| CHECK_REGEX | `^cubic` | — (none) | `^greptile` |
| COMPLETION | `check-run` | `bot-review` | `check-run` |
| SCORE_REGEX | `PR score: ([0-9]+)/10` (repo contract) | — | — |

## Raw commands the CLI uses

Check-run state for a SHA (gh api --jq cannot bind vars → pipe to jq):

```bash
gh api "repos/$OWNER/$REPO/commits/$SHA/check-runs" |
  jq -r --arg re '^cubic' \
    '[.check_runs[] | select(.name | test($re; "i"))] | last | .status // "missing"'
```

CI buckets (normalize on `bucket`, not `state`; exit codes lie — 1 can mean
"a check failed" or "command failed", 8 means pending):

```bash
gh pr checks "$PR" --json name,bucket,link,description
```

Unresolved bot threads (resolution state is GraphQL-only; pages merge with
`jq -s`):

```bash
gh api graphql --paginate -f owner=$O -f repo=$R -F pr=$N -f query='
query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
    reviewThreads(first:50,after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{id isResolved isOutdated path line
            comments(first:1){nodes{author{login} body}}}}}}}'
```

Resolve threads (batch ~20 aliased mutations; partial failures are
per-alias):

```bash
gh api graphql -f query='mutation {
  t0: resolveReviewThread(input:{threadId:"..."}){thread{isResolved}}
  t1: resolveReviewThread(input:{threadId:"..."}){thread{isResolved}} }'
```

Bot reviews / score / approval:

```bash
gh api --paginate "repos/$O/$R/pulls/$N/reviews" | jq -s 'add // []'
```

## Rate-limit etiquette

REST 5000 req/h, GraphQL 5000 pts/h. The CLI polls with 15s→60s backoff;
keep manual polling ≥15s per PR and serialize mutations. Introspect:
`gh api rate_limit`.

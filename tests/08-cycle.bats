#!/usr/bin/env bats
# End-to-end-ish tests for watch / ingest / rereview against the gh stub.

load helpers/common
load helpers/gh-stub

setup() {
  stub_init
  install_gh_stub
  REPO="$(make_repo)"
  add_origin "$REPO" >/dev/null
  cd "$REPO"
  export BMAD_PR_TOOL=gh BMAD_PR_REVIEWER=cubic BMAD_PR_POLL_INTERVAL=1
  export BMAD_PR_REGISTER_GRACE=1
  git switch -qc bmad/story/3.2
  git commit -q --allow-empty -m "story work"
  git push -qu origin bmad/story/3.2
  HEAD_SHA="$(git rev-parse HEAD)"
  export GH_STUB_HEAD_SHA="$HEAD_SHA"
  mkdir -p "$REPO/_bmad-output/pr"
  jq -n '
    {schema: 1, story: "3.2", branch: "bmad/story/3.2", parentBranch: null,
     parentSha: null, parentPr: null,
     pr: {number: 42, url: "https://github.com/o/r/pull/42", state: "open"},
     phase: "dev-story", runId: "run-1", tool: "gh",
     reviewer: {provider: "cubic", lastReviewedSha: null, lastScore: null, approved: false},
     openedAt: "2026-07-01T10:00:00Z", lastAmendedAt: "2026-07-01T10:00:00Z"}' \
    >"$REPO/_bmad-output/pr/3.2.json"
}

set_reviewed() { # sha
  jq --arg sha "$1" '.reviewer.lastReviewedSha = $sha' \
    "$REPO/_bmad-output/pr/3.2.json" >"$REPO/_bmad-output/pr/3.2.json.new"
  mv "$REPO/_bmad-output/pr/3.2.json.new" "$REPO/_bmad-output/pr/3.2.json"
}

@test "watch: green checks + completed clean review → exit 0" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  export GH_STUB_CHECKRUNS='{"check_runs":[{"name":"cubic — AI code review","status":"completed","started_at":"2026-07-06T11:30:00Z","completed_at":"2026-07-06T12:00:00Z"}]}'
  export GH_STUB_REVIEWS='[{"user":{"login":"cubic-dev-ai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T10:00:00Z","commit_id":"'"$HEAD_SHA"'","body":"PR score: 9/10\nLooks good."}]'
  run "$BMAD_PR_BIN" watch --story 3.2
  [ "$status" -eq 0 ]
  entry="$REPO/_bmad-output/pr/3.2.json"
  [ "$(jq -r '.reviewer.lastScore' "$entry")" = "9" ]
  [ "$(jq -r '.reviewer.lastReviewedSha' "$entry")" = "$HEAD_SHA" ]
  [ -f "$REPO/_bmad-output/pr/3.2-findings.md" ]
}

@test "watch: failing checks → findings file + exit 4" {
  export GH_STUB_CHECKS='[{"name":"test","bucket":"fail","link":"https://ci/1","description":"unit"}]'
  run "$BMAD_PR_BIN" watch --story 3.2
  [ "$status" -eq 4 ]
  grep -q 'CI check failing: test' "$REPO/_bmad-output/pr/3.2-findings.md"
  # no reviewer output existed → lastReviewedSha must stay null so the
  # first rereview trigger isn't deduped away
  [ "$(jq -r '.reviewer.lastReviewedSha' "$REPO/_bmad-output/pr/3.2.json")" = "null" ]
}

@test "watch: unresolved reviewer threads → exit 3" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  export GH_STUB_CHECKRUNS='{"check_runs":[{"name":"cubic","status":"completed","started_at":"2026-07-06T11:30:00Z","completed_at":"2026-07-06T12:00:00Z"}]}'
  export GH_STUB_GRAPHQL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"T_a","isResolved":false,"isOutdated":false,"path":"x.sh","line":3,"comments":{"nodes":[{"author":{"login":"cubic-dev-ai"},"body":"Bug here"}]}}]}}}}}'
  run "$BMAD_PR_BIN" watch --story 3.2
  [ "$status" -eq 3 ]
  grep -q 'thread:T_a' "$REPO/_bmad-output/pr/3.2-findings.md"
}

@test "watch: completed review with score below threshold → exit 3" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  export GH_STUB_CHECKRUNS='{"check_runs":[{"name":"cubic","status":"completed","started_at":"2026-07-06T11:30:00Z","completed_at":"2026-07-06T12:00:00Z"}]}'
  export GH_STUB_REVIEWS='[{"user":{"login":"cubic-dev-ai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T10:00:00Z","commit_id":"'"$HEAD_SHA"'","body":"PR score: 5/10"}]'
  run "$BMAD_PR_BIN" watch --story 3.2
  [ "$status" -eq 3 ]
  [ "$(jq -r '.reviewer.lastScore' "$REPO/_bmad-output/pr/3.2.json")" = "5" ]
}

@test "watch: reviewer never appears → exit 6 (absent)" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  # no cubic check run ever registers; the tiny --timeout bounds the grace
  run "$BMAD_PR_BIN" watch --story 3.2 --timeout 2
  [ "$status" -eq 5 ] || [ "$status" -eq 6 ]
}

@test "ingest standalone writes findings and exits with verdict" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  export GH_STUB_REVIEWS='[{"user":{"login":"cubic-dev-ai[bot]","type":"Bot"},"state":"APPROVED","submitted_at":"2026-07-06T10:00:00Z","commit_id":"'"$HEAD_SHA"'","body":"PR score: 10/10"}]'
  run "$BMAD_PR_BIN" ingest --story 3.2 --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.verdict' <<<"$output")" = "green" ]
  [ "$(jq -r '.approved' <<<"$output")" = "true" ]
  [ "$(jq -r '.score' <<<"$output")" = "10" ]
}

@test "watch: completed review WITHOUT the configured score → exit 3, not green" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  export GH_STUB_CHECKRUNS='{"check_runs":[{"name":"cubic","status":"completed","started_at":"2026-07-06T11:30:00Z","completed_at":"2026-07-06T12:00:00Z"}]}'
  export GH_STUB_REVIEWS='[{"user":{"login":"cubic-dev-ai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T12:00:00Z","commit_id":"'"$HEAD_SHA"'","body":"Looks fine overall."}]'
  run "$BMAD_PR_BIN" watch --story 3.2
  [ "$status" -eq 3 ]
  grep -q 'score:missing' "$REPO/_bmad-output/pr/3.2-findings.md"
}

@test "status dies when the checks state cannot be fetched" {
  export GH_STUB_CHECKS='null'
  run "$BMAD_PR_BIN" status --story 3.2
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch CI checks"* ]]
}

@test "watch: completed check run from BEFORE the re-review trigger doesn't count" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  # run completed at 12:00, but the re-review was triggered at 13:00 —
  # watch must keep waiting for the new run, not ingest pre-trigger state
  export GH_STUB_CHECKRUNS='{"check_runs":[{"name":"cubic","status":"completed","started_at":"2026-07-06T11:30:00Z","completed_at":"2026-07-06T12:00:00Z"}]}'
  jq '.reviewer.lastTriggeredAt = "2026-07-06T13:00:00Z"' \
    "$REPO/_bmad-output/pr/3.2.json" >"$REPO/_bmad-output/pr/3.2.json.new"
  mv "$REPO/_bmad-output/pr/3.2.json.new" "$REPO/_bmad-output/pr/3.2.json"
  run "$BMAD_PR_BIN" watch --story 3.2 --timeout 2
  [ "$status" -eq 5 ] || [ "$status" -eq 6 ]
}

@test "rereview --dry-run plans without pushing, resolving, or commenting" {
  set_reviewed "0000000000000000000000000000000000000000"
  git commit -q --allow-empty -m "pending fix"
  run "$BMAD_PR_BIN" rereview --story 3.2 --resolve-addressed --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan: resolve addressed threads=true"* ]]
  gh_not_called "pr comment"
  gh_not_called "resolveReviewThread"
  # pending commit was NOT pushed
  [ "$(git rev-list --count '@{u}..HEAD')" = "1" ]
}

@test "rereview: same SHA, nothing resolved → no trigger (dedupe R12)" {
  set_reviewed "$HEAD_SHA"
  run "$BMAD_PR_BIN" rereview --story 3.2
  [ "$status" -eq 0 ]
  [[ "$output" == *"already sent for review"* ]]
  gh_not_called "pr comment"
}

@test "rereview: same SHA with --force triggers" {
  set_reviewed "$HEAD_SHA"
  run "$BMAD_PR_BIN" rereview --story 3.2 --force
  [ "$status" -eq 0 ]
  gh_called "pr comment 42" "@cubic-dev re-review"
}

@test "rereview: new SHA triggers and records it" {
  set_reviewed "0000000000000000000000000000000000000000"
  run "$BMAD_PR_BIN" rereview --story 3.2 --comment "focus on error handling"
  [ "$status" -eq 0 ]
  gh_called "pr comment 42" "@cubic-dev re-review focus on error handling"
  [ "$(jq -r '.reviewer.lastReviewedSha' "$REPO/_bmad-output/pr/3.2.json")" = "$HEAD_SHA" ]
}

@test "rereview: review already running → no duplicate trigger" {
  set_reviewed "0000000000000000000000000000000000000000"
  export GH_STUB_CHECKRUNS='{"check_runs":[{"name":"cubic","status":"in_progress"}]}'
  run "$BMAD_PR_BIN" rereview --story 3.2
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
  gh_not_called "pr comment"
}

@test "rereview --resolve-addressed resolves checked threads then triggers" {
  set_reviewed "$HEAD_SHA" # same SHA, but resolutions justify a re-prod
  cat >"$REPO/_bmad-output/pr/3.2-findings.md" <<'EOF'
- [x] [Review][Patch] fixed [a.sh:1] <!-- thread:T_fixed1 -->
- [x] [Review][Patch] fixed [b.sh:2] <!-- thread:T_fixed2 -->
- [ ] [Review][Patch] open [c.sh:3] <!-- thread:T_open -->
EOF
  run "$BMAD_PR_BIN" rereview --story 3.2 --resolve-addressed
  [ "$status" -eq 0 ]
  gh_called "resolveReviewThread" "T_fixed1"
  gh_called "resolveReviewThread" "T_fixed2"
  gh_not_called "T_open"
  gh_called "pr comment 42"
}

@test "rereview pushes pending local commits before triggering" {
  set_reviewed "0000000000000000000000000000000000000000"
  git commit -q --allow-empty -m "fix findings"
  run "$BMAD_PR_BIN" rereview --story 3.2
  [ "$status" -eq 0 ]
  [ "$(git rev-list --count '@{u}..HEAD')" = "0" ]
}

@test "watch: score and approval for an older commit are stale and don't count" {
  export GH_STUB_CHECKS='[{"name":"ci","bucket":"pass"}]'
  export GH_STUB_CHECKRUNS='{"check_runs":[{"name":"cubic","status":"completed","started_at":"2026-07-06T11:30:00Z","completed_at":"2026-07-06T12:00:00Z"}]}'
  export GH_STUB_REVIEWS='[{"user":{"login":"cubic-dev-ai[bot]","type":"Bot"},"state":"APPROVED","submitted_at":"2026-07-06T10:00:00Z","commit_id":"olderolderolderolderolderolderolderolder","body":"PR score: 10/10"}]'
  run "$BMAD_PR_BIN" watch --story 3.2
  [ "$status" -eq 0 ]
  entry="$REPO/_bmad-output/pr/3.2.json"
  [ "$(jq -r '.reviewer.lastScore' "$entry")" = "null" ]
  [ "$(jq -r '.reviewer.approved' "$entry")" = "false" ]
}

@test "rereview refuses from the wrong branch" {
  git switch -qc feature/elsewhere
  git commit -q --allow-empty -m "unrelated"
  run "$BMAD_PR_BIN" rereview --story 3.2
  [ "$status" -eq 2 ]
  [[ "$output" == *"belongs to branch bmad/story/3.2"* ]]
  gh_not_called "pr comment"
}

@test "watch refuses when ledger has no PR number" {
  jq '.pr.number = null' "$REPO/_bmad-output/pr/3.2.json" >"$REPO/_bmad-output/pr/x.json"
  mv "$REPO/_bmad-output/pr/x.json" "$REPO/_bmad-output/pr/3.2.json"
  run "$BMAD_PR_BIN" watch --story 3.2
  [ "$status" -eq 2 ]
  [[ "$output" == *"no recorded PR number"* ]]
}

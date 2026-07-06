#!/usr/bin/env bats

load helpers/common

setup() {
  export LIB_SOURCE_DIR="$LIB_DIR"
  source "$LIB_DIR/common.sh"
  source "$LIB_DIR/config.sh"
  source "$LIB_DIR/ledger.sh"
  source "$LIB_DIR/checks.sh"
  source "$LIB_DIR/findings.sh"
  REPO="$(make_repo)"
  cd "$REPO"
  config_load "$REPO"
}

@test "checks_aggregate: empty → none" {
  [ "$(echo '[]' | checks_aggregate)" = "none" ]
}

@test "checks_aggregate: any fail wins" {
  json='[{"bucket":"pass"},{"bucket":"fail"},{"bucket":"pending"}]'
  [ "$(echo "$json" | checks_aggregate)" = "fail" ]
}

@test "checks_aggregate: cancel counts as fail" {
  [ "$(echo '[{"bucket":"cancel"}]' | checks_aggregate)" = "fail" ]
}

@test "checks_aggregate: pending beats pass" {
  json='[{"bucket":"pass"},{"bucket":"pending"}]'
  [ "$(echo "$json" | checks_aggregate)" = "pending" ]
}

@test "checks_aggregate: all pass or skipping → pass" {
  json='[{"bucket":"pass"},{"bucket":"skipping"}]'
  [ "$(echo "$json" | checks_aggregate)" = "pass" ]
}

@test "checks_snapshot yields null on gh failure (not a false-green [])" {
  stub_init
  make_stub gh <<'EOF'
echo "HTTP 502" >&2
exit 1
EOF
  [ "$(checks_snapshot 42)" = "null" ]
}

@test "checks_aggregate/failing treat null as pending with no failures" {
  [ "$(echo null | checks_aggregate)" = "pending" ]
  [ "$(echo null | checks_failing)" = "[]" ]
}

@test "findings_render emits a score finding when below threshold" {
  run findings_render 3.2 42 '[]' '[]' 5 false
  [ "$status" -eq 0 ]
  [[ "$output" == *"- [ ] [Review][Patch] Reviewer score 5/10 is below threshold 8"* ]]
  [[ "$output" != *"None — the PR is clean"* ]]
}

@test "findings_render approved PR is clean even with low score" {
  run findings_render 3.2 42 '[]' '[]' 5 true
  [ "$status" -eq 0 ]
  [[ "$output" == *"None — the PR is clean"* ]]
}

@test "findings_render emits BMAD [Review][Patch] items with thread tags" {
  threads='[{"id":"PRRT_abc","path":"src/a.sh","line":12,"author":"cubic-dev-ai",
             "body":"**Unquoted variable**\nThis can word-split.\nQuote it."}]'
  run findings_render 3.2 42 "$threads" '[]' 7 false
  [ "$status" -eq 0 ]
  [[ "$output" == *"- [ ] [Review][Patch] Unquoted variable [src/a.sh:12] <!-- thread:PRRT_abc -->"* ]]
  [[ "$output" == *"> This can word-split."* ]]
  [[ "$output" == *"Reviewer score: 7/10 (threshold: 8)"* ]]
  [[ "$output" == *"Unresolved reviewer threads: 1"* ]]
}

@test "findings_render emits failing checks as findings" {
  checks='[{"name":"test","bucket":"fail","link":"https://ci/run/1","description":"unit tests"}]'
  run findings_render 3.2 42 '[]' "$checks" "" false
  [ "$status" -eq 0 ]
  [[ "$output" == *"- [ ] [Review][Patch] CI check failing: test — unit tests <!-- check:test -->"* ]]
  [[ "$output" == *"https://ci/run/1"* ]]
  [[ "$output" == *"Reviewer score: n/a"* ]]
}

@test "findings_render clean PR says none" {
  run findings_render 3.2 42 '[]' '[]' 9 true
  [ "$status" -eq 0 ]
  [[ "$output" == *"None — the PR is clean"* ]]
  [[ "$output" == *"Reviewer approved: true"* ]]
}

@test "findings_addressed_thread_ids extracts only checked items" {
  mkdir -p "$(ledger_dir)"
  cat >"$(findings_path 3.2)" <<'EOF'
# findings
- [x] [Review][Patch] fixed one [a.sh:1] <!-- thread:T_one -->
- [ ] [Review][Patch] open one [b.sh:2] <!-- thread:T_two -->
- [X] [Review][Patch] fixed two [c.sh:3] <!-- thread:T_three -->
- [x] [Review][Patch] CI check failing: test <!-- check:test -->
EOF
  run findings_addressed_thread_ids 3.2
  [ "$status" -eq 0 ]
  [ "$output" = "T_one
T_three" ]
}

@test "findings_open_count counts unchecked items" {
  mkdir -p "$(ledger_dir)"
  cat >"$(findings_path 3.2)" <<'EOF'
- [x] done <!-- thread:T1 -->
- [ ] open <!-- thread:T2 -->
- [ ] also open <!-- check:ci -->
EOF
  [ "$(findings_open_count 3.2)" = "2" ]
}

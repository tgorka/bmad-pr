#!/usr/bin/env bats

load helpers/common

setup() {
  export LIB_SOURCE_DIR="$LIB_DIR"
  source "$LIB_DIR/common.sh"
  source "$LIB_DIR/config.sh"
  source "$LIB_DIR/ledger.sh"
  REPO="$(make_repo)"
  cd "$REPO"
  config_load "$REPO"
}

new_entry() { # key branch parent_branch parent_pr number openedAt
  ledger_new_entry "$1" "$2" "$3" "${4:+sha$4}" "$4" "$5" \
    "https://github.com/o/r/pull/$5" dev-story run-1 gh |
    jq --arg t "$6" '.openedAt = $t' | ledger_write "$1"
}

@test "write + read roundtrip" {
  new_entry 3.2 bmad/story/3.2 "" 41 42 2026-07-06T10:00:00Z
  run ledger_read 3.2
  [ "$status" -eq 0 ]
  [ "$(jq -r '.pr.number' <<<"$output")" = "42" ]
  [ "$(jq -r '.branch' <<<"$output")" = "bmad/story/3.2" ]
  [ "$(jq -r '.parentPr' <<<"$output")" = "41" ]
  [ "$(jq -r '.reviewer.provider' <<<"$output")" = "cubic" ]
}

@test "read of missing key returns 1 silently" {
  run ledger_read nope
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "malformed ledger refuses with exit 2" {
  mkdir -p "$REPO/_bmad-output/pr"
  echo '{"not": "a ledger"}' >"$REPO/_bmad-output/pr/bad.json"
  run ledger_read bad
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed ledger"* ]]
}

@test "ledger_update mutates and persists" {
  new_entry 3.2 bmad/story/3.2 "" 41 42 2026-07-06T10:00:00Z
  ledger_update 3.2 '.phase = $p' --arg p code-review
  [ "$(ledger_read 3.2 | jq -r .phase)" = "code-review" ]
}

@test "newest_open picks latest open entry excluding self" {
  new_entry 3.1 bmad/story/3.1 "" "" 40 2026-07-01T10:00:00Z
  new_entry 3.2 bmad/story/3.2 bmad/story/3.1 40 41 2026-07-03T10:00:00Z
  new_entry 3.3 bmad/story/3.3 bmad/story/3.2 41 42 2026-07-05T10:00:00Z
  run ledger_newest_open 3.3
  [ "$status" -eq 0 ]
  [ "$(jq -r '.story' <<<"$output")" = "3.2" ]
}

@test "newest_open skips merged entries" {
  new_entry 3.1 bmad/story/3.1 "" "" 40 2026-07-01T10:00:00Z
  new_entry 3.2 bmad/story/3.2 "" "" 41 2026-07-03T10:00:00Z
  ledger_update 3.2 '.pr.state = "merged"'
  run ledger_newest_open 3.3
  [ "$status" -eq 0 ]
  [ "$(jq -r '.story' <<<"$output")" = "3.1" ]
}

@test "newest_open returns 1 when ledger dir empty" {
  run ledger_newest_open 3.2
  [ "$status" -eq 1 ]
}

@test "newest_open refuses on unparseable ledger JSON instead of de-stacking" {
  new_entry 3.1 bmad/story/3.1 "" "" 40 2026-07-01T10:00:00Z
  echo '{broken' >"$REPO/_bmad-output/pr/zz.json"
  run ledger_newest_open 3.3
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed ledger files"* ]]
}

@test "newest_open refuses on valid JSON without the ledger shape" {
  new_entry 3.1 bmad/story/3.1 "" "" 40 2026-07-01T10:00:00Z
  echo '{"schema": 1, "story": 3}' >"$REPO/_bmad-output/pr/zz.json"
  run ledger_newest_open 3.3
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed ledger files"* ]]
}

@test "ledger_write rejects entries missing required fields" {
  run bash -c "
    cd '$REPO'
    export LIB_SOURCE_DIR='$LIB_DIR' BMAD_PR_LEDGER_DIR=_bmad-output/pr
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/ledger.sh'
    echo '{\"schema\": 1}' | ledger_write nope"
  [ "$status" -eq 1 ]
  [ ! -e "$REPO/_bmad-output/pr/nope.json" ]
}

@test "config_load refuses traversal or absolute BMAD_PR_LEDGER_DIR" {
  run bash -c "
    export LIB_SOURCE_DIR='$LIB_DIR' BMAD_PR_LEDGER_DIR='../outside'
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/config.sh'
    config_load '$REPO'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"repo-relative"* ]]
  run bash -c "
    export LIB_SOURCE_DIR='$LIB_DIR' BMAD_PR_LEDGER_DIR='/tmp/abs'
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/config.sh'
    config_load '$REPO'"
  [ "$status" -eq 2 ]
}

@test "ledger_dir itself refuses traversal (defense in depth)" {
  export BMAD_PR_LEDGER_DIR='../outside'
  run ledger_dir
  [ "$status" -eq 2 ]
  [[ "$output" == *"repo-relative"* ]]
}

@test "ledger_read propagates the ledger_dir refusal through substitutions" {
  export BMAD_PR_LEDGER_DIR='../outside'
  run ledger_read 3.2
  [ "$status" -eq 2 ]
  [[ "$output" == *"repo-relative"* ]]
}

@test "newest_open refuses when an entry lacks pr.state" {
  new_entry 3.1 bmad/story/3.1 "" "" 40 2026-07-01T10:00:00Z
  echo '{"schema": 1, "story": "9.9", "branch": "bmad/story/9.9"}' \
    >"$REPO/_bmad-output/pr/zz.json"
  run ledger_newest_open 3.3
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed ledger files"* ]]
}

@test "keys are sanitized in filenames" {
  new_entry 'evil/../key' bmad/story/x "" "" 7 2026-07-01T10:00:00Z
  [ -f "$REPO/_bmad-output/pr/evil-..-key.json" ]
}

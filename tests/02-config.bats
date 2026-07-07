#!/usr/bin/env bats

load helpers/common

setup() {
  export LIB_SOURCE_DIR="$LIB_DIR"
  source "$LIB_DIR/common.sh"
  source "$LIB_DIR/config.sh"
  ROOT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$ROOT"
}

@test "defaults apply with no config file" {
  config_load "$ROOT"
  [ "$BMAD_PR_TOOL" = "auto" ]
  [ "$BMAD_PR_TRUNK" = "main" ]
  [ "$BMAD_PR_REVIEWER" = "cubic" ]
  [ "$BMAD_PR_SCORE_THRESHOLD" = "8" ]
}

@test "config file overrides defaults" {
  mkdir -p "$ROOT/_bmad/bmad-pr"
  printf 'BMAD_PR_TRUNK=develop\nBMAD_PR_TOOL=gh\n' >"$ROOT/_bmad/bmad-pr/config.env"
  config_load "$ROOT"
  [ "$BMAD_PR_TRUNK" = "develop" ]
  [ "$BMAD_PR_TOOL" = "gh" ]
}

@test "environment wins over config file" {
  mkdir -p "$ROOT/_bmad/bmad-pr"
  printf 'BMAD_PR_TRUNK=develop\n' >"$ROOT/_bmad/bmad-pr/config.env"
  export BMAD_PR_TRUNK=release
  config_load "$ROOT"
  [ "$BMAD_PR_TRUNK" = "release" ]
}

@test "cubic profile fills reviewer gaps" {
  config_load "$ROOT"
  [ "$BMAD_PR_REVIEWER_TRIGGER" = "@cubic-dev re-review" ]
  [ "$BMAD_PR_REVIEWER_COMPLETION" = "check-run" ]
  [[ "$BMAD_PR_REVIEWER_BOT_REGEX" == "^cubic" ]]
}

@test "cubic profile respects overrides from config file" {
  mkdir -p "$ROOT/_bmad/bmad-pr"
  printf 'BMAD_PR_REVIEWER_TRIGGER="@cubic-dev-ai please review"\n' \
    >"$ROOT/_bmad/bmad-pr/config.env"
  config_load "$ROOT"
  [ "$BMAD_PR_REVIEWER_TRIGGER" = "@cubic-dev-ai please review" ]
}

@test "generic reviewer refuses without bot regex" {
  run bash -c "
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/config.sh'
    export LIB_SOURCE_DIR='$LIB_DIR'
    BMAD_PR_REVIEWER=generic config_load '$ROOT'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BMAD_PR_REVIEWER_BOT_REGEX"* ]]
}

@test "reviewer provider with path separators refuses cleanly" {
  run bash -c "
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/config.sh'
    export LIB_SOURCE_DIR='$LIB_DIR'
    BMAD_PR_REVIEWER='../../evil' config_load '$ROOT'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid reviewer provider name"* ]]
}

@test "unknown reviewer provider refuses" {
  run bash -c "
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/config.sh'
    export LIB_SOURCE_DIR='$LIB_DIR'
    BMAD_PR_REVIEWER=nonexistent config_load '$ROOT'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown reviewer provider"* ]]
}

@test "reviewer none skips profile loading" {
  BMAD_PR_REVIEWER=none config_load "$ROOT"
  [ -z "${BMAD_PR_REVIEWER_TRIGGER:-}" ]
}

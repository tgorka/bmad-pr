#!/usr/bin/env bats

load helpers/common

setup() {
  export LIB_SOURCE_DIR="$LIB_DIR"
  source "$LIB_DIR/common.sh"
}

@test "sanitize_key passes through story keys" {
  [ "$(sanitize_key '3.2')" = "3.2" ]
  [ "$(sanitize_key 'quick-fix_login.v2')" = "quick-fix_login.v2" ]
}

@test "sanitize_key replaces unsafe characters" {
  [ "$(sanitize_key 'a/b c!')" = "a-b-c-" ]
  [ "$(sanitize_key '../../etc/passwd')" = "..-..-etc-passwd" ]
}

@test "refuse exits 2 with message on stderr" {
  run bash -c "source '$LIB_DIR/common.sh'; refuse 'nope'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"refuse: nope"* ]]
}

@test "die exits 1 with message on stderr" {
  run bash -c "source '$LIB_DIR/common.sh'; die 'boom'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: boom"* ]]
}

@test "now_iso emits UTC ISO-8601" {
  [[ "$(now_iso)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

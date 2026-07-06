# shellcheck shell=bash
# Pre-submit CI checks via gh. Normalize on `bucket` (pass|fail|pending|
# skipping|cancel) — not `state` — per gh 2.95 semantics.

# checks_snapshot <pr> → JSON array [{name,bucket,link,description}], or
# `null` when the gh call itself failed (auth/network/API error).
# gh pr checks exits non-zero on fail/pending too, so don't trust the exit
# code — trust whether the output parses as an array. A hard API failure
# must NOT read as "no checks": that would let watch proceed false-green.
checks_snapshot() {
  local out
  out="$(gh pr checks "$1" --json name,bucket,link,description 2>/dev/null || true)"
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$out"; then
    printf 'null\n'
    return 0
  fi
  printf '%s\n' "$out"
}

# stdin: snapshot JSON → pass | fail | pending | none
# (null → pending: keep waiting / time out rather than false-green)
checks_aggregate() {
  jq -r '
    if . == null then "pending"
    elif length == 0 then "none"
    elif any(.[]; .bucket == "fail" or .bucket == "cancel") then "fail"
    elif any(.[]; .bucket == "pending") then "pending"
    else "pass"
    end'
}

# stdin: snapshot JSON → JSON array of failing checks
checks_failing() {
  jq 'if . == null then [] else [.[] | select(.bucket == "fail" or .bucket == "cancel")] end'
}

# checks_wait <pr> <timeout_sec> — poll with backoff until a terminal verdict.
# Prints pass|fail|none; rc 0. On deadline prints pending; rc 1.
# "none" after the grace window means the repo has no checks configured —
# check suites register a few seconds after push, hence the grace.
checks_wait() {
  local pr=$1 timeout=$2
  local deadline=$(($(epoch) + timeout))
  local grace_deadline=$(($(epoch) + 90))
  ((grace_deadline > deadline)) && grace_deadline=$deadline
  local interval="${BMAD_PR_POLL_INTERVAL:-15}"
  local agg
  while :; do
    agg="$(checks_snapshot "$pr" | checks_aggregate)"
    case "$agg" in
      none)
        (($(epoch) >= grace_deadline)) && {
          printf 'none\n'
          return 0
        }
        ;;
      pending) ;;
      *)
        printf '%s\n' "$agg"
        return 0
        ;;
    esac
    (($(epoch) >= deadline)) && {
      printf 'pending\n'
      return 1
    }
    sleep "$interval"
    ((interval < 60)) && interval=$((interval * 2))
  done
}

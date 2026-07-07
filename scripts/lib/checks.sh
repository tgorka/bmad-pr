# shellcheck shell=bash
# Pre-submit CI checks via gh. Normalize on `bucket` (pass|fail|pending|
# skipping|cancel) — not `state` — per gh 2.95 semantics.

# checks_snapshot <pr> → JSON array [{name,bucket,link,description}], or
# `null` when the gh call itself failed (auth/network/API error).
# gh pr checks exits non-zero on fail/pending too, so don't trust the exit
# code — trust whether the output parses as an array. A hard API failure
# must NOT read as "no checks": that would let watch proceed false-green.
checks_snapshot() {
  # Base-repo scoped when the slug cache is warm (fork workflows, DW-3);
  # never resolves the slug itself — a slug failure must not break the
  # null-on-error contract below.
  local out
  local -a repo_args=()
  [[ -n "${_BMAD_PR_REPO_SLUG:-}" ]] && repo_args=(--repo "$_BMAD_PR_REPO_SLUG")
  out="$(gh pr checks "$1" --json name,bucket,link,description \
    "${repo_args[@]}" 2>/dev/null || true)"
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
# Prints pass|fail|none; rc 0. On deadline prints pending; rc 1. Prints
# error; rc 1 when the checks API itself keeps failing — a hard gh failure
# must not masquerade as a CI timeout.
# "none" after the grace window means the repo has no checks configured —
# check suites register a few seconds after push, hence the grace.
checks_wait() {
  local pr=$1 timeout=$2
  local deadline grace grace_deadline
  deadline=$(($(epoch) + timeout))
  grace="${BMAD_PR_REGISTER_GRACE:-90}"
  grace_deadline=$(($(epoch) + grace))
  ((grace_deadline > deadline)) && grace_deadline=$deadline
  local interval="${BMAD_PR_POLL_INTERVAL:-15}"
  local agg snapshot null_streak=0
  while :; do
    snapshot="$(checks_snapshot "$pr")"
    if [[ "$snapshot" == null ]]; then
      ((++null_streak >= 3)) && {
        printf 'error\n'
        return 1
      }
    else
      null_streak=0
    fi
    agg="$(checks_aggregate <<<"$snapshot")"
    case "$agg" in
      pending) ;;
      fail)
        printf 'fail\n'
        return 0
        ;;
      none | pass)
        # Check suites register one by one for a few seconds after push —
        # neither "no checks" nor "all green so far" is trustworthy until
        # the registration grace window has elapsed. Failures are terminal
        # immediately.
        (($(epoch) >= grace_deadline)) && {
          printf '%s\n' "$agg"
          return 0
        }
        ;;
    esac
    local now remaining
    now="$(epoch)"
    ((now >= deadline)) && {
      printf 'pending\n'
      return 1
    }
    # Never sleep past the deadline — the backoff interval can exceed the
    # remaining time budget.
    remaining=$((deadline - now))
    if ((interval < remaining)); then
      sleep "$interval"
    else
      sleep "$remaining"
    fi
    ((interval < 60)) && interval=$((interval * 2))
  done
}

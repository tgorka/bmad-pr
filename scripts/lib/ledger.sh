# shellcheck shell=bash
# PR ledger: one JSON file per story key under $BMAD_PR_LEDGER_DIR (R3).
# All writes are atomic (tmp + mv); all reads go through jq.

# Ledger writes must stay inside the repository — refuse absolute paths and
# traversal segments in the configured dir.
ledger_dir() {
  case "/$BMAD_PR_LEDGER_DIR/" in
    //* | *"/../"* | *"/./"*)
      refuse "BMAD_PR_LEDGER_DIR must be a repo-relative path without '..' segments (got: $BMAD_PR_LEDGER_DIR)"
      ;;
  esac
  printf '%s/%s' "$(repo_root)" "$BMAD_PR_LEDGER_DIR"
}

ledger_path() {
  printf '%s/%s.json' "$(ledger_dir)" "$(sanitize_key "$1")"
}

# Print the ledger JSON for a key. Returns 1 (silently) when absent.
ledger_read() {
  local path
  path="$(ledger_path "$1")"
  [[ -f "$path" ]] || return 1
  jq -e '.schema == 1 and (.story | type == "string") and (.branch | type == "string")' \
    "$path" >/dev/null 2>&1 ||
    refuse "malformed ledger: $path (fix or remove it, then re-run)"
  cat "$path"
}

# Write ledger JSON (stdin) for a key, atomically, validating first.
ledger_write() {
  local key=$1 path tmp
  path="$(ledger_path "$key")"
  mkdir -p "$(dirname "$path")"
  tmp="$path.tmp.$$"
  cat >"$tmp"
  # Same shape validation as ledger_read — never persist what read would
  # later refuse.
  if ! jq -e '.schema == 1 and (.story | type == "string") and (.branch | type == "string")' \
    "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    die "internal: refusing to write invalid ledger JSON for $key"
  fi
  mv "$tmp" "$path"
}

# Newest ledger entry with an open PR, excluding the given key. This is the
# stack-parent resolution input (R5): the previous story still in flight.
# Prints the entry JSON; returns 1 when none exists.
ledger_newest_open() {
  local exclude
  exclude="$(sanitize_key "${1:-}")"
  local dir
  dir="$(ledger_dir)"
  [[ -d "$dir" ]] || return 1
  local -a files=("$dir"/*.json)
  [[ -e "${files[0]}" ]] || return 1
  local out
  # Corrupt ledger state must refuse, not read as "no open parent" —
  # silently de-stacking onto trunk would be worse than stopping. That
  # covers both unparseable JSON (jq -s fails) and parseable files that
  # don't have the required ledger shape (jq error() below).
  out="$(jq -s --arg ex "$exclude" '
    if any(.[]; (.schema != 1)
              or ((.story | type) != "string")
              or ((.branch | type) != "string"))
    then error("entry without required ledger shape")
    else
      [ .[]
        | select((.story | gsub("[^A-Za-z0-9._-]"; "-")) != $ex)
        | select(.pr.state == "open")
      ] | sort_by(.openedAt) | last // empty
    end
  ' "${files[@]}")" ||
    refuse "malformed ledger files in $dir — fix or remove them, then re-run"
  [[ -n "$out" ]] || return 1
  printf '%s\n' "$out"
}

# Build a fresh ledger entry. Args: key branch parent_branch parent_sha
# parent_pr pr_number pr_url phase run_id tool
ledger_new_entry() {
  jq -n \
    --arg story "$1" --arg branch "$2" --arg parentBranch "$3" \
    --arg parentSha "$4" --arg parentPr "$5" --arg number "$6" --arg url "$7" \
    --arg phase "$8" --arg runId "$9" --arg tool "${10}" \
    --arg now "$(now_iso)" --arg provider "${BMAD_PR_REVIEWER:-none}" '
    {
      schema: 1,
      story: $story,
      branch: $branch,
      parentBranch: (if $parentBranch == "" then null else $parentBranch end),
      parentSha: (if $parentSha == "" then null else $parentSha end),
      parentPr: (if $parentPr == "" then null else ($parentPr | tonumber) end),
      pr: {
        number: (if $number == "" then null else ($number | tonumber) end),
        url: (if $url == "" then null else $url end),
        state: "open"
      },
      phase: $phase,
      runId: (if $runId == "" then null else $runId end),
      tool: $tool,
      reviewer: {
        provider: $provider,
        lastReviewedSha: null,
        lastScore: null,
        approved: false
      },
      openedAt: $now,
      lastAmendedAt: $now
    }'
}

# Apply a jq filter to an existing ledger entry and persist the result.
# Usage: ledger_update <key> <jq-filter> [jq args...]
ledger_update() {
  local key=$1 filter=$2
  shift 2
  local current
  current="$(ledger_read "$key")" || die "internal: ledger_update on missing ledger for $key"
  jq "$@" "$filter" <<<"$current" | ledger_write "$key"
}

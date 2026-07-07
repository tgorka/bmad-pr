# shellcheck shell=bash
# Configuration loading. Precedence: CLI flags (applied by the caller after
# config_load) > environment variables > _bmad/bmad-pr/config.env > defaults.
# The config file is flat shell (KEY=value) so no YAML/TOML parsing is needed.

BMAD_PR_CONFIG_KEYS=(
  BMAD_PR_TOOL              # auto | gt | gh | git
  BMAD_PR_TRUNK             # trunk branch PRs ultimately target
  BMAD_PR_DRAFT             # true | false — open PRs as drafts
  BMAD_PR_LEDGER_DIR        # relative to repo root
  BMAD_PR_STAGE_GLOB        # CH3 scope: tree changes outside this path refuse
  BMAD_PR_BRANCH_PREFIX     # story branches: <prefix>/story/<key>
  BMAD_PR_REVIEWER          # cubic | generic | none
  BMAD_PR_REVIEWER_BOT_REGEX
  BMAD_PR_REVIEWER_CHECK_REGEX
  BMAD_PR_REVIEWER_TRIGGER
  BMAD_PR_REVIEWER_COMPLETION # check-run | bot-review
  BMAD_PR_SCORE_REGEX
  BMAD_PR_SCORE_THRESHOLD
  BMAD_PR_TIMEOUT           # seconds for watch
  BMAD_PR_POLL_INTERVAL     # initial poll interval, seconds
  BMAD_PR_REGISTER_GRACE    # seconds to wait for check suites to register
  BMAD_PR_MAX_ITERATIONS    # review-cycle ceiling (used by the loop skill)
)

config_defaults() {
  : "${BMAD_PR_TOOL:=auto}"
  : "${BMAD_PR_TRUNK:=main}"
  : "${BMAD_PR_DRAFT:=true}"
  : "${BMAD_PR_LEDGER_DIR:=_bmad-output/pr}"
  : "${BMAD_PR_STAGE_GLOB:=_bmad-output/}"
  : "${BMAD_PR_BRANCH_PREFIX:=bmad}"
  : "${BMAD_PR_REVIEWER:=cubic}"
  : "${BMAD_PR_SCORE_THRESHOLD:=8}"
  : "${BMAD_PR_TIMEOUT:=1800}"
  : "${BMAD_PR_POLL_INTERVAL:=15}"
  : "${BMAD_PR_REGISTER_GRACE:=90}"
  : "${BMAD_PR_MAX_ITERATIONS:=5}"
}

# Load config: file values fill in only what the environment did not set,
# then defaults fill the rest, then the reviewer profile fills its own gaps.
config_load() {
  local root=$1
  local file="${BMAD_PR_CONFIG_FILE:-$root/_bmad/bmad-pr/config.env}"

  if [[ -f "$file" ]]; then
    local key
    declare -A env_set=()
    for key in "${BMAD_PR_CONFIG_KEYS[@]}"; do
      [[ -n "${!key+x}" ]] && env_set[$key]=${!key}
    done
    # shellcheck source=/dev/null
    source "$file"
    for key in "${!env_set[@]}"; do
      printf -v "$key" '%s' "${env_set[$key]}"
    done
  fi

  config_defaults

  # Authoritative traversal guard: ledger_dir re-checks this, but functions
  # used inside command substitutions cannot abort the caller — this runs in
  # the main shell, so a bad value stops the CLI before any path is built.
  case "/$BMAD_PR_LEDGER_DIR/" in
    //* | *"/../"* | *"/./"*)
      refuse "BMAD_PR_LEDGER_DIR must be a repo-relative path without '..' segments (got: $BMAD_PR_LEDGER_DIR)"
      ;;
  esac

  # Provider names are tokens, never paths — a value with separators would
  # source arbitrary files instead of a reviewer profile.
  [[ "$BMAD_PR_REVIEWER" =~ ^[a-z0-9_-]+$ ]] ||
    refuse "invalid reviewer provider name: '$BMAD_PR_REVIEWER' (expected a token like cubic, generic, none)"

  local profile="${LIB_SOURCE_DIR}/reviewers/${BMAD_PR_REVIEWER}.sh"
  if [[ "$BMAD_PR_REVIEWER" != "none" ]]; then
    if [[ -f "$profile" ]]; then
      # shellcheck source=/dev/null
      source "$profile"
      reviewer_profile
    else
      refuse "unknown reviewer provider: $BMAD_PR_REVIEWER (no profile at $profile)"
    fi
  fi

  export "${BMAD_PR_CONFIG_KEYS[@]}"
}

#!/usr/bin/env bash
# Repo gate: syntax, lint, manifest validation, test suite.
# This is what CI runs and what the pre-commit hook runs. Keep it fast.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail=0
note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() {
  printf '\033[1;31mFAIL\033[0m %s\n' "$*"
  fail=1
}

sh_files() {
  # --others --exclude-standard also covers files not yet git-added.
  git ls-files -z --cached --others --exclude-standard -- \
    '*.sh' '*.bash' 'scripts/bmad-pr' '.githooks/*'
}

note "bash -n (syntax)"
while IFS= read -r -d '' f; do
  bash -n "$f" || err "syntax: $f"
done < <(sh_files)

note "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  sh_files | xargs -0 shellcheck --severity=warning --external-sources || err "shellcheck"
else
  note "shellcheck not installed — skipped locally (CI enforces it)"
fi

note "plugin manifests"
jq -e '.name == "bmad-pr" and .version and .description and .skills' \
  .claude-plugin/plugin.json >/dev/null 2>&1 || err ".claude-plugin/plugin.json invalid"
jq -e '.name and (.plugins | type == "array" and length > 0 and all(.name and .source))' \
  .claude-plugin/marketplace.json >/dev/null 2>&1 || err ".claude-plugin/marketplace.json invalid"

note "skill frontmatter"
shopt -s nullglob
for f in skills/*/SKILL.md; do
  head -1 "$f" | grep -qx -- '---' || err "$f: missing frontmatter open"
  frontmatter="$(sed -n '2,/^---$/p' "$f")"
  grep -q '^name:' <<<"$frontmatter" || err "$f: frontmatter missing name"
  grep -q '^description:' <<<"$frontmatter" || err "$f: frontmatter missing description"
done
shopt -u nullglob

note "module-help.csv shape"
awk -F',' 'NR==1 { n = NF } NF != n { printf "line %d has %d fields, want %d\n", NR, NF, n; bad = 1 } END { exit bad }' \
  module-help.csv || err "module-help.csv: inconsistent column count"

note "bats suite"
tests/run.sh || err "tests"

if ((fail)); then
  echo
  err "gate failed"
  exit 1
fi
note "gate passed"

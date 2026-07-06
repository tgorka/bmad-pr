#!/usr/bin/env bash
# Runs the bats suite. Uses system bats when present, else the vendored copy.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v bats >/dev/null 2>&1; then
  bats_bin="$(command -v bats)"
else
  bats_bin="$("$here/vendor.sh")"
fi

exec "$bats_bin" "${@:-$here}"

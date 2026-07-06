#!/usr/bin/env bash
# Vendors a pinned bats-core into tests/.vendor and prints the bats binary path.
# No global installs; idempotent; safe to run offline once vendored.
set -euo pipefail

BATS_VERSION="${BATS_VERSION:-1.11.1}"
# sha256 of the pinned release tarball; override together with BATS_VERSION.
BATS_SHA256="${BATS_SHA256:-5c57ed9616b78f7fd8c553b9bae3c7c9870119edd727ec17dbd1185c599f79d9}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vendor_dir="$here/.vendor"
bats_dir="$vendor_dir/bats-core-$BATS_VERSION"

if [[ ! -x "$bats_dir/bin/bats" ]]; then
  mkdir -p "$vendor_dir"
  tarball="$vendor_dir/bats-core-$BATS_VERSION.tar.gz"
  url="https://github.com/bats-core/bats-core/archive/refs/tags/v$BATS_VERSION.tar.gz"
  curl -fsSL "$url" -o "$tarball"
  echo "$BATS_SHA256  $tarball" | sha256sum -c --quiet - || {
    rm -f "$tarball"
    echo "vendor failed: checksum mismatch for $url" >&2
    exit 1
  }
  tar -xzf "$tarball" -C "$vendor_dir"
  rm -f "$tarball"
  [[ -x "$bats_dir/bin/bats" ]] || {
    echo "vendor failed: $bats_dir/bin/bats missing after extract" >&2
    exit 1
  }
fi

echo "$bats_dir/bin/bats"

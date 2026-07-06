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
  # Portable digest: coreutils sha256sum (Linux) or shasum (macOS). Fail
  # closed when neither exists — never extract an unverified tarball.
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tarball" | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
  else
    rm -f "$tarball"
    echo "vendor failed: neither sha256sum nor shasum available to verify $url" >&2
    exit 1
  fi
  if [[ "$actual" != "$BATS_SHA256" ]]; then
    rm -f "$tarball"
    echo "vendor failed: checksum mismatch for $url (got $actual)" >&2
    exit 1
  fi
  tar -xzf "$tarball" -C "$vendor_dir"
  rm -f "$tarball"
  [[ -x "$bats_dir/bin/bats" ]] || {
    echo "vendor failed: $bats_dir/bin/bats missing after extract" >&2
    exit 1
  }
fi

echo "$bats_dir/bin/bats"

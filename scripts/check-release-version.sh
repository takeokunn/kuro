#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo "usage: $0 vMAJOR.MINOR.PATCH" >&2
  exit 2
fi

tag=$1
if [[ ! $tag =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "release tag must be stable SemVer (vMAJOR.MINOR.PATCH): $tag" >&2
  exit 1
fi
expected=${tag#v}

read_version() {
  local label=$1 file=$2 pattern=$3
  local value
  value=$(perl -ne "if (/$pattern/) { print \$1; exit }" "$file")
  if [[ -z $value ]]; then
    echo "could not read $label version from $file" >&2
    exit 1
  fi
  if [[ $value != "$expected" ]]; then
    echo "$label version mismatch: expected $expected, found $value in $file" >&2
    exit 1
  fi
  printf '%-24s %s\n' "$label" "$value"
}

read_version "Cargo workspace" Cargo.toml '^version = "([^"]+)"'
read_version "Emacs package" emacs-lisp/core/kuro.el '^;; Version: ([^[:space:]]+)'
read_version "Native downloader" emacs-lisp/core/kuro-module-platform.el '^\(defconst kuro-module--version "([^"]+)"'
read_version "Nix package" flake.nix '^[[:space:]]+version = "([^"]+)";'

echo "release versions match $tag"

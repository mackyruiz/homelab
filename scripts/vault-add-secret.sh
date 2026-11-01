#!/usr/bin/env bash
# Append a random hex secret to an ansible-vault file without ever writing it
# to disk unencrypted outside a mode-0600 temp file.
# Usage: scripts/vault-add-secret.sh <vault-file> <variable-name> [bytes]   (file relative to ansible/; bytes default 32)
# Run from anywhere; uses ansible/ansible.cfg for the vault password file.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../ansible"

[[ $# -eq 2 || $# -eq 3 ]] || { echo "usage: $0 <vault-file> <variable-name> [bytes]" >&2; exit 2; }
file=$1
var=$2

tmp=$(mktemp)
trap 'shred -u "$tmp"' EXIT

ansible-vault decrypt --output - "$file" > "$tmp"
if grep -q "^${var}:" "$tmp"; then
  echo "$var already exists in $file; refusing to overwrite" >&2
  exit 1
fi
printf '%s: "%s"\n' "$var" "$(openssl rand -hex "${3:-32}")" >> "$tmp"
ansible-vault encrypt --output "$file" "$tmp"
echo "added $var to $file"

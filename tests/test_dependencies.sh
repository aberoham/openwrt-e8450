#!/bin/bash
# Check that required dependencies are available in PATH
set -e

COMMANDS=(
  bash
  git
  ssh
  ping
  readlink
  awk
  sed
  grep
  cut
  xargs
  tee
  tar
)

missing=()
for cmd in "${COMMANDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

if [ ${#missing[@]} -ne 0 ]; then
  echo "Missing required commands: ${missing[*]}" >&2
  exit 1
fi

echo "All required commands are available."

# Verify readlink supports -f (GNU version is required)
if ! readlink -f "$(pwd)" >/dev/null 2>&1; then
  echo "readlink does not support -f option; install coreutils version" >&2
  exit 1
fi

echo "readlink -f is functional."

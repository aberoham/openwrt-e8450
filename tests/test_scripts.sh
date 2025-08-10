#!/bin/bash
# Validate all shell scripts with bash -n
set -e

SCRIPTS=$(git ls-files '*.sh')

fail=0
for script in $SCRIPTS; do
  if ! bash -n "$script"; then
    echo "Syntax error in $script" >&2
    fail=1
  fi
  if [ ! -x "$script" ]; then
    echo "Warning: $script is not executable" >&2
  fi
done

if [ $fail -ne 0 ]; then
  echo "Shell script validation failed" >&2
  exit 1
fi

echo "All shell scripts passed syntax check."

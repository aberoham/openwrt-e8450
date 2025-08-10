#!/bin/bash
# Run all test scripts
set -e

dir="$(dirname "$0")"

"$dir/test_dependencies.sh"
"$dir/test_scripts.sh"

echo "All tests completed successfully."

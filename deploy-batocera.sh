#!/usr/bin/env bash
# Deploy Chomp Wars to a Batocera machine
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(which python3 || echo "python")"

exec "$PYTHON_BIN" "$SCRIPT_DIR/tools/deploy_batocera.py" "$@"

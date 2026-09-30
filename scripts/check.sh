#!/bin/bash
set -euo pipefail
KEYFINDER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KEYFINDER_ROOT"
swift build
swift run --skip-build KeyfinderCoreChecks
BIN_DIRECTORY="$(swift build --show-bin-path)"
"$BIN_DIRECTORY/Keyfinder" --render-previews "$KEYFINDER_ROOT/artifacts/previews"
"$BIN_DIRECTORY/Keyfinder" --smoke-test "$KEYFINDER_ROOT/artifacts/smoke/report.json"
echo 'All software checks passed. Live USB acceptance requires the Moonlander.'

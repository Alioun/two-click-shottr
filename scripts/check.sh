#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-source.py
xcrun swift-format lint --strict --recursive Sources Tests
for script in scripts/*.sh scripts/*.command; do bash -n "$script"; done
python3 scripts/test-script-regressions.py
python3 scripts/test-release.py
./scripts/swift.sh test --disable-xctest --enable-swift-testing
./scripts/swift.sh build -c release

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-source.py
xcrun swift-format lint --strict --recursive Sources Tests scripts/dmg-layout.swift
for script in scripts/*.sh scripts/*.command; do bash -n "$script"; done
python3 scripts/test-script-regressions.py
python3 scripts/test-release.py
# AppKit lifecycle tests activate and close native windows in a separate process.
./scripts/swift.sh test --disable-xctest --enable-swift-testing --skip AppearanceSettingsTests
./scripts/swift.sh test --disable-xctest --enable-swift-testing --filter AppearanceSettingsTests
./scripts/swift.sh build -c release

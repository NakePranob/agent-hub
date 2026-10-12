#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-robot-look.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/Robot/RobotLook.swift \
    tests/RobotLookTests.swift -o "$TEST_DIR/robot-look-tests"
"$TEST_DIR/robot-look-tests"

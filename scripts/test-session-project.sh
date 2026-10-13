#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-session-project.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library NotchBuddy/Sources/App/Agents/SessionProject.swift \
    tests/SessionProjectTests.swift -o "$TEST_DIR/session-project-tests"
"$TEST_DIR/session-project-tests"

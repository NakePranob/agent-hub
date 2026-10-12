#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-step-kinds.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/StepKinds.swift NotchBuddy/Sources/CoucouKit/AgentTurn.swift \
    NotchBuddy/Sources/CoucouKit/DiffEngine.swift \
    tests/StepKindTests.swift -o "$TEST_DIR/step-kind-tests"
"$TEST_DIR/step-kind-tests"

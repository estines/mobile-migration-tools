#!/usr/bin/env bash
set -euo pipefail

# mstack Universal Always-Compile Gate
# Usage: ./mobile-migration-tools/scripts/compile-gate.sh <step_name> <principles_csv> "<description>" [custom_compile_cmd]

STEP_NAME="${1:-compile-check}"
PRINCIPLES="${2:-principle-always-compile}"
DESCRIPTION="${3:-Atomic sub-step compilation gate}"
CUSTOM_CMD="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="$SCRIPT_DIR/log-evidence.sh"
PROFILE_FILE=".mstack/target-profile.json"

mkdir -p .mstack/logs

# Resolve compile command in priority order:
# 1. Explicit argument
# 2. .mstack/target-profile.json "compileGateCommand"
# 3. Auto-detected build system fallback
if [[ -n "$CUSTOM_CMD" ]]; then
  COMPILE_CMD="$CUSTOM_CMD"
elif [[ -f "$PROFILE_FILE" ]] && command -v jq >/dev/null 2>&1; then
  COMPILE_CMD=$(jq -r '.verification.compileGateCommand // empty' "$PROFILE_FILE")
fi

if [[ -z "${COMPILE_CMD:-}" ]]; then
  if [[ -f "./gradlew" ]]; then
    COMPILE_CMD="./gradlew compileDebugKotlin"
  elif [[ -f "pubspec.yaml" ]]; then
    COMPILE_CMD="flutter analyze && flutter test"
  elif [[ -f "Package.swift" ]]; then
    COMPILE_CMD="swift build"
  elif [[ -f "package.json" ]]; then
    COMPILE_CMD="npm run typecheck || npx tsc --noEmit"
  else
    echo "ERROR: Cannot determine compile command. Configure .mstack/target-profile.json via mstack-setup." >&2
    exit 2
  fi
fi

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
LOG_FILE=".mstack/logs/compile_${STEP_NAME}_${TIMESTAMP}.log"

echo "[mstack compile-gate] Running: $COMPILE_CMD"
echo "[mstack compile-gate] Principles: $PRINCIPLES"

set +e
eval "$COMPILE_CMD" >"$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 0 ]]; then
  echo "[mstack compile-gate] PASSED ($LOG_FILE)"
  "$LOG_SCRIPT" "$STEP_NAME" "$PRINCIPLES" "$DESCRIPTION" "$COMPILE_CMD" "$LOG_FILE" "COMPILE_PASSED"
  exit 0
else
  echo "[mstack compile-gate] FAILED with exit code $EXIT_CODE. Tail of $LOG_FILE:" >&2
  tail -n 40 "$LOG_FILE" >&2
  "$LOG_SCRIPT" "$STEP_NAME" "$PRINCIPLES" "$DESCRIPTION (exit $EXIT_CODE)" "$COMPILE_CMD" "$LOG_FILE" "COMPILE_FAILED"
  exit $EXIT_CODE
fi

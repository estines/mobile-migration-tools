#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# mstack Universal Always-Compile & Anti-Slop Verification Gate
# Usage: ./mobile-migration-tools/scripts/compile-gate.sh <step_name> <principles_csv> "<description>" [custom_compile_cmd]

STEP_NAME="${1:-compile-check}"
PRINCIPLES="${2:-principle-always-compile}"
DESCRIPTION="${3:-Atomic sub-step compilation gate}"
CUSTOM_CMD="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="$SCRIPT_DIR/log-evidence.sh"
PROFILE_FILE=".mstack/target-profile.json"
PLAN_FILE=".mstack/migration-plan.json"

mkdir -p .mstack/logs

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
LOG_FILE=".mstack/logs/compile_${STEP_NAME}_${TIMESTAMP}.log"

# ------------------------------------------------------------------------------
# 1. Anti-Slop Guard: Verify Locked Golden Master Checksums & Phase Boundaries
# ------------------------------------------------------------------------------
if [[ -f "$PLAN_FILE" ]] && command -v node >/dev/null 2>&1; then
  set +e
  node - "$PLAN_FILE" "$STEP_NAME" >"$LOG_FILE" 2>&1 <<'NODE_EOF'
const fs = require("node:fs");
const crypto = require("node:crypto");
const { execSync } = require("node:child_process");

const [planFile, currentStep] = process.argv.slice(2);
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));

// A. Check Golden Master SHA-256 locks from earlier sub-steps
if (Array.isArray(plan.goldenLocks)) {
  for (const lock of plan.goldenLocks) {
    if (lock.lockedByStep === currentStep) continue; // Creator step may update its own baseline
    if (!fs.existsSync(lock.path)) {
      console.error(`[SLOP_DETECTED] Locked Golden Master file '${lock.path}' (created by '${lock.lockedByStep}') was DELETED!`);
      process.exit(10);
    }
    const actualSha = crypto.createHash("sha256").update(fs.readFileSync(lock.path)).digest("hex");
    if (actualSha !== lock.sha256) {
      console.error(`[SLOP_DETECTED] Locked Golden Master file '${lock.path}' (created by '${lock.lockedByStep}') was MODIFIED! Expected SHA-256 ${lock.sha256}, got ${actualSha}. Restore the original Golden Master file and fix the candidate code instead.`);
      process.exit(11);
    }
  }
}

// B. Check git diff for test-skipping slop (@Ignore / @Disabled) and phase boundary violations
try {
  execSync("git rev-parse --is-inside-work-tree", { stdio: "ignore" });
  const changedFiles = execSync("git diff --name-only", { encoding: "utf8" })
    .split("\n")
    .map(s => s.trim())
    .filter(Boolean);

  // Step 1.1-1.3 must NEVER touch Legacy UI XML/Storyboard files
  if (/step1-[123]\b/.test(currentStep)) {
    const uiViolations = changedFiles.filter(f =>
      /res\/layout\/.*\.xml$/i.test(f) || /\.(storyboard|xib)$/i.test(f)
    );
    if (uiViolations.length > 0) {
      console.error(`[SLOP_DETECTED] Phase Boundary Violation in '${currentStep}': Step 1 (Logic & Storage) must keep Legacy UI 100% untouched, but modified: ${uiViolations.join(", ")}`);
      process.exit(12);
    }
  }

  // Check test files for newly added @Ignore or @Disabled annotations
  const testFiles = changedFiles.filter(f => /(Test|Spec)\.(kt|java|swift|ts|tsx|dart)$/i.test(f));
  for (const tf of testFiles) {
    const diff = execSync(`git diff -- "${tf}"`, { encoding: "utf8" });
    const addedLines = diff
      .split("\n")
      .filter(line => line.startsWith("+") && !line.startsWith("+++"));
    for (const line of addedLines) {
      if (/@Ignore\b|@Disabled\b|\.skip\(/.test(line)) {
        console.error(`[SLOP_DETECTED] Test suppression detected in '${tf}': '${line.trim()}'. Never @Ignore or skip failing parity tests.`);
        process.exit(13);
      }
    }
  }
} catch (e) {
  // Ignore git check if not in a git repository
}
NODE_EOF
  SLOP_EXIT=$?
  set -e
  if [[ $SLOP_EXIT -ne 0 ]]; then
    cat "$LOG_FILE" >&2
    "$LOG_SCRIPT" "$STEP_NAME" "$PRINCIPLES" "$DESCRIPTION (SLOP_DETECTED exit $SLOP_EXIT)" "anti-slop-guard" "$LOG_FILE" "SLOP_REJECTED"
    exit $SLOP_EXIT
  fi
fi

# ------------------------------------------------------------------------------
# 2. Resolve Compile / Test Command
# ------------------------------------------------------------------------------
# Priority order:
# 1. Explicit argument
# 2. Step-level compileCmd in .mstack/migration-plan.json
# 3. .mstack/target-profile.json "compileGateCommand"
# 4. Auto-detected build system fallback
COMPILE_CMD=""
if [[ -n "$CUSTOM_CMD" ]]; then
  COMPILE_CMD="$CUSTOM_CMD"
elif [[ -f "$PLAN_FILE" ]] && command -v node >/dev/null 2>&1; then
  COMPILE_CMD=$(node -e '
    const fs = require("node:fs");
    try {
      const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const s = (p.steps || []).find(x => x.id === process.argv[2]);
      if (s && s.compileCmd) process.stdout.write(s.compileCmd);
    } catch {}
  ' "$PLAN_FILE" "$STEP_NAME")
fi

if [[ -z "${COMPILE_CMD:-}" && -f "$PROFILE_FILE" ]] && command -v node >/dev/null 2>&1; then
  COMPILE_CMD=$(node -e '
    const fs = require("node:fs");
    try {
      const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      if (p.verification && p.verification.compileGateCommand) {
        process.stdout.write(p.verification.compileGateCommand);
      }
    } catch {}
  ' "$PROFILE_FILE")
fi

if [[ -z "${COMPILE_CMD:-}" ]]; then
  if [[ -f "./gradlew" ]]; then
    COMPILE_CMD="./gradlew compileDebugKotlin testDebugUnitTest"
  elif [[ -f "pubspec.yaml" ]]; then
    COMPILE_CMD="flutter analyze && flutter test"
  elif [[ -f "Package.swift" ]]; then
    COMPILE_CMD="swift test"
  elif [[ -f "package.json" ]]; then
    COMPILE_CMD="npm test --if-present && (npm run typecheck --if-present || npx tsc --noEmit)"
  else
    echo "ERROR: Cannot determine compile command. Configure .mstack/target-profile.json via mstack-setup." >&2
    exit 2
  fi
fi

echo "[mstack compile-gate] Running: $COMPILE_CMD"
echo "[mstack compile-gate] Principles: $PRINCIPLES"

set +e
eval "$COMPILE_CMD" >>"$LOG_FILE" 2>&1
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

#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# mstack Sub-Step Handoff & Anti-Slop Golden Lock Recorder
# Called by each non-interactive sub-step session before exiting to:
# 1. Record what was done in this session (summary + fact-checked file list)
# 2. Lock SHA-256 checksums of Golden Master baselines (JSON/PNG/Maestro) so future sessions cannot tamper with them
# 3. Either mark the sub-step ready for completion (DONE) or hand off remaining work (NEEDS_MORE_WORK / --spawn-substep)
#    to the next sequentially spawned non-interactive agent session.

PLAN_FILE=".mstack/migration-plan.json"
STEP_ID=""
HANDOFF_STATUS="DONE"
SUMMARY=""
FILES_CSV=""
LOCK_GOLDEN_CSV=""
REMAINING_PIPE=""
SPAWN_SUBSTEP_TITLE=""
DISCOVERED_COMPILE_CMD=""

usage() {
  cat <<'EOF'
Usage:
  ./mobile-migration-tools/scripts/handoff-substep.sh \
    --step-id <substep_id> \
    --status <DONE|NEEDS_MORE_WORK> \
    --summary "<concise summary of what was completed>" \
    [--files "<path1,path2,...>"] \
    [--lock-golden "<golden_file1,golden_file2,...>"] \
    [--remaining "<todo_item_1|todo_item_2|...>"] \
    [--spawn-substep "<title of follow-up substep to insert right after this one>"] \
    [--compile-cmd "<module test/compile command for this feature>"] \
    [--plan <path>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step-id)
      STEP_ID="${2:-}"
      shift 2
      ;;
    --status)
      HANDOFF_STATUS="${2:-DONE}"
      shift 2
      ;;
    --summary)
      SUMMARY="${2:-}"
      shift 2
      ;;
    --files)
      FILES_CSV="${2:-}"
      shift 2
      ;;
    --lock-golden)
      LOCK_GOLDEN_CSV="${2:-}"
      shift 2
      ;;
    --remaining)
      REMAINING_PIPE="${2:-}"
      shift 2
      ;;
    --spawn-substep)
      SPAWN_SUBSTEP_TITLE="${2:-}"
      shift 2
      ;;
    --compile-cmd)
      DISCOVERED_COMPILE_CMD="${2:-}"
      shift 2
      ;;
    --plan)
      PLAN_FILE="${2:-.mstack/migration-plan.json}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option in handoff-substep.sh: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$STEP_ID" ]]; then
  echo "ERROR: --step-id is required." >&2
  usage
  exit 1
fi

if [[ "$HANDOFF_STATUS" != "DONE" && "$HANDOFF_STATUS" != "NEEDS_MORE_WORK" ]]; then
  echo "ERROR: --status must be DONE or NEEDS_MORE_WORK (got '$HANDOFF_STATUS')." >&2
  exit 1
fi

if [[ -z "$SUMMARY" ]]; then
  echo "ERROR: --summary is required so the next spawned agent session knows what was completed." >&2
  exit 1
fi

if [[ "$HANDOFF_STATUS" == "NEEDS_MORE_WORK" && -z "$REMAINING_PIPE" && -z "$SPAWN_SUBSTEP_TITLE" ]]; then
  echo "ERROR: When --status is NEEDS_MORE_WORK, you must provide --remaining \"<item1|item2>\" or --spawn-substep \"<title>\" for the next agent session." >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: Plan file not found at $PLAN_FILE" >&2
  exit 1
fi

node - "$PLAN_FILE" "$STEP_ID" "$HANDOFF_STATUS" "$SUMMARY" "$FILES_CSV" "$LOCK_GOLDEN_CSV" "$REMAINING_PIPE" "$SPAWN_SUBSTEP_TITLE" "$DISCOVERED_COMPILE_CMD" <<'NODE_EOF'
const fs = require("node:fs");
const crypto = require("node:crypto");

const [
  planFile,
  stepId,
  handoffStatus,
  rawSummary,
  filesCsv,
  lockGoldenCsv,
  remainingPipe,
  spawnSubstepTitle,
  discoveredCompileCmd
] = process.argv.slice(2);

const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
if (!Array.isArray(plan.steps)) {
  console.error("ERROR: Malformed migration-plan.json (missing steps array).");
  process.exit(1);
}

const stepIdx = plan.steps.findIndex(s => s.id === stepId);
if (stepIdx === -1) {
  console.error(`ERROR: Sub-step '${stepId}' not found in ${planFile}.`);
  process.exit(1);
}

const step = plan.steps[stepIdx];

// 1. Fact-check listed files on disk to prevent hallucinated handoffs
const requestedFiles = filesCsv
  .split(",")
  .map(s => s.trim())
  .filter(Boolean);

const verifiedFiles = [];
const missingFiles = [];
for (const f of requestedFiles) {
  if (fs.existsSync(f)) {
    verifiedFiles.push(f);
  } else {
    missingFiles.push(f);
  }
}

if (missingFiles.length > 0) {
  console.error(`[SLOP_GUARD] Handoff rejected: The following --files do not exist on disk: ${missingFiles.join(", ")}`);
  process.exit(2);
}

// 2. Compute and lock SHA-256 hashes for Golden Master files
const goldenPaths = lockGoldenCsv
  .split(",")
  .map(s => s.trim())
  .filter(Boolean);

if (!Array.isArray(plan.goldenLocks)) {
  plan.goldenLocks = [];
}

for (const gp of goldenPaths) {
  if (!fs.existsSync(gp) || !fs.statSync(gp).isFile()) {
    console.error(`[SLOP_GUARD] Golden lock rejected: Golden file '${gp}' does not exist on disk.`);
    process.exit(2);
  }
  const content = fs.readFileSync(gp);
  if (content.length === 0) {
    console.error(`[SLOP_GUARD] Golden lock rejected: Golden file '${gp}' is empty (0 bytes).`);
    process.exit(2);
  }
  const sha256 = crypto.createHash("sha256").update(content).digest("hex");
  const existingLock = plan.goldenLocks.find(g => g.path === gp);
  if (existingLock && existingLock.lockedByStep !== stepId && existingLock.sha256 !== sha256) {
    console.error(`[SLOP_GUARD] Cannot overwrite Golden Master lock for '${gp}' (originally locked by '${existingLock.lockedByStep}').`);
    process.exit(3);
  }
  if (existingLock) {
    existingLock.sha256 = sha256;
    existingLock.updatedAt = new Date().toISOString();
  } else {
    plan.goldenLocks.push({
      path: gp,
      feature: step.feature,
      lockedByStep: stepId,
      sha256,
      bytes: content.length,
      lockedAt: new Date().toISOString()
    });
  }
}

// 3. Cap summary length to prevent context poisoning across sessions
const cleanSummary = rawSummary.trim().replace(/\s+/g, " ").slice(0, 500);
const remainingItems = remainingPipe
  .split("|")
  .map(s => s.trim())
  .filter(Boolean);

if (!Array.isArray(step.handoffHistory)) {
  step.handoffHistory = [];
}

step.handoffHistory.push({
  timestamp: new Date().toISOString(),
  reportedStatus: handoffStatus,
  summary: cleanSummary,
  verifiedFiles,
  remainingTodo: remainingItems
});

step.lastHandoff = {
  reportedStatus: handoffStatus,
  summary: cleanSummary,
  verifiedFiles,
  remainingTodo: remainingItems,
  updatedAt: new Date().toISOString()
};

// Update remainingTodo on the step itself for the next session
step.remainingTodo = handoffStatus === "NEEDS_MORE_WORK" ? remainingItems : [];

// Propagate discovered compileCmd to this step and subsequent sub-steps of the same feature if not set
if (discoveredCompileCmd) {
  step.compileCmd = discoveredCompileCmd;
  for (let i = stepIdx + 1; i < plan.steps.length; i++) {
    if (plan.steps[i].feature === step.feature && !plan.steps[i].compileCmd) {
      plan.steps[i].compileCmd = discoveredCompileCmd;
    }
  }
}

// 4. Optional: Dynamically spawn a bounded follow-up sub-step right after the current one
if (spawnSubstepTitle) {
  const maxCont = plan.maxContinuationsPerSubstep || 3;
  const currentSpawnCount = step.spawnedSubstepsCount || 0;
  if (currentSpawnCount >= maxCont) {
    console.error(`[SLOP_GUARD] Cannot spawn another follow-up sub-step from '${stepId}' (reached maxContinuationsPerSubstep=${maxCont}).`);
    process.exit(4);
  }
  step.spawnedSubstepsCount = currentSpawnCount + 1;
  const newId = `${stepId}-cont${step.spawnedSubstepsCount}`;
  const newSubstep = {
    id: newId,
    parentStepId: stepId,
    feature: step.feature,
    phase: step.phase,
    substepCode: `${step.substepCode || step.phase}.c${step.spawnedSubstepsCount}`,
    skill: step.skill,
    principles: step.principles,
    title: `${step.feature} — [Continuation ${step.spawnedSubstepsCount}] ${spawnSubstepTitle.trim()}`,
    goal: spawnSubstepTitle.trim(),
    compileCmd: step.compileCmd || "",
    status: "PENDING",
    attempts: 0,
    continuationsUsed: 0,
    remainingTodo: remainingItems,
    handoffHistory: [],
    attemptHistory: [],
    lastUpdatedAt: new Date().toISOString()
  };
  plan.steps.splice(stepIdx + 1, 0, newSubstep);
  console.log(`[mstack handoff] Spawned sequential follow-up sub-step '${newId}' -> ${newSubstep.title}`);
}

step.lastUpdatedAt = new Date().toISOString();
plan.updatedAt = new Date().toISOString();
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");

console.log(`[mstack handoff] Recorded handoff for '${stepId}' (reportedStatus=${handoffStatus}, verifiedFiles=${verifiedFiles.length}, goldenLocks=${plan.goldenLocks.length})`);
NODE_EOF

#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# mstack Long-Running Non-Interactive CLI Automation Runner
# Loops through a queued migration plan (.mstack/migration-plan.json), invoking any AI CLI tool
# (agy, claude, codex, gemini, cursor, aider, or a custom command) in non-interactive headless mode
# to solve persistent "agent stops after 1 migration plan step" behavior.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_EVIDENCE="$SCRIPT_DIR/log-evidence.sh"
COMPILE_GATE="$SCRIPT_DIR/compile-gate.sh"

PLAN_FILE=".mstack/migration-plan.json"
CLI_PRESET=""
CUSTOM_CLI_CMD=""
FEATURE_CSV=""
PHASES_CSV="step1,step2,step3"
MAX_STEPS=0
MAX_RETRIES=3
INIT_ONLY=false
STATUS_ONLY=false
DRY_RUN=false
RESET_FAILED=false

usage() {
  cat <<'EOF'
Usage:
  ./mobile-migration-tools/scripts/automate-plan.sh [options]
  npx mobile-migration-tools automate [options]

Description:
  Long-running non-interactive automation runner for mstack migrations.
  Solves the problem where an AI skill stops after completing 1 migration step
  by maintaining a persistent state machine in .mstack/migration-plan.json and
  repeatedly invoking your chosen CLI agent in non-interactive mode (1 fresh context
  per step) until every step in the plan is COMPLETED and passes compile-gate.sh.

Options:
  --features <F1,F2,...>     Initialize/append features to .mstack/migration-plan.json
  --phases <P1,P2,...>       Phases to queue per feature (default: step1,step2,step3)
                             Valid phases: step1, step2, step3, step4-greenfield, step4-cutover
  --init-only                Only generate/update .mstack/migration-plan.json without running
  --status                   Print current progress of .mstack/migration-plan.json and exit
  --reset-failed             Reset any FAILED or IN_PROGRESS steps back to PENDING
  --cli <preset>             CLI tool preset to use in non-interactive mode:
                               agy     : agy -p "<prompt>"
                               claude  : claude -p "<prompt>" --dangerously-skip-permissions
                               codex   : codex exec --full-auto "<prompt>"
                               gemini  : gemini -p "<prompt>" --yolo
                               aider   : aider --yes-always --message "<prompt>"
  --cli-cmd "<template>"     Custom non-interactive CLI command template.
                             If it contains {PROMPT} or {PROMPT_FILE}, they are replaced;
                             otherwise the prompt is passed as the final argument.
  --plan <path>              Path to migration plan JSON (default: .mstack/migration-plan.json)
  --max-steps <N>            Stop after completing N steps (0 = run all pending steps)
  --max-retries <N>          Max automatic self-healing retries per step (default: 3)
  --dry-run                  Print the non-interactive CLI commands without executing them
  -h, --help                 Show this help message

Examples:
  # 1. Initialize a multi-feature migration plan and run it unattended with Claude Code CLI:
  npx mobile-migration-tools automate --features "Login,PaymentConfirmation,TransferReceipt" --cli claude

  # 2. Run unattended with Antigravity CLI (agy):
  npx mobile-migration-tools automate --features "PaymentConfirmation" --cli agy

  # 3. Run unattended with OpenAI Codex or Gemini CLI:
  npx mobile-migration-tools automate --cli codex
  npx mobile-migration-tools automate --cli gemini

  # 4. Run with any custom CLI command template:
  npx mobile-migration-tools automate --cli-cmd 'my-agent-cli run --headless --prompt-file {PROMPT_FILE}'
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --features)
      FEATURE_CSV="${2:-}"
      shift 2
      ;;
    --phases)
      PHASES_CSV="${2:-}"
      shift 2
      ;;
    --init-only)
      INIT_ONLY=true
      shift
      ;;
    --status)
      STATUS_ONLY=true
      shift
      ;;
    --reset-failed)
      RESET_FAILED=true
      shift
      ;;
    --cli)
      CLI_PRESET="${2:-}"
      shift 2
      ;;
    --cli-cmd)
      CUSTOM_CLI_CMD="${2:-}"
      shift 2
      ;;
    --plan)
      PLAN_FILE="${2:-}"
      shift 2
      ;;
    --max-steps)
      MAX_STEPS="${2:-0}"
      shift 2
      ;;
    --max-retries)
      MAX_RETRIES="${2:-3}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$PLAN_FILE")" .mstack/logs .mstack/prompts

# Ensure target-profile.json exists (or create a sensible non-interactive default if missing)
if [[ ! -f ".mstack/target-profile.json" ]]; then
  echo "[mstack automate] .mstack/target-profile.json not found. Generating default non-interactive profile..."
  cat > ".mstack/target-profile.json" <<'EOF'
{
  "projectType": "auto-detected",
  "executionMode": "non-interactive-automation",
  "legacyBaseline": {
    "languages": ["Java", "Kotlin", "Objective-C", "Swift"],
    "ui": "Legacy XML / Storyboard Views",
    "navigation": "Legacy Activities / Fragments / ViewControllers",
    "storage": "Legacy SharedPreferences / SQLite / NSUserDefaults",
    "network": "Legacy Network Stack"
  },
  "targetStack": {
    "platform": "Kotlin Multiplatform (KMP) + Compose Multiplatform",
    "moduleStructure": ":features:<name>:api + :features:<name>:impl",
    "ui": "Compose Multiplatform (Stateless + Stateful split)",
    "presentation": "Unidirectional MVI (sealed UiState, Event, Effect)",
    "navigation": "Navigation 3 (NavKey, NavDisplay) + Material 3 Adaptive SceneStrategy (Foldables)",
    "di": "Koin",
    "storage": "Room KMP + DataStore (via Synced StorageBridge)",
    "network": "Ktor + kotlinx.serialization"
  },
  "verification": {
    "compileGateCommand": "",
    "visualParityTool": "Roborazzi (<= 0.1% pixel diff)",
    "logicParityTool": "Golden Master Approval Tests + Scientist Shadow Runner",
    "e2eParityTool": "Maestro"
  }
}
EOF
fi

# Initialize or append features to .mstack/migration-plan.json using node
if [[ -n "$FEATURE_CSV" ]]; then
  node - "$PLAN_FILE" "$FEATURE_CSV" "$PHASES_CSV" <<'NODE_EOF'
const fs = require("node:fs");
const [planFile, featureCsv, phasesCsv] = process.argv.slice(2);

let plan = {
  version: "1.0",
  executionMode: "non-interactive",
  updatedAt: new Date().toISOString(),
  steps: []
};

if (fs.existsSync(planFile)) {
  try {
    plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
    if (!Array.isArray(plan.steps)) plan.steps = [];
  } catch (e) {
    console.error("Warning: Reinitializing malformed plan file:", planFile);
  }
}

const phaseMetadata = {
  "step1": {
    skill: "mstack-step1-logic-storage",
    principles: "principle-always-compile,principle-scientist-parity",
    title: "Step 1: Business Logic & Synced Storage Extraction (Golden Master + Scientist)"
  },
  "step2": {
    skill: "mstack-step2-ui-parity",
    principles: "principle-always-compile,principle-visual-golden-master,principle-decouple-ui-and-nav",
    title: "Step 2: Pixel-Exact Declarative UI Parity Inside Existing Host (<= 0.1% Diff)"
  },
  "step3": {
    skill: "mstack-step3-navigation-adaptive",
    principles: "principle-always-compile,principle-decouple-ui-and-nav",
    title: "Step 3: Navigation 3 & Foldable Adaptive Scenes Upgrade + E2E Parity"
  },
  "step4-greenfield": {
    skill: "mstack-step4-greenfield-cutover",
    principles: "principle-always-compile,principle-scientist-parity,principle-decouple-ui-and-nav",
    title: "Step 4 (Track A): Parallel Greenfield Feature on Target Stack"
  },
  "step4-cutover": {
    skill: "mstack-step4-greenfield-cutover",
    principles: "principle-always-compile",
    title: "Step 4 (Track B): Safe Legacy Java/XML Decommissioning & Cutover"
  }
};

const features = featureCsv.split(",").map(s => s.trim()).filter(Boolean);
const phases = phasesCsv.split(",").map(s => s.trim()).filter(Boolean);

for (const feature of features) {
  const slug = feature.replace(/[^a-zA-Z0-9_-]/g, "-").toLowerCase();
  for (const phase of phases) {
    const meta = phaseMetadata[phase] || {
      skill: phase,
      principles: "principle-always-compile",
      title: `Migration Phase: ${phase}`
    };
    const id = `${slug}-${phase}`;
    const exists = plan.steps.some(s => s.id === id);
    if (!exists) {
      plan.steps.push({
        id,
        feature,
        phase,
        skill: meta.skill,
        principles: meta.principles,
        title: `${feature} — ${meta.title}`,
        compileCmd: "",
        status: "PENDING",
        attempts: 0,
        lastUpdatedAt: new Date().toISOString()
      });
    }
  }
}

plan.updatedAt = new Date().toISOString();
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");
console.log(`[mstack automate] Updated plan file: ${planFile} (${plan.steps.length} total steps)`);
NODE_EOF
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: No migration plan found at $PLAN_FILE." >&2
  echo "Initialize one with: npx mobile-migration-tools automate --features \"FeatureA,FeatureB\"" >&2
  exit 1
fi

if [[ "$RESET_FAILED" == "true" ]]; then
  node - "$PLAN_FILE" <<'NODE_EOF'
const fs = require("node:fs");
const planFile = process.argv[2];
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
let count = 0;
for (const s of plan.steps) {
  if (s.status === "FAILED" || s.status === "IN_PROGRESS") {
    s.status = "PENDING";
    s.attempts = 0;
    s.lastUpdatedAt = new Date().toISOString();
    count++;
  }
}
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");
console.log(`[mstack automate] Reset ${count} FAILED/IN_PROGRESS step(s) back to PENDING.`);
NODE_EOF
fi

print_status() {
  node - "$PLAN_FILE" <<'NODE_EOF'
const fs = require("node:fs");
const planFile = process.argv[2];
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
const counts = { COMPLETED: 0, PENDING: 0, IN_PROGRESS: 0, FAILED: 0 };
console.log("\n=== mstack Automation Plan Status ===");
console.log(`Plan File: ${planFile}`);
console.log("--------------------------------------------------------------------------------");
for (const s of plan.steps) {
  counts[s.status] = (counts[s.status] || 0) + 1;
  const icon = s.status === "COMPLETED" ? "[PASS]" : s.status === "FAILED" ? "[FAIL]" : s.status === "IN_PROGRESS" ? "[RUN ]" : "[WAIT]";
  console.log(`${icon} ${s.id.padEnd(32)} | ${s.status.padEnd(11)} | attempts: ${s.attempts || 0} | ${s.title}`);
}
console.log("--------------------------------------------------------------------------------");
console.log(`Summary: ${counts.COMPLETED} COMPLETED, ${counts.PENDING} PENDING, ${counts.IN_PROGRESS} IN_PROGRESS, ${counts.FAILED} FAILED (Total: ${plan.steps.length})\n`);
NODE_EOF
}

if [[ "$STATUS_ONLY" == "true" || "$INIT_ONLY" == "true" ]]; then
  print_status
  exit 0
fi

# Resolve CLI preset or auto-detect available CLI binary if not specified
if [[ -z "$CUSTOM_CLI_CMD" && -z "$CLI_PRESET" ]]; then
  if command -v claude >/dev/null 2>&1; then
    CLI_PRESET="claude"
  elif command -v agy >/dev/null 2>&1; then
    CLI_PRESET="agy"
  elif command -v gemini >/dev/null 2>&1; then
    CLI_PRESET="gemini"
  elif command -v codex >/dev/null 2>&1; then
    CLI_PRESET="codex"
  elif command -v aider >/dev/null 2>&1; then
    CLI_PRESET="aider"
  else
    echo "ERROR: No CLI tool specified and none of (claude, agy, gemini, codex, aider) found on PATH." >&2
    echo "Pass --cli <agy|claude|codex|gemini|aider> or --cli-cmd '<custom-command>'." >&2
    exit 1
  fi
fi

run_cli_with_prompt() {
  local prompt_file="$1"
  local log_file="$2"
  local prompt_text
  prompt_text="$(cat "$prompt_file")"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would execute non-interactive CLI (${CLI_PRESET:-custom}) with prompt file: $prompt_file"
    return 0
  fi

  if [[ -n "$CUSTOM_CLI_CMD" ]]; then
    local cmd="$CUSTOM_CLI_CMD"
    if [[ "$cmd" == *"{PROMPT_FILE}"* ]]; then
      cmd="${cmd//\{PROMPT_FILE\}/$prompt_file}"
      eval "$cmd" >"$log_file" 2>&1
    elif [[ "$cmd" == *"{PROMPT}"* ]]; then
      # Export prompt as env var to avoid shell escaping bugs
      MSTACK_PROMPT="$prompt_text" eval "${cmd//\{PROMPT\}/\"\$MSTACK_PROMPT\"}" >"$log_file" 2>&1
    else
      eval "$cmd" '"$prompt_text"' >"$log_file" 2>&1
    fi
    return $?
  fi

  case "$CLI_PRESET" in
    agy)
      agy -p "$prompt_text" >"$log_file" 2>&1
      ;;
    claude)
      claude -p "$prompt_text" --dangerously-skip-permissions >"$log_file" 2>&1
      ;;
    codex)
      codex exec --full-auto "$prompt_text" >"$log_file" 2>&1
      ;;
    gemini)
      gemini -p "$prompt_text" --yolo >"$log_file" 2>&1
      ;;
    aider)
      aider --yes-always --message "$prompt_text" >"$log_file" 2>&1
      ;;
    *)
      echo "ERROR: Unsupported --cli preset '$CLI_PRESET'. Use agy, claude, codex, gemini, aider, or --cli-cmd." >&2
      return 2
      ;;
  esac
}

update_step_state() {
  local step_id="$1"
  local new_status="$2"
  local inc_attempt="${3:-false}"
  node - "$PLAN_FILE" "$step_id" "$new_status" "$inc_attempt" <<'NODE_EOF'
const fs = require("node:fs");
const [planFile, stepId, newStatus, incAttempt] = process.argv.slice(2);
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
for (const s of plan.steps) {
  if (s.id === stepId) {
    s.status = newStatus;
    if (incAttempt === "true") {
      s.attempts = (s.attempts || 0) + 1;
    }
    s.lastUpdatedAt = new Date().toISOString();
    break;
  }
}
plan.updatedAt = new Date().toISOString();
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");
NODE_EOF
}

get_next_pending_step_json() {
  node - "$PLAN_FILE" <<'NODE_EOF'
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const next = plan.steps.find(s => s.status === "PENDING" || s.status === "IN_PROGRESS");
if (next) {
  console.log(JSON.stringify(next));
}
NODE_EOF
}

echo "================================================================================"
echo "🚀 mstack Long-Running Non-Interactive CLI Automation"
echo "   Plan File   : $PLAN_FILE"
echo "   CLI Runner  : ${CUSTOM_CLI_CMD:-$CLI_PRESET}"
echo "   Max Retries : $MAX_RETRIES per step"
echo "================================================================================"

STEPS_COMPLETED_THIS_RUN=0

while true; do
  if [[ "$MAX_STEPS" -gt 0 && "$STEPS_COMPLETED_THIS_RUN" -ge "$MAX_STEPS" ]]; then
    echo "[mstack automate] Reached --max-steps ($MAX_STEPS). Stopping loop."
    break
  fi

  NEXT_JSON="$(get_next_pending_step_json)"
  if [[ -z "$NEXT_JSON" ]]; then
    echo "✅ [mstack automate] All migration steps in $PLAN_FILE are COMPLETED!"
    break
  fi

  STEP_ID=$(node -e 'console.log(JSON.parse(process.argv[1]).id)' "$NEXT_JSON")
  FEATURE=$(node -e 'console.log(JSON.parse(process.argv[1]).feature)' "$NEXT_JSON")
  PHASE=$(node -e 'console.log(JSON.parse(process.argv[1]).phase)' "$NEXT_JSON")
  SKILL=$(node -e 'console.log(process.argv[1] ? JSON.parse(process.argv[1]).skill : "")' "$NEXT_JSON")
  PRINCIPLES=$(node -e 'console.log(process.argv[1] ? JSON.parse(process.argv[1]).principles : "principle-always-compile")' "$NEXT_JSON")
  TITLE=$(node -e 'console.log(process.argv[1] ? JSON.parse(process.argv[1]).title : "")' "$NEXT_JSON")
  STEP_COMPILE_CMD=$(node -e 'console.log(process.argv[1] ? (JSON.parse(process.argv[1]).compileCmd || "") : "")' "$NEXT_JSON")

  echo ""
  echo "--------------------------------------------------------------------------------"
  echo "▶ Executing Step: $STEP_ID ($TITLE)"
  echo "  Skill         : $SKILL"
  echo "  Principles    : $PRINCIPLES"
  echo "--------------------------------------------------------------------------------"

  STEP_SUCCEEDED=false
  LAST_ERROR_TAIL=""

  for (( ATTEMPT=1; ATTEMPT<=MAX_RETRIES; ATTEMPT++ )); do
    update_step_state "$STEP_ID" "IN_PROGRESS" "true"
    TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
    PROMPT_FILE=".mstack/prompts/prompt_${STEP_ID}_attempt${ATTEMPT}.md"
    AGENT_LOG=".mstack/logs/agent_${STEP_ID}_attempt${ATTEMPT}_${TIMESTAMP}.log"

    cat > "$PROMPT_FILE" <<EOF
# NON-INTERACTIVE HEADLESS EXECUTION MODE (\`mstack-automation\`)

You are running in **unattended, non-interactive CLI automation mode** for \`mobile-migration-tools\` (\`mstack\`).

## STRICT NON-INTERACTIVE RULES (MANDATORY)
1. **DO NOT ask the user any questions.** Do NOT call \`ask_question\` or pause for human confirmation or approval checkpoints.
2. Read \`.mstack/target-profile.json\` for the target architecture and stack decisions.
3. Read and execute the skill \`mobile-migration-tools/skills/${SKILL}/SKILL.md\` for feature **\`${FEATURE}\`** (Step ID: \`${STEP_ID}\` — ${TITLE}).
4. Execute **all sub-steps** of \`${SKILL}\` for \`${FEATURE}\` completely in this session.
5. After every atomic sub-step, run:
   \`\`\`bash
   ./mobile-migration-tools/scripts/compile-gate.sh "${STEP_ID}" "${PRINCIPLES}" "Automated execution of ${STEP_ID}" ${STEP_COMPILE_CMD:+"\"$STEP_COMPILE_CMD\""}
   \`\`\`
6. If compilation or parity tests fail, fix the root cause immediately and re-run \`compile-gate.sh\` until \`COMPILE_PASSED\` before exiting.
EOF

    if [[ -n "$LAST_ERROR_TAIL" ]]; then
      cat >> "$PROMPT_FILE" <<EOF

## PREVIOUS ATTEMPT FAILURE TO FIX IMMEDIATELY
Attempt $((ATTEMPT - 1)) failed verification with the following output. Fix this root cause first:
\`\`\`text
${LAST_ERROR_TAIL}
\`\`\`
EOF
    fi

    echo "  [Attempt $ATTEMPT/$MAX_RETRIES] Invoking non-interactive CLI agent (log: $AGENT_LOG)..."
    set +e
    run_cli_with_prompt "$PROMPT_FILE" "$AGENT_LOG"
    CLI_EXIT=$?
    set -e

    if [[ "$DRY_RUN" == "true" ]]; then
      STEP_SUCCEEDED=true
      break
    fi

    echo "  [Attempt $ATTEMPT/$MAX_RETRIES] Running mandatory post-step compile-gate.sh verification..."
    set +e
    "$COMPILE_GATE" "$STEP_ID" "$PRINCIPLES" "Automated verification gate for $STEP_ID (attempt $ATTEMPT)" "$STEP_COMPILE_CMD"
    GATE_EXIT=$?
    set -e

    if [[ $CLI_EXIT -eq 0 && $GATE_EXIT -eq 0 ]]; then
      echo "  ✔ Step '$STEP_ID' PASSED on attempt $ATTEMPT!"
      STEP_SUCCEEDED=true
      break
    else
      echo "  ✖ Step '$STEP_ID' failed on attempt $ATTEMPT (CLI exit: $CLI_EXIT, Gate exit: $GATE_EXIT)." >&2
      LATEST_COMPILE_LOG=$(ls -t .mstack/logs/compile_${STEP_ID}_*.log 2>/dev/null | head -n 1 || true)
      if [[ -n "$LATEST_COMPILE_LOG" && -f "$LATEST_COMPILE_LOG" ]]; then
        LAST_ERROR_TAIL="$(tail -n 60 "$LATEST_COMPILE_LOG")"
      elif [[ -f "$AGENT_LOG" ]]; then
        LAST_ERROR_TAIL="$(tail -n 60 "$AGENT_LOG")"
      fi
    fi
  done

  if [[ "$STEP_SUCCEEDED" == "true" ]]; then
    update_step_state "$STEP_ID" "COMPLETED" "false"
    "$LOG_EVIDENCE" "$STEP_ID" "$PRINCIPLES" "Completed automated step $STEP_ID for $FEATURE" "${CUSTOM_CLI_CMD:-$CLI_PRESET}" "$PLAN_FILE" "STEP_COMPLETED"
    STEPS_COMPLETED_THIS_RUN=$((STEPS_COMPLETED_THIS_RUN + 1))
  else
    update_step_state "$STEP_ID" "FAILED" "false"
    "$LOG_EVIDENCE" "$STEP_ID" "$PRINCIPLES" "Failed automated step $STEP_ID after $MAX_RETRIES attempts" "${CUSTOM_CLI_CMD:-$CLI_PRESET}" "$PLAN_FILE" "STEP_FAILED"
    echo "❌ [mstack automate] Step '$STEP_ID' failed after $MAX_RETRIES attempts. Stopping loop to preserve Always-Compile discipline." >&2
    print_status
    exit 1
  fi
done

print_status

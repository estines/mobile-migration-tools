#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.gemini/bin:$HOME/.gemini/antigravity/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# mstack Long-Running Non-Interactive Sub-Step Automation Runner (v2 — Atomic Sub-Step + Handoff + Anti-Slop)
#
# Behavior:
# 1. Expands features into sequential atomic sub-steps (1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4)
#    inside .mstack/migration-plan.json.
# 2. Spawns 1 fresh non-interactive CLI session per 1 sub-step sequentially.
# 3. Every sub-step session records what was completed via handoff-substep.sh (summary, verified files, golden locks)
#    and, if more work is needed, assigns remainingTodo (status=NEEDS_MORE_WORK or --spawn-substep) to the next spawned agent.
# 4. Enforces Anti-Slop Circuit Breakers:
#    - Golden Master SHA-256 lock verification (prevents overwriting baselines from 1.1/2.1/3.1)
#    - Non-empty diff guard (prevents no-op handoff procrastination loops)
#    - Bounded continuations (--max-continuations, default 3 per sub-step)
#    - Cumulative attemptHistory + same-error-hash ping-pong circuit breaker

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_EVIDENCE="$SCRIPT_DIR/log-evidence.sh"
COMPILE_GATE="$SCRIPT_DIR/compile-gate.sh"
HANDOFF_SCRIPT="$SCRIPT_DIR/handoff-substep.sh"

PLAN_FILE=".mstack/migration-plan.json"
CLI_PRESET=""
CUSTOM_CLI_CMD=""
FEATURE_CSV=""
PHASES_CSV="step1,step2,step3"
GRANULARITY="substep"
MAX_STEPS=0
MAX_RETRIES=3
MAX_CONTINUATIONS=3
INIT_ONLY=false
STATUS_ONLY=false
DRY_RUN=false
RESET_FAILED=false
ALLOW_NOOP=false
RUN_BACKGROUND=false
STOP_AUTOMATION=false
OPEN_DASHBOARD=false

usage() {
  cat <<'EOF'
Usage:
  ./mobile-migration-tools/scripts/automate-plan.sh [options]
  npx mobile-migration-tools automate [options]

Description:
  Sequential 1-sub-step-per-session non-interactive automation runner with verified
  agent-to-agent handoffs, 3D hologram dashboard, and anti-slop circuit breakers.

Options:
  --features <F1,F2,...>       Initialize/append features to .mstack/migration-plan.json
  --phases <P1,P2,...>         Phases to queue per feature (default: step1,step2,step3)
                               Valid phases: step1, step2, step3, step4-greenfield, step4-cutover
  --granularity <mode>         'substep' (default: 1.1, 1.2, 1.3, 1.4... 1 sub-step per session)
                               or 'phase' (coarse step1, step2, step3)
  --background, --daemon       Run unattended automation loop detached in the background
  --stop                       Stop running background automation process
  --open-dashboard             Automatically launch 3D HTML dashboard in default browser
  --init-only                  Only generate/update .mstack/migration-plan.json and dashboard without running
  --status                     Print detailed progress & handoff state of .mstack/migration-plan.json
  --reset-failed               Reset any FAILED or IN_PROGRESS sub-steps back to PENDING
  --cli <preset>               CLI tool preset to run in non-interactive mode (auto-approves permissions):
                                 agy     : agy -p "<prompt>" --dangerously-skip-permissions
                                 claude  : claude -p "<prompt>" --dangerously-skip-permissions
                                 codex   : codex exec --full-auto "<prompt>"
                                 gemini  : gemini -p "<prompt>" --yolo
                                 aider   : aider --yes-always --no-auto-commits --message "<prompt>"
  --cli-cmd "<template>"       Custom non-interactive CLI command template ({PROMPT_FILE} or {PROMPT})
  --plan <path>                Path to migration plan JSON (default: .mstack/migration-plan.json)
  --max-steps <N>              Stop after completing N sub-step sessions (0 = run all pending)
  --max-retries <N>            Max automatic self-healing retries per sub-step attempt (default: 3)
  --max-continuations <N>      Max sequential continuation sessions a sub-step can hand off (default: 3)
  --allow-noop                 Allow sessions with zero git file changes to pass if compile-gate passes
  --dry-run                    Print the non-interactive CLI session prompts/commands without executing
  -h, --help                   Show this help message
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
    --granularity)
      GRANULARITY="${2:-substep}"
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
    --max-continuations)
      MAX_CONTINUATIONS="${2:-3}"
      shift 2
      ;;
    --allow-noop)
      ALLOW_NOOP=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --background|--daemon)
      RUN_BACKGROUND=true
      shift
      ;;
    --stop)
      STOP_AUTOMATION=true
      shift
      ;;
    --open-dashboard)
      OPEN_DASHBOARD=true
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

if [[ "$STOP_AUTOMATION" == "true" ]]; then
  PID_FILE=".mstack/automation.pid"
  if [[ -f "$PID_FILE" ]]; then
    RUNNER_PID="$(cat "$PID_FILE" | tr -d ' ')"
    if [[ -n "$RUNNER_PID" ]] && kill -0 "$RUNNER_PID" 2>/dev/null; then
      echo "[mstack automate] Terminating background automation runner (PID $RUNNER_PID)..."
      kill "$RUNNER_PID" 2>/dev/null || true
      sleep 1
      if kill -0 "$RUNNER_PID" 2>/dev/null; then
        kill -9 "$RUNNER_PID" 2>/dev/null || true
      fi
      rm -f "$PID_FILE"
      echo "✔ Background automation runner stopped."
      exit 0
    else
      rm -f "$PID_FILE"
      echo "[mstack automate] Removed stale PID file (process $RUNNER_PID was not running)."
      exit 0
    fi
  else
    echo "[mstack automate] No background automation process running (.mstack/automation.pid not found)."
    exit 0
  fi
fi

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
  node - "$PLAN_FILE" "$FEATURE_CSV" "$PHASES_CSV" "$GRANULARITY" "$MAX_CONTINUATIONS" <<'NODE_EOF'
const fs = require("node:fs");
const [planFile, featureCsv, phasesCsv, granularity, maxContStr] = process.argv.slice(2);
const maxContinuations = parseInt(maxContStr, 10) || 3;

let plan = {
  version: "2.0",
  executionMode: "sequential-substep-handoff",
  granularity: granularity || "substep",
  maxContinuationsPerSubstep: maxContinuations,
  updatedAt: new Date().toISOString(),
  goldenLocks: [],
  steps: []
};

if (fs.existsSync(planFile)) {
  try {
    const existing = JSON.parse(fs.readFileSync(planFile, "utf8"));
    plan = {
      ...plan,
      ...existing,
      version: "2.0",
      maxContinuationsPerSubstep: maxContinuations,
      goldenLocks: Array.isArray(existing.goldenLocks) ? existing.goldenLocks : [],
      steps: Array.isArray(existing.steps) ? existing.steps : []
    };
  } catch (e) {
    console.error("Warning: Reinitializing malformed plan file:", planFile);
  }
}

const substepCatalog = {
  "step1": [
    {
      suffix: "step1-1",
      substepCode: "1.1",
      skill: "mstack-step1-logic-storage",
      principles: "principle-always-compile,principle-scientist-parity",
      title: "Sub-Step 1.1: Characterize Legacy Logic & Record Golden Master Baseline",
      goal: "Identify all legacy classes/methods for this feature, write a Golden Master characterization test across boundary/null/rounding/locale inputs against the untouched legacy code, record the serialized Golden Master baseline file, and lock its SHA-256 via --lock-golden in handoff-substep.sh. Keep Legacy UI and Navigation 100% untouched.",
      requiresGoldenLock: true
    },
    {
      suffix: "step1-2",
      substepCode: "1.2",
      skill: "mstack-step1-logic-storage",
      principles: "principle-always-compile,principle-scientist-parity",
      title: "Sub-Step 1.2: Scaffold Target Module Pair & Synchronized Storage Proxy",
      goal: "Scaffold the target module pair (:api + :impl) and implement a Read-Through / Dual-Write Storage Proxy keeping legacy storage (SharedPreferences/SQLite/NSUserDefaults) and modern target storage (DataStore/Room) 100% synchronized with unit tests proving bidirectional read/write parity.",
      requiresGoldenLock: false
    },
    {
      suffix: "step1-3",
      substepCode: "1.3",
      skill: "mstack-step1-logic-storage",
      principles: "principle-always-compile,principle-scientist-parity",
      title: "Sub-Step 1.3: Implement Target Domain & Data Layer (100% Golden Match)",
      goal: "Implement pure domain models, value classes, mappers, repository, and UseCases in the target module and pass 100.0% of the locked Golden Master test cases from Sub-Step 1.1 without modifying the locked Golden Master baseline.",
      requiresGoldenLock: false
    },
    {
      suffix: "step1-4",
      substepCode: "1.4",
      skill: "mstack-step1-logic-storage",
      principles: "principle-always-compile,principle-scientist-parity",
      title: "Sub-Step 1.4: Wire Scientist Dual-Execution Runner in Legacy Host",
      goal: "Wire a Scientist shadow wrapper inside the legacy presenter/ViewModel/Activity that executes Legacy (Control) and New Target (Candidate) in parallel and verifies 0.00% discrepancy in tests while leaving Legacy UI and Navigation untouched.",
      requiresGoldenLock: false
    }
  ],
  "step2": [
    {
      suffix: "step2-1",
      substepCode: "2.1",
      skill: "mstack-step2-ui-parity",
      principles: "principle-always-compile,principle-visual-golden-master,principle-decouple-ui-and-nav",
      title: "Sub-Step 2.1: Capture Legacy View Golden Master PNGs",
      goal: "Render the real untouched legacy XML/Storyboard/View across all visual states (Loading, Content, Empty, Error) and locales into Golden Master PNGs and lock their SHA-256 hashes via --lock-golden in handoff-substep.sh.",
      requiresGoldenLock: true
    },
    {
      suffix: "step2-2",
      substepCode: "2.2",
      skill: "mstack-step2-ui-parity",
      principles: "principle-always-compile,principle-visual-golden-master,principle-decouple-ui-and-nav",
      title: "Sub-Step 2.2: Implement Stateless Declarative UI + Legacy-Compat Bridge Theme",
      goal: "Build stateless declarative UI (<Screen>Content(state, onEvent)) using a Legacy-Compat Bridge Theme (matching font padding, line heights, density, and preserving original test tags/IDs). Keep Legacy Navigation 100% untouched.",
      requiresGoldenLock: false
    },
    {
      suffix: "step2-3",
      substepCode: "2.3",
      skill: "mstack-step2-ui-parity",
      principles: "principle-always-compile,principle-visual-golden-master,principle-decouple-ui-and-nav",
      title: "Sub-Step 2.3: Automated Pixel-Diff Gate (<= 0.1% vs Locked Golden PNGs)",
      goal: "Run automated screenshot comparison of the new declarative UI against the locked Golden Master PNGs from Sub-Step 2.1 and fix any spacing/typography/color drift until pixel difference is <= 0.1% across all states without modifying the locked Golden PNGs.",
      requiresGoldenLock: false
    },
    {
      suffix: "step2-4",
      substepCode: "2.4",
      skill: "mstack-step2-ui-parity",
      principles: "principle-always-compile,principle-visual-golden-master,principle-decouple-ui-and-nav",
      title: "Sub-Step 2.4: Swap View Host Inside Existing Untouched Navigation Shell",
      goal: "Replace setContentView(R.layout...) / legacy view loading with ComposeView / UIHostingController inside the existing Activity/Fragment/ViewController while keeping all Intent extras, arguments, result contracts, and navigation transitions 100% untouched.",
      requiresGoldenLock: false
    }
  ],
  "step3": [
    {
      suffix: "step3-1",
      substepCode: "3.1",
      skill: "mstack-step3-navigation-adaptive",
      principles: "principle-always-compile,principle-decouple-ui-and-nav",
      title: "Sub-Step 3.1: Extract Legacy Navigation State Machine & Baseline E2E Flow",
      goal: "Document all inbound Intent extras, deep links, back-stack flags, and result contracts for the flow, and record a baseline navigation test / Maestro E2E flow YAML (locked via --lock-golden).",
      requiresGoldenLock: false
    },
    {
      suffix: "step3-2",
      substepCode: "3.2",
      skill: "mstack-step3-navigation-adaptive",
      principles: "principle-always-compile,principle-decouple-ui-and-nav",
      title: "Sub-Step 3.2: Implement Typed Routes (NavKey) & NavDisplay Back Stack",
      goal: "Define @Serializable NavKey routes in :api and register EntryProviderScope<NavKey> entries in :impl backed by rememberNavBackStack, keeping a single inbound bridge from unmigrated callers.",
      requiresGoldenLock: false
    },
    {
      suffix: "step3-3",
      substepCode: "3.3",
      skill: "mstack-step3-navigation-adaptive",
      principles: "principle-always-compile,principle-decouple-ui-and-nav",
      title: "Sub-Step 3.3: Add Foldable & Large-Screen Adaptive Scenes (SceneStrategy)",
      goal: "Attach Material 3 Adaptive SceneStrategy (ListDetailSceneStrategy or SupportingPaneSceneStrategy) so unfolded foldables/tablets render multi-pane scenes while compact phones stay 100% identical to single-pane legacy flow.",
      requiresGoldenLock: false
    },
    {
      suffix: "step3-4",
      substepCode: "3.4",
      skill: "mstack-step3-navigation-adaptive",
      principles: "principle-always-compile,principle-decouple-ui-and-nav",
      title: "Sub-Step 3.4: Verify Backstack Unit Tests, Fold/Unfold Recreate & E2E Parity",
      goal: "Run pure JVM backstack state-machine unit tests, posture configuration recreation tests (ActivityScenario.recreate()), and verify the E2E Maestro navigation flow passes unmodified.",
      requiresGoldenLock: false
    }
  ],
  "step4-greenfield": [
    {
      suffix: "step4-gf-1",
      substepCode: "4A.1",
      skill: "mstack-step4-greenfield-cutover",
      principles: "principle-always-compile,principle-scientist-parity",
      title: "Sub-Step 4A.1: Scaffold Greenfield :api + :impl & Synced Storage Bridge",
      goal: "Scaffold the new feature's :api and :impl modules and wire any shared legacy user/session state through the Read-Through / Dual-Write Storage Bridge.",
      requiresGoldenLock: false
    },
    {
      suffix: "step4-gf-2",
      substepCode: "4A.2",
      skill: "mstack-step4-greenfield-cutover",
      principles: "principle-always-compile,principle-scientist-parity",
      title: "Sub-Step 4A.2: Implement Pure Domain, Data & MVI Presentation with Tests",
      goal: "Implement pure domain models, repository, and MVI ViewModel (sealed UiState, Event, Effect) with unit tests in commonTest.",
      requiresGoldenLock: false
    },
    {
      suffix: "step4-gf-3",
      substepCode: "4A.3",
      skill: "mstack-step4-greenfield-cutover",
      principles: "principle-always-compile,principle-decouple-ui-and-nav",
      title: "Sub-Step 4A.3: Implement Declarative UI, Foldable Scenes & 1-Line Legacy Bridge",
      goal: "Build stateless declarative UI + Foldable Adaptive SceneStrategy and expose a single 1-line bridge hook for legacy callers.",
      requiresGoldenLock: false
    }
  ],
  "step4-cutover": [
    {
      suffix: "step4-cut-1",
      substepCode: "4B.1",
      skill: "mstack-step4-greenfield-cutover",
      principles: "principle-always-compile",
      title: "Sub-Step 4B.1: Verify All Step 1-3 Gates & Remove Scientist Shadow Wrapper",
      goal: "Verify Steps 1, 2, and 3 are COMPLETED in .mstack/migration-plan.json and remove the temporary Scientist dual-execution wrapper so the target implementation is the sole runtime path.",
      requiresGoldenLock: false
    },
    {
      suffix: "step4-cut-2",
      substepCode: "4B.2",
      skill: "mstack-step4-greenfield-cutover",
      principles: "principle-always-compile",
      title: "Sub-Step 4B.2: Delete Retired Legacy Java/Obj-C/XML Files & Verify Clean Build",
      goal: "Delete the retired legacy classes and XML/Storyboard layouts, run compile-gate.sh, and log reduced legacy file counts via detect-project.sh.",
      requiresGoldenLock: false
    }
  ]
};

const features = featureCsv.split(",").map(s => s.trim()).filter(Boolean);
const phases = phasesCsv.split(",").map(s => s.trim()).filter(Boolean);

for (const feature of features) {
  const slug = feature.replace(/[^a-zA-Z0-9_-]/g, "-").toLowerCase();
  for (const phase of phases) {
    if (granularity === "phase") {
      const id = `${slug}-${phase}`;
      if (!plan.steps.some(s => s.id === id)) {
        plan.steps.push({
          id,
          feature,
          phase,
          substepCode: phase,
          skill: (substepCatalog[phase] && substepCatalog[phase][0].skill) || phase,
          principles: "principle-always-compile,principle-scientist-parity,principle-visual-golden-master,principle-decouple-ui-and-nav",
          title: `${feature} — Phase ${phase}`,
          goal: `Complete all sub-steps of ${phase} for ${feature}.`,
          compileCmd: "",
          status: "PENDING",
          attempts: 0,
          continuationsUsed: 0,
          remainingTodo: [],
          handoffHistory: [],
          attemptHistory: [],
          lastUpdatedAt: new Date().toISOString()
        });
      }
    } else {
      const entries = substepCatalog[phase] || [
        {
          suffix: phase,
          substepCode: phase,
          skill: phase,
          principles: "principle-always-compile",
          title: `Sub-Step ${phase}`,
          goal: `Execute ${phase} for ${feature}`,
          requiresGoldenLock: false
        }
      ];
      for (const entry of entries) {
        const id = `${slug}-${entry.suffix}`;
        if (!plan.steps.some(s => s.id === id)) {
          plan.steps.push({
            id,
            feature,
            phase,
            substepCode: entry.substepCode,
            skill: entry.skill,
            principles: entry.principles,
            title: `${feature} — ${entry.title}`,
            goal: entry.goal,
            requiresGoldenLock: Boolean(entry.requiresGoldenLock),
            compileCmd: "",
            status: "PENDING",
            attempts: 0,
            continuationsUsed: 0,
            remainingTodo: [],
            handoffHistory: [],
            attemptHistory: [],
            lastUpdatedAt: new Date().toISOString()
          });
        }
      }
    }
  }
}

plan.updatedAt = new Date().toISOString();
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");
console.log(`[mstack automate] Updated plan file: ${planFile} (${plan.steps.length} total sequential sub-steps)`);
NODE_EOF
fi

# Always synchronize 3D Hologram Dashboard on disk
if [[ -f "$PLAN_FILE" ]]; then
  node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
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
    s.status = (Array.isArray(s.remainingTodo) && s.remainingTodo.length > 0) ? "NEEDS_MORE_WORK" : "PENDING";
    s.attempts = 0;
    s.lastUpdatedAt = new Date().toISOString();
    count++;
  }
}
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");
console.log(`[mstack automate] Reset ${count} FAILED/IN_PROGRESS sub-step(s) for retry.`);
NODE_EOF
  node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
fi

print_status() {
  node - "$PLAN_FILE" <<'NODE_EOF'
const fs = require("node:fs");
const planFile = process.argv[2];
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
const counts = { COMPLETED: 0, PENDING: 0, NEEDS_MORE_WORK: 0, IN_PROGRESS: 0, FAILED: 0 };
console.log("\n=== mstack Sequential Sub-Step Automation Plan Status ===");
console.log(`Plan File    : ${planFile} (Granularity: ${plan.granularity || "substep"})`);
console.log(`Golden Locks : ${(plan.goldenLocks || []).length} locked baseline file(s)`);
console.log("----------------------------------------------------------------------------------------------------------------");
for (const s of plan.steps) {
  counts[s.status] = (counts[s.status] || 0) + 1;
  const icon =
    s.status === "COMPLETED" ? "[PASS]" :
    s.status === "FAILED" ? "[FAIL]" :
    s.status === "NEEDS_MORE_WORK" ? "[CONT]" :
    s.status === "IN_PROGRESS" ? "[RUN ]" : "[WAIT]";
  const contInfo = `cont:${s.continuationsUsed || 0}/${plan.maxContinuationsPerSubstep || 3}`;
  console.log(`${icon} ${s.id.padEnd(30)} | ${s.status.padEnd(15)} | try:${s.attempts || 0} ${contInfo} | ${s.title}`);
  if (s.lastHandoff && s.lastHandoff.summary) {
    console.log(`       ↳ Last Handoff: ${s.lastHandoff.summary}`);
  }
  if (Array.isArray(s.remainingTodo) && s.remainingTodo.length > 0) {
    console.log(`       ↳ Next Agent Todo: ${s.remainingTodo.join(" ; ")}`);
  }
}
console.log("----------------------------------------------------------------------------------------------------------------");
console.log(`Summary: ${counts.COMPLETED} COMPLETED, ${counts.NEEDS_MORE_WORK} NEEDS_MORE_WORK, ${counts.PENDING} PENDING, ${counts.IN_PROGRESS} IN_PROGRESS, ${counts.FAILED} FAILED (Total: ${plan.steps.length})\n`);
NODE_EOF
}

if [[ "$STATUS_ONLY" == "true" || "$INIT_ONLY" == "true" ]]; then
  node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
  print_status
  exit 0
fi

# Background / Daemon Dispatcher
if [[ "$RUN_BACKGROUND" == "true" ]]; then
  PID_FILE=".mstack/automation.pid"
  if [[ -f "$PID_FILE" ]]; then
    EXISTING_PID="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ' || true)"
    if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
      echo "⚠️  [mstack automate] An automation runner is ALREADY RUNNING in background (PID: $EXISTING_PID)."
      echo "   To monitor: tail -f .mstack/logs/automation.log"
      echo "   To stop   : ./mobile-migration-tools/scripts/automate-plan.sh --stop"
      DASH_URL="http://localhost:3333"
      [[ -f ".mstack/dashboard.url" ]] && DASH_URL="$(cat .mstack/dashboard.url | tr -d '\n')"
      echo "   3D Hologram: $DASH_URL"
      exit 0
    else
      rm -f "$PID_FILE"
    fi
  fi

  # Generate 3D dashboard upfront
  node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true

  # Ensure Dashboard server is active in background
  if ! pgrep -f "dashboard-server.js" >/dev/null 2>&1; then
    nohup node "$SCRIPT_DIR/dashboard-server.js" </dev/null >>.mstack/logs/dashboard-server.log 2>&1 &
    disown 2>/dev/null || true
    sleep 0.5
  fi

  FILTERED_ARGS=()
  for a in "$@"; do
    if [[ "$a" != "--background" && "$a" != "--daemon" ]]; then
      FILTERED_ARGS+=("$a")
    fi
  done

  echo "🚀 [mstack automate] Spawning non-interactive automation runner in background..."
  if [[ ${#FILTERED_ARGS[@]} -gt 0 ]]; then
    nohup "$SCRIPT_DIR/automate-plan.sh" "${FILTERED_ARGS[@]}" </dev/null >>.mstack/logs/automation.log 2>&1 &
  else
    nohup "$SCRIPT_DIR/automate-plan.sh" </dev/null >>.mstack/logs/automation.log 2>&1 &
  fi
  RUNNER_PID=$!
  disown 2>/dev/null || true
  echo "$RUNNER_PID" > "$PID_FILE"

  DASHBOARD_URL="http://localhost:3333"
  if [[ -f ".mstack/dashboard.url" ]]; then
    DASHBOARD_URL="$(cat .mstack/dashboard.url | tr -d '\n')"
  fi
  INDEX_FILE="$(pwd)/.mstack/dashboard/index.html"

  echo ""
  echo "================================================================================"
  echo "✔ mstack Background Automation Runner ACTIVE!"
  echo "   PID               : $RUNNER_PID"
  echo "   Runner Log        : .mstack/logs/automation.log"
  echo "   3D HTML Dashboard : $DASHBOARD_URL"
  echo "   Local HTML File   : file://$INDEX_FILE"
  echo "   Status Command    : npx mobile-migration-tools automate --status"
  echo "   Stop Command      : npx mobile-migration-tools automate --stop"
  echo "================================================================================"
  echo ""

  if [[ "$OPEN_DASHBOARD" == "true" && "$(uname)" == "Darwin" ]]; then
    open "$DASHBOARD_URL" 2>/dev/null || open "file://$INDEX_FILE" 2>/dev/null || true
  fi

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
    echo "[DRY-RUN] Would execute non-interactive CLI (${CLI_PRESET:-custom}) for 1 sub-step session with prompt file: $prompt_file"
    return 0
  fi

  # Auto-skip all permissions in unattended non-interactive mode across all CLI runners
  export CI=true
  export CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=1
  export ANTHROPIC_DANGEROUSLY_SKIP_PERMISSIONS=true
  export CLAUDE_AUTO_APPROVE=1

  if [[ -n "$CUSTOM_CLI_CMD" ]]; then
    local cmd="$CUSTOM_CLI_CMD"
    if [[ "$cmd" == *"{PROMPT_FILE}"* ]]; then
      cmd="${cmd//\{PROMPT_FILE\}/$prompt_file}"
      eval "$cmd" >"$log_file" 2>&1
    elif [[ "$cmd" == *"{PROMPT}"* ]]; then
      MSTACK_PROMPT="$prompt_text" eval "${cmd//\{PROMPT\}/\"\$MSTACK_PROMPT\"}" >"$log_file" 2>&1
    else
      eval "$cmd" '"$prompt_text"' >"$log_file" 2>&1
    fi
    return $?
  fi

  case "$CLI_PRESET" in
    agy)
      agy -p "$prompt_text" --dangerously-skip-permissions >"$log_file" 2>&1
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
      aider --yes-always --no-auto-commits --message "$prompt_text" >"$log_file" 2>&1
      ;;
    *)
      echo "ERROR: Unsupported --cli preset '$CLI_PRESET'. Use agy, claude, codex, gemini, aider, or --cli-cmd." >&2
      return 2
      ;;
  esac
}

get_git_tree_fingerprint() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (git status --porcelain; git diff) | shasum -a 256 | awk '{print $1}'
  else
    echo "no-git-$(date +%s)"
  fi
}

get_next_pending_step_json() {
  node - "$PLAN_FILE" <<'NODE_EOF'
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const next = plan.steps.find(s =>
  s.status === "NEEDS_MORE_WORK" || s.status === "PENDING" || s.status === "IN_PROGRESS"
);
if (next) {
  console.log(JSON.stringify(next));
}
NODE_EOF
}

build_substep_prompt() {
  local step_id="$1"
  local attempt="$2"
  local prompt_file="$3"
  node - "$PLAN_FILE" "$step_id" "$attempt" "$prompt_file" "$MAX_CONTINUATIONS" <<'NODE_EOF'
const fs = require("node:fs");
const [planFile, stepId, attemptStr, promptFile, maxContStr] = process.argv.slice(2);
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
const stepIdx = plan.steps.findIndex(s => s.id === stepId);
const step = plan.steps[stepIdx];

// Gather verified handoffs from earlier completed sub-steps of the same feature
const priorSteps = plan.steps
  .slice(0, stepIdx)
  .filter(s => s.feature === step.feature && s.lastHandoff);

let priorHandoffSection = "*(No prior sub-steps completed yet for this feature)*";
if (priorSteps.length > 0) {
  priorHandoffSection = priorSteps.map(ps => {
    const files = (ps.lastHandoff.verifiedFiles || []).join(", ") || "none listed";
    return `- **${ps.id}** (${ps.substepCode || ps.phase}): ${ps.lastHandoff.summary}\n  - Verified Files: \`${files}\``;
  }).join("\n");
}

// Gather locked Golden Master files for this feature
const featureLocks = (plan.goldenLocks || []).filter(g => g.feature === step.feature);
let goldenLockSection = "*(No Golden Master baselines locked yet for this feature)*";
if (featureLocks.length > 0) {
  goldenLockSection = featureLocks.map(g =>
    `- \`${g.path}\` (locked by \`${g.lockedByStep}\`, SHA-256: \`${g.sha256.slice(0, 16)}...\`) — **DO NOT MODIFY OR DELETE**`
  ).join("\n");
}

// Check if this session is a continuation of a partially completed sub-step
let continuationSection = "";
if (Array.isArray(step.remainingTodo) && step.remainingTodo.length > 0) {
  const prevSummary = step.lastHandoff ? step.lastHandoff.summary : "Partial progress completed.";
  continuationSection = `
## CONTINUATION HANDOFF FROM PREVIOUS SESSION ON THIS SUB-STEP (${step.continuationsUsed || 0}/${maxContStr})
The previous non-interactive session completed part of \`${step.id}\`:
- **Already Completed**: ${prevSummary}
- **Verified Files Touched**: \`${((step.lastHandoff && step.lastHandoff.verifiedFiles) || []).join(", ") || "none"}\`
- **Remaining Work Assigned to You in This Session**:
${step.remainingTodo.map((item, idx) => `  ${idx + 1}. ${item}`).join("\n")}
`;
}

// Check if previous attempts failed on this sub-step (Anti-Ping-Pong memory)
let attemptHistorySection = "";
if (Array.isArray(step.attemptHistory) && step.attemptHistory.length > 0) {
  attemptHistorySection = `
## PREVIOUS FAILED ATTEMPTS ON THIS SUB-STEP (DO NOT REPEAT THESE FAILURES)
${step.attemptHistory.map(a => `### Attempt ${a.attempt} (Reason: ${a.reason}, Error Hash: ${a.errorHash})
\`\`\`text
${a.errorTail}
\`\`\``).join("\n\n")}
`;
}

const goldenFlagHint = step.requiresGoldenLock
  ? `\n   --lock-golden "<comma-separated-paths-to-golden-baseline-files>" \\`
  : "";

const prompt = `# NON-INTERACTIVE SINGLE SUB-STEP SESSION (\`mstack-automation\`)

You are running in **unattended, non-interactive 1-sub-step-per-session mode** for \`mobile-migration-tools\` (\`mstack\`).

## CURRENT SESSION ASSIGNMENT (EXECUTE ONLY THIS 1 SUB-STEP)
- **Feature**: \`${step.feature}\`
- **Sub-Step ID**: \`${step.id}\` (\`${step.substepCode || step.phase}\`)
- **Title**: ${step.title}
- **Skill Reference**: \`mobile-migration-tools/skills/${step.skill}/SKILL.md\`
- **Required Principles**: \`${step.principles}\`
- **Sub-Step Goal**:
  > ${step.goal || step.title}

## VERIFIED HANDOFF CONTEXT FROM PREVIOUS SUB-STEPS
${priorHandoffSection}

## LOCKED GOLDEN MASTER BASELINES (IMMUTABLE ANTI-SLOP LOCK)
${goldenLockSection}
${continuationSection}${attemptHistorySection}
## MANDATORY EXECUTION & HANDOFF PROTOCOL FOR THIS SESSION
1. **Strict Scope (1 Sub-Step Only)**:
   - Do **NOT** ask the user any questions (\`ask_question\` is forbidden).
   - Read \`.mstack/target-profile.json\` and \`mobile-migration-tools/skills/${step.skill}/SKILL.md\`.
   - Execute **ONLY Sub-Step \`${step.id}\`** (do NOT jump ahead to subsequent sub-steps; the next sub-step will be spawned in a fresh session).
2. **Anti-Slop Rules**:
   - **Never modify or overwrite locked Golden Master files** created by earlier sub-steps. Fix candidate code to match the Golden Master.
   - **Never add \`@Ignore\` or \`@Disabled\`** to tests.
   - Keep Legacy UI and Navigation untouched during Step 1, and Legacy Navigation untouched during Step 2.
3. **Compile & Test Gate**:
   - Run the verification gate before finishing:
     \`\`\`bash
     ./mobile-migration-tools/scripts/compile-gate.sh "${step.id}" "${step.principles}" "Verified ${step.id}" ${step.compileCmd ? `"${step.compileCmd}"` : ""}
     \`\`\`
4. **Mandatory Handoff Update (MUST RUN BEFORE EXITING)**:
   - **Case A — You completed all work for Sub-Step \`${step.id}\`**:
     \`\`\`bash
     ./mobile-migration-tools/scripts/handoff-substep.sh \\
       --step-id "${step.id}" \\
       --status DONE \\
       --summary "<concise summary of classes/tests created and parity results>" \\
       --files "<comma-separated-paths-of-created-or-modified-files>"${goldenFlagHint}
     \`\`\`
   - **Case B — Sub-Step \`${step.id}\` is very large, your partial slice compiles cleanly, and you need the next spawned session to finish remaining items**:
     \`\`\`bash
     ./mobile-migration-tools/scripts/handoff-substep.sh \\
       --step-id "${step.id}" \\
       --status NEEDS_MORE_WORK \\
       --summary "<what you completed and verified in this session>" \\
       --files "<comma-separated-paths-of-created-or-modified-files>" \\
       --remaining "<concrete remaining task 1|concrete remaining task 2>"
     \`\`\`
`;

fs.writeFileSync(promptFile, prompt, "utf8");
NODE_EOF
}

record_attempt_failure() {
  local step_id="$1"
  local attempt="$2"
  local reason="$3"
  local error_tail="$4"
  node - "$PLAN_FILE" "$step_id" "$attempt" "$reason" "$error_tail" <<'NODE_EOF'
const fs = require("node:fs");
const crypto = require("node:crypto");
const [planFile, stepId, attemptStr, reason, errorTail] = process.argv.slice(2);
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
const step = plan.steps.find(s => s.id === stepId);
if (!step) process.exit(0);

if (!Array.isArray(step.attemptHistory)) step.attemptHistory = [];

// Normalize timestamps/paths when computing errorHash to detect identical ping-pong errors
const normalized = (errorTail || reason)
  .replace(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*/g, "")
  .replace(/\b\d+ms\b|\b\d+s\b/g, "")
  .trim();
const errorHash = crypto.createHash("sha256").update(normalized).digest("hex").slice(0, 12);

const prevAttempt = step.attemptHistory[step.attemptHistory.length - 1];
const isPingPong = Boolean(prevAttempt && prevAttempt.errorHash === errorHash);

step.attemptHistory.push({
  attempt: parseInt(attemptStr, 10),
  timestamp: new Date().toISOString(),
  reason,
  errorHash,
  errorTail: (errorTail || "").slice(-1500)
});
step.lastErrorHash = errorHash;
step.pingPongDetected = isPingPong;
step.lastUpdatedAt = new Date().toISOString();
plan.updatedAt = new Date().toISOString();
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");

if (isPingPong) {
  process.stdout.write("PING_PONG_DETECTED");
}
NODE_EOF
}

update_step_state() {
  local step_id="$1"
  local new_status="$2"
  local inc_attempt="${3:-false}"
  local inc_continuation="${4:-false}"
  node - "$PLAN_FILE" "$step_id" "$new_status" "$inc_attempt" "$inc_continuation" <<'NODE_EOF'
const fs = require("node:fs");
const [planFile, stepId, newStatus, incAttempt, incCont] = process.argv.slice(2);
const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
for (const s of plan.steps) {
  if (s.id === stepId) {
    s.status = newStatus;
    if (incAttempt === "true") {
      s.attempts = (s.attempts || 0) + 1;
    }
    if (incCont === "true") {
      s.continuationsUsed = (s.continuationsUsed || 0) + 1;
      s.attempts = 0; // Reset retry counter for the fresh continuation session
      s.attemptHistory = [];
    }
    s.lastUpdatedAt = new Date().toISOString();
    break;
  }
}
plan.updatedAt = new Date().toISOString();
fs.writeFileSync(planFile, JSON.stringify(plan, null, 2) + "\n", "utf8");
NODE_EOF
}

echo "================================================================================"
echo "🚀 mstack Sequential Sub-Step Non-Interactive CLI Automation (v2)"
echo "   Plan File         : $PLAN_FILE"
echo "   Granularity       : 1 Sub-Step per 1 Session (+ Dynamic Handoff)"
echo "   CLI Runner        : ${CUSTOM_CLI_CMD:-$CLI_PRESET}"
echo "   Max Retries/Step  : $MAX_RETRIES"
echo "   Max Continuations : $MAX_CONTINUATIONS per sub-step"
echo "================================================================================"

# Record foreground PID and ensure dashboard server is alive
echo "$$" > .mstack/automation.pid
trap 'rm -f .mstack/automation.pid' EXIT

if ! pgrep -f "dashboard-server.js" >/dev/null 2>&1; then
  nohup node "$SCRIPT_DIR/dashboard-server.js" </dev/null >>.mstack/logs/dashboard-server.log 2>&1 &
  disown 2>/dev/null || true
  sleep 0.5
fi
node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true

SESSIONS_COMPLETED_THIS_RUN=0

while true; do
  if [[ "$MAX_STEPS" -gt 0 && "$SESSIONS_COMPLETED_THIS_RUN" -ge "$MAX_STEPS" ]]; then
    echo "[mstack automate] Reached --max-steps ($MAX_STEPS). Stopping loop."
    break
  fi

  NEXT_JSON="$(get_next_pending_step_json)"
  if [[ -z "$NEXT_JSON" ]]; then
    echo "✅ [mstack automate] All sub-steps in $PLAN_FILE are COMPLETED!"
    break
  fi

  STEP_ID=$(node -e 'console.log(JSON.parse(process.argv[1]).id)' "$NEXT_JSON")
  FEATURE=$(node -e 'console.log(JSON.parse(process.argv[1]).feature)' "$NEXT_JSON")
  SUBSTEP_CODE=$(node -e 'console.log(JSON.parse(process.argv[1]).substepCode || JSON.parse(process.argv[1]).phase)' "$NEXT_JSON")
  SKILL=$(node -e 'console.log(JSON.parse(process.argv[1]).skill || "")' "$NEXT_JSON")
  PRINCIPLES=$(node -e 'console.log(JSON.parse(process.argv[1]).principles || "principle-always-compile")' "$NEXT_JSON")
  TITLE=$(node -e 'console.log(JSON.parse(process.argv[1]).title || "")' "$NEXT_JSON")
  STEP_COMPILE_CMD=$(node -e 'console.log(JSON.parse(process.argv[1]).compileCmd || "")' "$NEXT_JSON")
  CONT_USED=$(node -e 'console.log(JSON.parse(process.argv[1]).continuationsUsed || 0)' "$NEXT_JSON")
  HANDOFF_COUNT_BEFORE=$(node -e 'console.log((JSON.parse(process.argv[1]).handoffHistory || []).length)' "$NEXT_JSON")

  echo ""
  echo "--------------------------------------------------------------------------------"
  echo "▶ Spawning Session for Sub-Step: $STEP_ID [$SUBSTEP_CODE] ($TITLE)"
  echo "  Skill         : $SKILL"
  echo "  Principles    : $PRINCIPLES"
  echo "  Continuations : $CONT_USED / $MAX_CONTINUATIONS"
  echo "--------------------------------------------------------------------------------"

  SESSION_SUCCEEDED=false
  FINAL_SESSION_OUTCOME="DONE"

  for (( ATTEMPT=1; ATTEMPT<=MAX_RETRIES; ATTEMPT++ )); do
    update_step_state "$STEP_ID" "IN_PROGRESS" "true" "false"
    node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
    TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
    PROMPT_FILE=".mstack/prompts/prompt_${STEP_ID}_cont${CONT_USED}_attempt${ATTEMPT}.md"
    AGENT_LOG=".mstack/logs/agent_${STEP_ID}_cont${CONT_USED}_attempt${ATTEMPT}_${TIMESTAMP}.log"

    build_substep_prompt "$STEP_ID" "$ATTEMPT" "$PROMPT_FILE"

    PRE_GIT_FINGERPRINT="$(get_git_tree_fingerprint)"

    echo "  [Attempt $ATTEMPT/$MAX_RETRIES] Invoking fresh non-interactive CLI session (log: $AGENT_LOG)..."
    set +e
    run_cli_with_prompt "$PROMPT_FILE" "$AGENT_LOG"
    CLI_EXIT=$?
    set -e

    if [[ "$DRY_RUN" == "true" ]]; then
      SESSION_SUCCEEDED=true
      FINAL_SESSION_OUTCOME="DONE"
      break
    fi

    POST_GIT_FINGERPRINT="$(get_git_tree_fingerprint)"

    # Inspect whether the agent updated handoff-substep.sh during this session
    HANDOFF_CHECK_JSON=$(node -e '
      const fs = require("node:fs");
      const plan = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const s = plan.steps.find(x => x.id === process.argv[2]);
      const histLen = (s && s.handoffHistory) ? s.handoffHistory.length : 0;
      const status = (s && s.lastHandoff && s.lastHandoff.reportedStatus) ? s.lastHandoff.reportedStatus : "DONE";
      const locksCount = (plan.goldenLocks || []).filter(g => g.lockedByStep === process.argv[2]).length;
      console.log(JSON.stringify({ histLen, status, locksCount, requiresGoldenLock: Boolean(s && s.requiresGoldenLock) }));
    ' "$PLAN_FILE" "$STEP_ID")

    HANDOFF_COUNT_AFTER=$(node -e 'console.log(JSON.parse(process.argv[1]).histLen)' "$HANDOFF_CHECK_JSON")
    REPORTED_HANDOFF_STATUS=$(node -e 'console.log(JSON.parse(process.argv[1]).status)' "$HANDOFF_CHECK_JSON")
    REQUIRES_GOLDEN_LOCK=$(node -e 'console.log(JSON.parse(process.argv[1]).requiresGoldenLock)' "$HANDOFF_CHECK_JSON")
    GOLDEN_LOCKS_BY_STEP=$(node -e 'console.log(JSON.parse(process.argv[1]).locksCount)' "$HANDOFF_CHECK_JSON")

    # Anti-Slop Check 1: Did the agent exit without changing any files AND without recording a handoff?
    if [[ "$ALLOW_NOOP" != "true" && "$PRE_GIT_FINGERPRINT" == "$POST_GIT_FINGERPRINT" && "$HANDOFF_COUNT_AFTER" -le "$HANDOFF_COUNT_BEFORE" ]]; then
      echo "  ✖ [SLOP_GUARD] Attempt $ATTEMPT made zero file changes and recorded no handoff." >&2
      PING_PONG=$(record_attempt_failure "$STEP_ID" "$ATTEMPT" "SLOP_NO_OP: Session exited without modifying any files or calling handoff-substep.sh" "You exited without making code/test changes or running handoff-substep.sh.")
      if [[ "$PING_PONG" == "PING_PONG_DETECTED" ]]; then
        echo "  🛑 [CIRCUIT_BREAKER] Identical no-op failure repeated on consecutive attempts. Halting." >&2
        break
      fi
      continue
    fi

    # Anti-Slop Check 2: If this sub-step requires locking Golden Master baselines (1.1, 2.1) and reported DONE, verify golden lock exists
    if [[ "$REQUIRES_GOLDEN_LOCK" == "true" && "$REPORTED_HANDOFF_STATUS" == "DONE" && "$GOLDEN_LOCKS_BY_STEP" -eq 0 ]]; then
      echo "  ✖ [SLOP_GUARD] Sub-Step '$STEP_ID' requires locking Golden Master baseline files via --lock-golden in handoff-substep.sh, but 0 golden files were locked." >&2
      PING_PONG=$(record_attempt_failure "$STEP_ID" "$ATTEMPT" "SLOP_MISSING_GOLDEN_LOCK" "Sub-step $STEP_ID requires recording and locking Golden Master files via: ./mobile-migration-tools/scripts/handoff-substep.sh --step-id \"$STEP_ID\" --status DONE --summary \"...\" --files \"...\" --lock-golden \"<golden-file-path>\"")
      if [[ "$PING_PONG" == "PING_PONG_DETECTED" ]]; then
        echo "  🛑 [CIRCUIT_BREAKER] Missing golden lock repeated on consecutive attempts. Halting." >&2
        break
      fi
      continue
    fi

    # Anti-Slop Check 3: Run mandatory outer compile-gate.sh (includes Golden SHA-256 verification & boundary checks)
    echo "  [Attempt $ATTEMPT/$MAX_RETRIES] Running mandatory outer compile-gate.sh verification..."
    set +e
    "$COMPILE_GATE" "$STEP_ID" "$PRINCIPLES" "Automated verification gate for $STEP_ID (cont $CONT_USED, attempt $ATTEMPT)" "$STEP_COMPILE_CMD"
    GATE_EXIT=$?
    set -e

    if [[ $CLI_EXIT -eq 0 && $GATE_EXIT -eq 0 ]]; then
      # If the agent forgot to call handoff-substep.sh but changed files and passed compile-gate, auto-record a verified git-diff handoff
      if [[ "$HANDOFF_COUNT_AFTER" -le "$HANDOFF_COUNT_BEFORE" ]]; then
        CHANGED_FILES_CSV=$(git diff --name-only 2>/dev/null | paste -sd "," - || true)
        "$HANDOFF_SCRIPT" \
          --plan "$PLAN_FILE" \
          --step-id "$STEP_ID" \
          --status "DONE" \
          --summary "Completed $STEP_ID and passed compile-gate.sh" \
          ${CHANGED_FILES_CSV:+--files "$CHANGED_FILES_CSV"} >/dev/null 2>&1 || true
        REPORTED_HANDOFF_STATUS="DONE"
      fi

      echo "  ✔ Session for '$STEP_ID' PASSED verification on attempt $ATTEMPT (Handoff Status: $REPORTED_HANDOFF_STATUS)!"
      SESSION_SUCCEEDED=true
      FINAL_SESSION_OUTCOME="$REPORTED_HANDOFF_STATUS"
      break
    else
      echo "  ✖ Sub-step '$STEP_ID' failed on attempt $ATTEMPT (CLI exit: $CLI_EXIT, Gate exit: $GATE_EXIT)." >&2
      LATEST_COMPILE_LOG=$(ls -t .mstack/logs/compile_${STEP_ID}_*.log 2>/dev/null | head -n 1 || true)
      ERR_TAIL=""
      if [[ -n "$LATEST_COMPILE_LOG" && -f "$LATEST_COMPILE_LOG" ]]; then
        ERR_TAIL="$(tail -n 60 "$LATEST_COMPILE_LOG")"
      elif [[ -f "$AGENT_LOG" ]]; then
        ERR_TAIL="$(tail -n 60 "$AGENT_LOG")"
      fi
      PING_PONG=$(record_attempt_failure "$STEP_ID" "$ATTEMPT" "GATE_FAILED (CLI=$CLI_EXIT, Gate=$GATE_EXIT)" "$ERR_TAIL")
      if [[ "$PING_PONG" == "PING_PONG_DETECTED" ]]; then
        echo "  🛑 [CIRCUIT_BREAKER] Identical compiler/test error repeated across consecutive attempts. Stopping ping-pong loop." >&2
        break
      fi
    fi
  done

  if [[ "$SESSION_SUCCEEDED" == "true" ]]; then
    if [[ "$FINAL_SESSION_OUTCOME" == "NEEDS_MORE_WORK" ]]; then
      NEXT_CONT=$((CONT_USED + 1))
      if [[ "$NEXT_CONT" -gt "$MAX_CONTINUATIONS" ]]; then
        update_step_state "$STEP_ID" "FAILED" "false" "false"
        node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
        "$LOG_EVIDENCE" "$STEP_ID" "$PRINCIPLES" "Exceeded max continuations ($MAX_CONTINUATIONS) for $STEP_ID (Slop Loop Prevention)" "${CUSTOM_CLI_CMD:-$CLI_PRESET}" "$PLAN_FILE" "SLOP_MAX_CONTINUATIONS"
        echo "❌ [SLOP_GUARD] Sub-Step '$STEP_ID' requested NEEDS_MORE_WORK more than --max-continuations ($MAX_CONTINUATIONS) times. Halting to prevent infinite handoff loop." >&2
        print_status
        exit 1
      fi
      update_step_state "$STEP_ID" "NEEDS_MORE_WORK" "false" "true"
      node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
      "$LOG_EVIDENCE" "$STEP_ID" "$PRINCIPLES" "Partial sub-step compiled & verified; handed off remaining work to continuation session $NEXT_CONT/$MAX_CONTINUATIONS" "${CUSTOM_CLI_CMD:-$CLI_PRESET}" "$PLAN_FILE" "SUBSTEP_HANDOFF_CONTINUE"
      echo "  🔄 Handoff recorded for '$STEP_ID' (NEEDS_MORE_WORK). Spawning next fresh session ($NEXT_CONT/$MAX_CONTINUATIONS) for remaining items..."
      SESSIONS_COMPLETED_THIS_RUN=$((SESSIONS_COMPLETED_THIS_RUN + 1))
    else
      update_step_state "$STEP_ID" "COMPLETED" "false" "false"
      node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
      "$LOG_EVIDENCE" "$STEP_ID" "$PRINCIPLES" "Completed sub-step $STEP_ID for $FEATURE" "${CUSTOM_CLI_CMD:-$CLI_PRESET}" "$PLAN_FILE" "SUBSTEP_COMPLETED"
      SESSIONS_COMPLETED_THIS_RUN=$((SESSIONS_COMPLETED_THIS_RUN + 1))
    fi
  else
    update_step_state "$STEP_ID" "FAILED" "false" "false"
    node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
    "$LOG_EVIDENCE" "$STEP_ID" "$PRINCIPLES" "Failed sub-step $STEP_ID after $MAX_RETRIES attempts" "${CUSTOM_CLI_CMD:-$CLI_PRESET}" "$PLAN_FILE" "SUBSTEP_FAILED"
    echo "❌ [mstack automate] Sub-Step '$STEP_ID' failed verification. Stopping loop to preserve Always-Compile discipline." >&2
    print_status
    exit 1
  fi
done

node "$SCRIPT_DIR/generate-dashboard.js" "$PLAN_FILE" >/dev/null 2>&1 || true
print_status

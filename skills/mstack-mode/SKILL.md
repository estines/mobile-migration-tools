---
name: mstack-mode
description: >-
  Front-door orchestrator for mobile-migration-tools (modeled after poteto/pstack). Activate this skill for any mobile migration, modernization, parallel greenfield feature, or parity verification task. Enforces interactive stack setup, playbook todo routing, principle citation, and Always-Compile gates.
---

# `mstack-mode` — Mobile Migration Orchestrator

Inspired by `poteto/pstack`, `mstack-mode` is the front-door router that ensures every mobile migration or parallel feature task executes with **zero guesswork, 100% parity proof, and compilation at every atomic step**.

```mermaid
flowchart TD
    Entry["Task Received in mstack-mode"] --> CheckProfile{".mstack/target-profile.json\nexists?"}
    CheckProfile -- "No (or user wants change)" --> Setup["Run Skill: mstack-setup\n1. Run detect-project.sh\n2. Ask user via ask_question\n3. Save .mstack/target-profile.json"]
    CheckProfile -- "Yes" --> Classify["Classify Task & Load Playbook"]
    Setup --> Classify

    Classify -->|"Migrate Legacy Feature (Interactive or Continuous)"| P_Mig["4-Step Decoupled Migration:\n1. mstack-step1-logic-storage\n2. mstack-step2-ui-parity\n3. mstack-step3-navigation-adaptive\n4. mstack-step4-greenfield-cutover"]
    Classify -->|"Long-Running / Non-Interactive CLI Automation"| P_Auto["Run Skill: mstack-automation\n(automate-plan.sh + .mstack/migration-plan.json\nZero human prompts until all steps COMPLETED)"]
    Classify -->|"Build New Parallel Feature"| P_New["Run Skill: mstack-step4-greenfield-cutover\n(Greenfield on Target Stack + Synced Bridge)"]
    Classify -->|"Audit / Verify Parity"| P_Ver["Run All 4 Verification Gates\n& Audit .mstack/audit.tsv"]
```

---

## Mandatory Execution Protocol

### 1. Check Target Profile First (`mstack-setup` vs. `mstack-automation`)
- Check if `.mstack/target-profile.json` exists in the workspace root.
- **Interactive Mode (default)**: If `.mstack/target-profile.json` is missing, execute [`mstack-setup`](../mstack-setup/SKILL.md) to detect the current project and ask the user to select their target architecture and stack via `ask_question`.
- **Non-Interactive / Automation Mode**: If the user requested unattended/automation mode (or passed `--cli` / `mstack-automation`), **never pause to ask questions**. Use [`mstack-automation`](../mstack-automation/SKILL.md) and `./mobile-migration-tools/scripts/automate-plan.sh` to auto-initialize `.mstack/target-profile.json` and `.mstack/migration-plan.json`, and execute all queued steps continuously without stopping after 1 step.

### 2. Copy Playbook Steps into Your Active Checklist (And Never Stop After 1 Step in Automation Mode)
Never improvise a migration sequence. Match the user's request to the exact playbook below:

- **Migrating an Existing Feature / Screen (End-to-End or Phased)**:
  1. **Step 1 (`mstack-step1-logic-storage`)**: Extract business logic & storage using Golden Master Approval Tests + Scientist Dual-Execution + Synced Storage Proxy (UI & Navigation untouched). **Run `compile-gate.sh`**.
  2. **Step 2 (`mstack-step2-ui-parity`)**: Capture Legacy View Golden PNG, build declarative UI with Bridge Theme, pass `<= 0.1%` pixel diff, and swap inside existing navigation host (`ComposeView` / `UIHostingController`). **Run `compile-gate.sh`**.
  3. **Step 3 (`mstack-step3-navigation-adaptive`)**: Upgrade internal routing to the target navigation stack (e.g., Navigation 3 + Adaptive Foldable Scenes), pass JVM/unit backstack state-machine tests, configuration recreate tests, and E2E Maestro tests. **Run `compile-gate.sh`**.
  4. **Step 4 (`mstack-step4-greenfield-cutover`)**: Only after user approval and 0% Scientist/Visual/Nav diffs, decommission dead legacy files in a dedicated cleanup step. **Run `compile-gate.sh`**.

- **Building a New Feature During Ongoing Migration**:
  - Execute [`mstack-step4-greenfield-cutover`](../mstack-step4-greenfield-cutover/SKILL.md) (Greenfield Track) to scaffold in the target multi-module architecture and connect to legacy callers via a single bridge hook and synced storage proxy.

### 3. Enforce the Four Principles at Every Step
At the end of every phase or response, state explicitly:
1. **Which `mstack` principles were applied** (`principle-always-compile`, `principle-scientist-parity`, `principle-visual-golden-master`, `principle-decouple-ui-and-nav`).
2. **Which compile & test gates were executed** via `./mobile-migration-tools/scripts/compile-gate.sh` and their exact exit status / test counts.
3. **What was NOT verified** (e.g., if physical foldable device hardware was unavailable and verified via JVM Roborazzi / Robolectric instead).

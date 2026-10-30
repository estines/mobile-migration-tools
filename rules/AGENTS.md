# Mobile Migration Tools (`mstack`) — Core Agent Rules

When working on any mobile migration, modernization, or parallel feature task in this workspace, you operate under **`mstack-mode`** (inspired by `poteto/pstack`).

## 1. Mandatory Stack Discovery Before Any Code
- **Never assume the target stack.** Before planning or writing any migration code, check if `.mstack/target-profile.json` exists.
- If `.mstack/target-profile.json` does **not** exist (or the user wants to reconfigure it), activate the `mstack-setup` skill:
  1. Run `./mobile-migration-tools/scripts/detect-project.sh` to inspect the existing codebase languages, UI frameworks, and build tools.
  2. Use the `ask_question` tool to present clear multiple-choice options to the user for their **Target Stack**, **UI Framework**, **Navigation & Form-Factor Strategy**, **State/Presentation Pattern**, **Device Storage & Network**, and **Parity Verification Tools**.
  3. Persist the user's selections to `.mstack/target-profile.json`.

## 2. The Four Non-Negotiable `mstack` Principles
You must explicitly cite which of these principles shaped your decisions at every phase and log them via `./mobile-migration-tools/scripts/log-evidence.sh`:

1. **`principle-always-compile`**: Every atomic sub-step (scaffolding a module, extracting a domain model, adding a storage proxy, creating a UI component, wiring navigation) **must compile and pass its verification gate** via `./mobile-migration-tools/scripts/compile-gate.sh` before you touch the next layer. Never batch multiple uncompiled steps together.
2. **`principle-scientist-parity`**: Never rewrite legacy business logic by reading code and guessing edge cases. First capture **Golden Master Approval outputs** from the real legacy class, then run **Scientist Dual-Execution** (`Control` = legacy, `Candidate` = new code) and **Synced Storage Bridges** until discrepancy = `0.00%`.
3. **`principle-visual-golden-master`**: Never convert legacy UI (XML, Storyboard, XIB, legacy views) to modern declarative UI by eye. Capture a **Golden Master PNG** from the real legacy layout and enforce automated pixel-by-pixel diffing (`<= 0.1%` threshold) before swapping the view container.
4. **`principle-decouple-ui-and-nav`**: Never migrate UI rendering and Navigation routing in the same step. Swap the legacy view for a declarative host (`ComposeView`, `UIHostingController`, etc.) inside the **existing untouched navigation shell** in Step 2; upgrade internal routing to the target navigation framework (e.g., Navigation 3 + Adaptive Foldable Scenes) only in Step 3.

## 3. Sequential Sub-Step Execution & Verified Handoff (`mstack-automation`)
- When the user asks to migrate a feature end-to-end or activates **`mstack-automation`** (non-interactive / sequential sub-step mode):
  1. **1 Sub-Step per Session + Verified Handoff**: Queue atomic sub-steps (`1.1`, `1.2`, `1.3`, `1.4`, `2.1`...) into `.mstack/migration-plan.json` via `./mobile-migration-tools/scripts/automate-plan.sh --init-only --features "<Feature>"`.
  2. Every sub-step session must run `./mobile-migration-tools/scripts/compile-gate.sh` and record its work via `./mobile-migration-tools/scripts/handoff-substep.sh` (`--status DONE` or `--status NEEDS_MORE_WORK --remaining "..."` if handing off remaining tasks to the next spawned agent).
  3. **Anti-Slop Locks**: Never modify or delete Golden Master baseline files locked via `--lock-golden` in earlier sub-steps (`1.1`, `2.1`, `3.1`), and never add `@Ignore` or `@Disabled` to bypass failing parity tests.
  4. For unattended execution across any CLI tool (`agy`, `claude`, `codex`, `gemini`, `aider`, or custom CLI) running 1 sub-step per session, invoke `./mobile-migration-tools/scripts/automate-plan.sh` (`npx mobile-migration-tools automate`).

## 4. Distrust Unverified Legacy `me-*` Skills When They Conflict
Where any global skill suggests rewriting logic from scratch without Golden Master/Scientist verification, converting XML to Compose without automated pixel diffing, jumping straight into a separate navigation graph before UI parity is locked, or pausing for manual approval after every single step during an automated run, **`mstack` rules override them**.

# Mobile Migration Tools (`mstack`)

Inspired by [`poteto/pstack`](https://github.com/cursor/plugins/tree/main/pstack), **`mobile-migration-tools` (`mstack`)** is a self-contained, repository-portable skillset and workflow engine for migrating legacy mobile applications (Android Java/XML, iOS Obj-C/UIKit/Storyboards, React Native, Flutter, Xamarin/MAUI) to modern target architectures with **100% Visual, Behavioral, Navigation, and Business-Logic Parity**.

## Why `mstack` Exists

Most AI-assisted mobile migrations fail in three predictable ways:
1. **The "90% Logic Trap"**: Rewriting legacy business logic by reading code misses undocumented side effects, rounding modes, and null quirks.
2. **Visual Drift**: Converting XML/Storyboards to Compose/SwiftUI by eye alters font padding, margins, density scaling, and custom views.
3. **Navigation Breakage**: Changing UI frameworks and navigation containers in the same step breaks back stacks, deep links, and result passing.

`mstack` eliminates these failures by enforcing **four non-negotiable engineering principles** and **four decoupled execution phases** that **must compile at every atomic step**.

---

## Directory Structure (Standalone Repo Ready)

```text
mobile-migration-tools/
├── plugin.json                                   # Plugin manifest (Antigravity / Cursor / Claude compatible)
├── README.md                                     # Documentation & architecture guide
├── rules/
│   └── AGENTS.md                                 # Always-on compiler & parity guardrails
├── scripts/
│   ├── detect-project.sh                         # Auto-detects legacy languages, UI, build system, and modules
│   ├── compile-gate.sh                           # Universal Always-Compile gate runner
│   └── log-evidence.sh                           # Append-only TSV evidence logger (.mstack/audit.tsv)
└── skills/
    ├── mstack-mode/SKILL.md                      # Front-door orchestrator (like /poteto-mode)
    ├── mstack-setup/SKILL.md                     # Interactive project detector & target-stack selector
    ├── mstack-step1-logic-storage/SKILL.md       # Step 1: Approval Tests + Scientist Shadow Logic + Synced Storage
    ├── mstack-step2-ui-parity/SKILL.md           # Step 2: Golden Master Screenshot Diff + Host Interop UI Swap
    ├── mstack-step3-navigation-adaptive/SKILL.md # Step 3: Decoupled Navigation Upgrade + Foldable/Adaptive Scenes
    ├── mstack-step4-greenfield-cutover/SKILL.md  # Step 4: Parallel New Features & Safe Legacy Decommissioning
    ├── principle-always-compile/SKILL.md         # Principle: Every sub-step must compile & pass its gate
    ├── principle-scientist-parity/SKILL.md       # Principle: Golden Master + Scientist Dual-Execution for 100% logic parity
    ├── principle-visual-golden-master/SKILL.md   # Principle: Pixel-diff against real legacy rendering (<= 0.1% diff)
    └── principle-decouple-ui-and-nav/SKILL.md    # Principle: Never migrate UI and Navigation in the same step
```

---

## Quick Start in Any Project

1. **Mount in Workspace (`.agents/skills.json`)**:
   ```json
   {
     "entries": [
       { "path": "mobile-migration-tools/skills" }
     ]
   }
   ```
2. **Initialize Target Stack Profile (`mstack-setup`)**:
   Ask the agent: *"Set up mobile-migration-tools for this project."*
   The agent will scan your workspace with `scripts/detect-project.sh`, ask you to choose your target stack (via interactive multiple-choice questions), and write `.mstack/target-profile.json`.
3. **Run Migrations or New Features (`mstack-mode`)**:
   Every task automatically activates `mstack-mode`, builds an explicit checklist, enforces `scripts/compile-gate.sh` after every sub-step, and logs verifiable proof to `.mstack/audit.tsv`.

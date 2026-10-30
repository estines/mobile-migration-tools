---
name: mstack-setup
description: >-
  Project-agnostic discovery and interactive target-stack configuration skill. Runs detect-project.sh to inspect the current mobile codebase (Android, iOS, KMP, Flutter, React Native) and always asks the user via ask_question to select their target architecture, UI, navigation, storage, and parity tools before saving .mstack/target-profile.json.
---

# `mstack-setup` — Interactive Project Detector & Stack Selector

`mobile-migration-tools` works across **any mobile project and language**. Never hardcode or assume the target stack—always detect the baseline project first and ask the user to choose their target architecture.

---

## Step 1: Detect the Current Workspace Baseline

Run the project detector script:

```bash
./mobile-migration-tools/scripts/detect-project.sh
```

Inspect the output (and build configuration files such as `settings.gradle.kts`, `gradle/libs.versions.toml`, `Podfile`, `Package.swift`, `pubspec.yaml`, or `package.json`) to understand:
1. **Current Legacy Stack**: Languages (Java, Kotlin, Objective-C, Swift, Dart, TS/JS), UI toolkit (Android XML, UIKit Storyboards/XIBs, legacy RN/Flutter), navigation, DI, and persistence.
2. **Existing Partial Target Stack**: Any multi-module structure or modern libraries already present in the repository.

---

## Step 2: Ask the User for Target Stack Choices (`ask_question`)

**Mandatory Rule:** Even if you see hints in the repo, you **must** use the `ask_question` tool to let the user confirm or select their target stack across these dimensions (adapt the recommended option `(Recommended)` to match what fits their project best):

1. **Target Platform & Module Strategy**:
   - e.g., `(Recommended) Kotlin Multiplatform (KMP) + Compose Multiplatform (:api + :impl multi-module)`
   - `Native Android Multi-Module (Jetpack Compose + Kotlin :api + :impl)`
   - `Native iOS Modular (SwiftUI + Swift Package Manager feature modules)`
   - `Flutter / React Native Modular Architecture`
2. **UI & Presentation Pattern**:
   - e.g., `(Recommended) Unidirectional MVI (Sealed UiState + Event + Effect + Stateless UI)`
   - `MVVM with StateFlow / Combine / Observable`
   - `Circuit / Decompose / TCA (The Composable Architecture)`
3. **Navigation & Form-Factor (Foldable/Tablet) Strategy**:
   - e.g., `(Recommended) Navigation 3 (NavKey + NavDisplay) + Material 3 Adaptive SceneStrategy for Foldables`
   - `Navigation Compose (Type-Safe Routes) + Adaptive Scaffolds`
   - `Decompose / Voyager (KMP Router)`
   - `SwiftUI NavigationStack + NavigationSplitView`
4. **Modern Device Storage & Network Stack**:
   - e.g., `(Recommended) Room KMP + DataStore (with Legacy SharedPreferences Sync Proxy) + Ktor`
   - `SQLDelight + Multiplatform-Settings + Ktor`
   - `SwiftData / CoreData + Keychain + URLSession`
5. **Visual & Logic Parity Gate Tooling**:
   - e.g., `(Recommended) Roborazzi (JVM XML-vs-Compose Pixel Diff) + Scientist Dual-Run + Maestro E2E`
   - `Paparazzi + Golden Master Approval Tests + Maestro E2E`
   - `Compose Preview Screenshot Testing + JUnit/Turbine + Espresso/UIAutomator`

---

## Step 3: Persist `.mstack/target-profile.json`

Once the user answers, create `.mstack/target-profile.json` in the workspace root recording their exact choices and the project's fast compile command:

```json
{
  "projectType": "<detected-project-type>",
  "legacyBaseline": {
    "languages": ["Java", "Kotlin"],
    "ui": "Android XML Views",
    "navigation": "Activities / Fragments / XML NavGraph",
    "storage": "SharedPreferences / Legacy SQLite / Room",
    "network": "Retrofit / Gson"
  },
  "targetStack": {
    "platform": "Compose Multiplatform (KMP)",
    "moduleStructure": ":features:<name>:api (Pure KMP) + :features:<name>:impl",
    "ui": "Compose Multiplatform (Stateless + Stateful split)",
    "presentation": "MVI (sealed UiState, Event, Channel Effect)",
    "navigation": "Navigation 3 (NavKey, NavDisplay) + Material 3 Adaptive SceneStrategy (Foldables)",
    "di": "Koin",
    "storage": "Room KMP + DataStore (via Synced StorageBridge)",
    "network": "Ktor + kotlinx.serialization",
    "eliminateLanguages": ["Java", "XML"]
  },
  "verification": {
    "compileGateCommand": "./gradlew :app:compileModeUatDebugKotlin",
    "moduleCompileTemplate": "./gradlew :features:<feature>:api:build :features:<feature>:impl:build",
    "visualParityTool": "Roborazzi (JVM XML-to-Compose Pixel Diff <= 0.1%)",
    "logicParityTool": "Golden Master Approval Tests + Scientist Shadow Runner",
    "e2eParityTool": "Maestro"
  }
}
```

Log the setup completion:
```bash
./mobile-migration-tools/scripts/log-evidence.sh "setup" "principle-always-compile" "Target stack profile configured by user" "mstack-setup" ".mstack/target-profile.json" "READY"
```

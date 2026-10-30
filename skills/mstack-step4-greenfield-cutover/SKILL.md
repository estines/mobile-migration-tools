---
name: mstack-step4-greenfield-cutover
description: >-
  Step 4 of the mstack workflow: Build brand-new parallel features directly on the target stack (:api + :impl, CMP, Nav3, Room/Ktor) with minimal bridge impact on legacy code, and safely decommission retired legacy Java/XML files after all parity gates pass.
---

# `mstack-step4-greenfield-cutover` — Parallel New Features & Safe Legacy Cutover

**Required Principles:** [`principle-always-compile`](../principle-always-compile/SKILL.md), [`principle-scientist-parity`](../principle-scientist-parity/SKILL.md), [`principle-decouple-ui-and-nav`](../principle-decouple-ui-and-nav/SKILL.md)

This skill governs two tracks:
- **Track A (Parallel Greenfield Features):** Building brand-new product features while the migration is ongoing, with near-zero impact on legacy code.
- **Track B (Legacy Decommissioning & Cutover):** Safely deleting legacy Java, XML, and Activity shells once a migrated feature has passed Steps 1–3.

---

## Track A: Building New Features During Migration (Zero Legacy Debt)

Never build new features inside legacy Activities, XML layouts, or Java classes. All new features are built 100% on the target stack configured in `.mstack/target-profile.json`:

1. **Step A1 — Contract & Module Scaffold (`compile-gate.sh`)**:
   - Create `:features:<new_feature>:api` (pure KMP: `NavKey` routes, domain models, inbound/outbound bridge contracts) and `:features:<new_feature>:impl`.
   - Register in `settings.gradle.kts` and verify compilation immediately.
2. **Step A2 — Domain & Data Layer with Synced Storage (`compile-gate.sh`)**:
   - Build pure domain UseCases, value classes, Ktor `@Serializable` DTOs, fail-closed mappers, and Room KMP persistence.
   - If the new feature reads shared auth/session/user state from the legacy app, read it through the `:core:data` **Synced Storage Proxy**—never duplicate or mutate legacy singletons directly.
   - Write `commonTest` unit tests (`MockEngine`, `Turbine`, fakes) and run `compile-gate.sh`.
3. **Step A3 — Stateless Declarative UI + MVI + Foldable Previews (`compile-gate.sh`)**:
   - Build `<Screen>UiState` (`sealed interface`), `<Screen>Event`, `<Screen>Effect`, `<Screen>ViewModel`, and `<Screen>Content`.
   - Add multi-form-factor previews (`Phone`, `Foldable`, `Tablet`) and Roborazzi snapshot tests.
   - Run `compile-gate.sh`.
4. **Step A4 — Navigation 3 + Single Bridge Hook into Legacy (`compile-gate.sh`)**:
   - Wire `NavDisplay` + `rememberListDetailSceneStrategy()` / `rememberSupportingPaneSceneStrategy()`.
   - Connect the new feature to the existing legacy app via **at most one bridge hook** in `:app`.
   - Run `compile-gate.sh` and Maestro E2E verification.

---

## Track B: Safe Legacy Decommissioning (Zero Java & Zero XML Cutover)

Legacy files (`*.java`, `res/layout/*.xml`, legacy `Activity`/`Fragment` classes) are **never deleted during Steps 1–3**. Decommissioning happens only in Track B when all preconditions are met:

### Preconditions Checklist (Must All Be `PASS` in `.mstack/audit.tsv`)
- [ ] **Step 1 Gate Passed**: 100% Golden Master Approval tests + `0.00%` Scientist shadow mismatches.
- [ ] **Step 2 Gate Passed**: `<= 0.1%` Roborazzi visual pixel diff across all screen states and locales (EN/TH).
- [ ] **Step 3 Gate Passed**: Navigation 3 backstack unit tests + Foldable recreation test + identical Maestro E2E flow passing.
- [ ] **Explicit User Approval**: User has confirmed readiness to retire the legacy code for this feature.

### Decommissioning Sequence
1. Remove the `Scientist` shadow wrapper and legacy `Control` branch so the target KMP/CMP path is the sole execution path.
2. Delete the unused legacy `res/layout/*.xml` files, legacy `Activity`/`Fragment` classes, and legacy `*.java` classes for that feature.
3. Run the repo-wide compile and test gate:
   ```bash
   ./mobile-migration-tools/scripts/compile-gate.sh "step4-decommission" "principle-always-compile" "Removed retired legacy Java and XML files for feature"
   ```
4. Re-run `./mobile-migration-tools/scripts/detect-project.sh` to record the reduced `java` and `android_layout_xml` file counts in `.mstack/audit.tsv`.

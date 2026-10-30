---
name: principle-decouple-ui-and-nav
description: >-
  Prevents navigation regressions during mobile migrations by strictly separating UI replacement (Step 2) from Navigation & Adaptive/Foldable routing upgrades (Step 3).
---

# Principle: Decouple UI Migration from Navigation Migration

## Why This Principle Exists
Replacing legacy screens (XML/UIKit) with declarative screens (Compose/SwiftUI) **at the same time** as replacing the navigation container (Activities/Fragments/`UINavigationController` -> Navigation 3 / `NavigationStack`) breaks backstack flags (`CLEAR_TOP`, `SINGLE_TOP`), result passing (`startActivityForResult` / delegates), deep links, and transition animations.

## Mandatory Rules

1. **Step 2 is Strictly UI-Inside-Legacy-Host**:
   - When migrating a screen's UI from legacy views to declarative UI, keep the existing navigation host (`Activity`, `Fragment`, `UIViewController`) and all inbound/outbound routing calls **100% untouched**.
   - Replace only the view inflation (`setContentView` / `onCreateView` / `loadView`) with the declarative host container (`ComposeView` / `setContent` / `UIHostingController`).
   - Because the navigation host and its Intent/Bundle/result contracts are untouched, navigation is mathematically guaranteed not to break during UI migration.

2. **Step 3 Upgrades Navigation Only After the Flow's UI & Logic Are Locked**:
   - Only after all screens in a cohesive sub-flow are running in declarative UI (verified in Step 2) and backed by migrated logic (verified in Step 1), consolidate their internal routing into the target navigation framework (e.g., **Navigation 3** `NavDisplay` + `SnapshotStateList<NavKey>`, or SwiftUI `NavigationStack`).
   - Preserve the exact entry/exit contract at the boundary of the flow so unmigrated callers outside the flow see zero change.

3. **Explicit Backstack State-Machine Verification**:
   - Model every legacy navigation flag (`singleTop`, `clearTop`, pop-to-root, result delivery, system back, predictive back, deep link entry) as a deterministic unit test on the user-owned backstack before running E2E Maestro/UI tests.

4. **Adaptive / Foldable Support Without Breaking Phone Parity**:
   - Attach adaptive multi-pane strategies (e.g., Material 3 Adaptive `ListDetailSceneStrategy` / `SupportingPaneSceneStrategy` on Navigation 3, or `NavigationSplitView`) at the navigation display layer in Step 3.
   - Verify that compact/folded phone posture remains 100% identical to the legacy single-pane flow while unfolded/tablet postures automatically adapt into multi-pane scenes and survive configuration/posture changes (`recreate()`).

---
name: principle-visual-golden-master
description: >-
  Guarantees 100% visual and UI parity when migrating legacy mobile views (Android XML, iOS Storyboards/XIBs/UIKit, legacy RN/Flutter) to modern declarative UI (Compose, Compose Multiplatform, SwiftUI) via JVM/simulator Golden Master screenshot diffing and hybrid view interop.
---

# Principle: Visual Golden Master (Pixel-Exact UI Parity)

## Why This Principle Exists
Direct LLM translation from legacy layout files (Android XML, iOS Storyboards/XIBs) to declarative UI (Jetpack Compose / Compose Multiplatform / SwiftUI) introduces unacceptable visual drift: different font padding (`includeFontPadding`), density scaling quirks, ripple/touch target padding, shadow rendering, and custom View behaviors.

## Mandatory Rules

1. **Capture the Real Legacy View as a Golden PNG First**:
   - Before writing the replacement declarative UI, render the **actual legacy view** in an automated snapshot runner (e.g., **Roborazzi** / **Paparazzi** on Android/KMP, **swift-snapshot-testing** on iOS, **GoldenToolkit** on Flutter) across all supported locales (e.g., EN and TH) and states (`Loading`, `Content`, `Empty`, `Error`).
   - Save the rendered PNGs as the immutable **Golden Master baseline**.

2. **Bridge Theme & Rendering Quirk Alignment**:
   - Configure a Legacy-Compat Bridge Theme for migrated screens so framework defaults match legacy rendering:
     - **Android XML -> Compose**: Match `PlatformTextStyle(includeFontPadding = true)`, respect exact `R.dimen` pixel/dp/sp semantics (including non-scaling `dp` text via `LocalDensity` where legacy used `dp` for text size), and preserve legacy touch target bounds.
     - **iOS UIKit -> SwiftUI**: Match exact `UIFont` line spacing, safe-area inset behavior, and separator insets.

3. **Bottom-Up & Hybrid Interop (`AndroidView` / `UIViewRepresentable`)**:
   - If a screen contains a complex custom legacy widget (custom canvas chart, PDF viewer, specialized input), wrap it inside the declarative screen using native interop (`AndroidView` in Compose, `UIViewRepresentable` in SwiftUI) first to guarantee 100% visual parity on Day 1, then migrate that leaf widget separately with its own Golden PNG test.

4. **Automated Pixel-Diff Gate (`<= 0.1%` Tolerance)**:
   - Render the new declarative component under the exact same dimensions, density, locale, and state as the Golden Master PNG.
   - If the pixel diff exceeds `0.1%`, the step **fails**. Inspect the generated diff overlay image, fix the exact spacing/font/color discrepancy, and re-verify before proceeding.

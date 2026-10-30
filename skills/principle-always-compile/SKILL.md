---
name: principle-always-compile
description: >-
  Enforces pstack-style atomic compilation discipline across any mobile project (Gradle, Xcode, Flutter, React Native, KMP). Every single sub-step must compile and pass its gate via compile-gate.sh before moving to the next sub-step.
---

# Principle: Always Compile (Sequence Work into Verifiable Units)

Adapted from `poteto/pstack`'s *Prove It Works* and *Sequence Work into Verifiable Units*.

## Why This Principle Exists
In complex mobile migrations (multi-module KMP, Swift/Obj-C interop, React Native New Architecture, Flutter), batching 10 files across Data, Domain, UI, and Navigation before running the compiler creates cascading type, DI, and resource errors that cause agents to hallucinate workarounds or break legacy contracts.

## Mandatory Rules

1. **One Atomic Change -> One Compile Gate**:
   - After every atomic unit of work (e.g., adding a module, creating domain models, writing a repository, adding a Compose/SwiftUI screen, wiring a bridge), you **must** run:
     ```bash
     ./mobile-migration-tools/scripts/compile-gate.sh "<step-slug>" "principle-always-compile" "<what changed>" "<module-specific-compile-cmd>"
     ```
2. **Never Proceed on Red**:
   - If `compile-gate.sh` returns a non-zero exit code, **stop forward progress immediately**.
   - Fix the root cause of the compilation failure in the current atomic unit and re-run `compile-gate.sh` until it outputs `COMPILE_PASSED`.
3. **Public & Binary Contract Preservation**:
   - When touching shared models or boundaries called by legacy code (Java, Objective-C, legacy JS), keep binary-compatible annotations (`@JvmStatic`, `@JvmOverloads`, `@objc`, exact Intent/route keys) so downstream modules never fail to compile.
4. **Cite the Principle**:
   - Every row logged to `.mstack/audit.tsv` must list `principle-always-compile` alongside the exact compile command and log artifact path.

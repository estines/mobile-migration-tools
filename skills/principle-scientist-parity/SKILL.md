---
name: principle-scientist-parity
description: >-
  Eliminates the "90% business logic accuracy" trap during mobile migrations using Golden Master Approval Testing, GitHub's Scientist Dual-Execution pattern (Control vs Candidate), and Synchronized Storage Proxies.
---

# Principle: Scientist Parity (100% Business Logic & Storage Equivalence)

## Why This Principle Exists
Rewriting legacy mobile business logic (Java, Objective-C, legacy JS/Dart) by reading source code and translating it "from scratch" routinely achieves only ~90% accuracy. The remaining 10% hides in implicit rounding modes (`BigDecimal`), null-coercion quirks, mutable singletons, main-thread callback ordering, and legacy bug workarounds that backend APIs depend on.

## Mandatory Rules

1. **Approval Testing (Golden Master) Before Rewriting**:
   - Before writing the new domain/data implementation, write an automated test harness that executes the **actual untouched legacy class** across a combinatorial matrix of inputs (happy paths, boundary decimals, `1.005`, `-0.005`, nulls, empty strings, malformed payloads, localization edge cases).
   - Serialize the legacy outputs into a Golden Master snapshot file.
   - The new implementation is **rejected** until it produces 100% identical outputs against the Golden Master snapshot.

2. **Two-Phase Language/Type Conversion**:
   - Do not change the language/platform **and** redesign the algorithm/decimal representation in a single blind leap.
   - If introducing pure value types (e.g., KMP `Money` / `Units`), prove mathematical isomorphism against the legacy type (`java.math.BigDecimal`, `NSDecimalNumber`, etc.) over 1,000+ property-based test cases first.

3. **Runtime "Scientist" Dual-Execution (Control vs. Candidate)**:
   - Wrap migrated business logic in a `Scientist<T>` shadow runner during Step 1:
     - **`Control`**: Executes the legacy code path.
     - **`Candidate`**: Executes the new migrated code path asynchronously/safely (read-only/side-effect-isolated).
     - **Comparison**: Deep-compares `Control` and `Candidate` results. Any mismatch is logged with full input context, while `Control` is returned to the UI so user experience never breaks.
   - Cutover from `Control` to `Candidate` is permitted only after `0.00%` mismatches across test/UAT journeys.

4. **Zero Split-Brain Device Storage**:
   - Never write to a new database/preferences store (e.g., Room KMP, DataStore, SwiftData, MMKV) while unmigrated screens still read from the legacy store (`SharedPreferences`, `NSUserDefaults`, legacy SQLite/Realm).
   - Always route through a **Read-Through / Dual-Write Storage Proxy** until 100% of legacy readers for that domain are retired.

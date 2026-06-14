# Skill: Apex Trigger Consolidation Analysis (Cross-Trigger)

Analyze **all triggers on an object together** after per-trigger risk scans are complete. Requires the output blocks from `apex-trigger-risk-scan` for every trigger as input.

Input: all per-trigger scan outputs + all trigger source bodies + all dependent class source bodies.

---

## Analysis Dimensions

### 8. Logic Overlap
Compare all triggers and flag:
- Same field assigned in multiple triggers
- Identical or near-identical validation logic across triggers
- Same helper method called from multiple triggers
- **Severity:** MEDIUM

### 9. Conflicting Logic
Compare all triggers firing on the same event and flag contradictions — not just overlap, but cases where one trigger's output invalidates or opposes another's:
- Same field assigned with different or opposing values across triggers on the same event
- One trigger nulls or clears a field that another trigger reads to make a decision
- Mutually exclusive conditionals: one trigger allows a condition that another blocks
- Read-after-write dependencies where execution order changes the final field value

For each conflict, identify which trigger "wins" if left as-is (last writer wins) and whether that outcome is correct.
- **Severity:** CRITICAL if the field is a key business field (status, owner, amount, record type); HIGH otherwise

### 10. Helper Class Coupling
Map helper/utility classes to dependent triggers. Flag any class used by 2+ triggers — modifying it during consolidation can break all callers. List dependent trigger names per shared class.
- **Severity:** MEDIUM–HIGH based on dependent count

### 11. Test Coverage Gaps
Per trigger, note:
- Whether a corresponding `*Test` class exists
- Coverage below 85%
- Absence of a bulk test (200+ records)
- **Severity:** MEDIUM

### 12. Static Variable Collision
Using the static variable inventories from all per-trigger scan outputs, identify name collisions across handler/helper classes:
- Two or more classes that declare a static variable with the same name (e.g. `isRunning`, `processedIds`)
- After consolidation, if both classes are called from one trigger these variables share JVM-level state within the transaction and can corrupt each other's recursion guards
- List the colliding variable name, both class names, and which trigger each belongs to
- **Severity:** CRITICAL if the collision involves a recursion guard; HIGH otherwise

### 13. Bypass Consolidation Strategy
Using the bypass mechanisms from all per-trigger scan outputs, assess whether bypasses can be unified:
- If all triggers use the same Custom Setting/Metadata record, a single bypass will work post-consolidation
- If triggers use different bypass fields or classes, the handler must preserve per-trigger bypass granularity or merge them — flag which approach is required
- If any trigger has no bypass and others do, flag the inconsistency — post-consolidation the no-bypass trigger's logic inherits the unified bypass unintentionally
- **Severity:** HIGH if bypass inconsistency found; MEDIUM if all bypasses are compatible

### 14. Automation Re-entry Risk
Identify whether any Flow, Process Builder, or Workflow Field Update on this object can commit DML that re-fires Apex triggers mid-transaction:
- Look for trigger logic that reacts to field values that a Flow or WFR also writes
- Flag if two triggers both react to the same automation-written field — consolidation does not eliminate the re-entry, it concentrates it
- Flag any `@future`, `Queueable`, or `Platform Event` publish calls that could loop back into this object's triggers
- **Severity:** HIGH if re-entry path found; LOW otherwise

### 15. Cumulative Governor Limit Budget
Sum governor limit consumption across all triggers and flag compound risk that is invisible per-trigger:
- Estimate combined SOQL query count, DML statement count, and heap usage across all trigger handler paths for a single transaction
- Flag if the combined estimate approaches Salesforce limits (100 SOQL, 150 DML, 6MB heap) even if no single trigger is problematic individually
- Note that consolidation does not reduce limit consumption — it concentrates it in one execution path where a single bulkification failure fails everything
- **Severity:** CRITICAL if combined estimate exceeds 80% of any limit; HIGH if 50–80%

(Dimension numbering: 1–7 from per-trigger scan; 8–15 from this cross-trigger analysis. Managed package triggers are excluded from this analysis — only unmanaged triggers are in scope.)

---

## Risk Scoring

Using per-trigger scores from the scan outputs plus dimensions 8–15 above:
- Assign a **final risk score per trigger** (1–10) — raise the scan score if dim 8–16 findings add risk
- Assign an **overall object risk score** (1–10)

| Score | Meaning |
|-------|---------|
| 1–3 | Low — safe to consolidate with minimal prep |
| 4–6 | Medium — refactor required before merge |
| 7–9 | High — urgent action recommended |
| 10 | Critical — production incident likely without immediate action |

---

## Output Format

1. **Trigger Inventory Table** — `Trigger Name | Events | Lines of Code | Risk Score | Top Risk`
2. **Risk Register Table** — `Trigger | Dimension | Severity | Description | Recommendation` (include dim 1–7 findings from scan outputs + dim 8–15 from this analysis)
3. **Dependency Graph** — plain-text diagram of triggers → shared helper classes
4. **Overall Risk Score** — single score (1–10) with one-sentence justification
5. **Phased Consolidation Recommendation**
   - Phase 1: Safe to merge immediately (no code changes needed)
   - Phase 2: Needs refactoring before merge
   - Phase 3: Final handler framework migration steps

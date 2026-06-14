# Skill: Apex Trigger Risk Scan (Per-Trigger)

Analyze a **single** Apex trigger and its dependent classes across seven risk dimensions. Run this skill once per trigger before calling `apex-trigger-consolidation-analysis`.

Input: one trigger's source body + all dependent class source bodies for that trigger.

---

## Analysis Dimensions

### 1. Execution Order Risk
Triggers fire in undefined order. Flag any assumption this trigger makes about running before or after another specific trigger.
- Look for: comments ("must run after X"), field reads that depend on values another trigger should set first
- **Severity:** HIGH if found, LOW otherwise

### 2. Recursion Traps
Flag absence of a static Boolean recursion guard (`isRunning`, `alreadyExecuted`, `hasRun`, `isExecuting`) when DML is present.
- **Severity:** CRITICAL if no guard + DML present; HIGH if no guard only

### 3. Governor Limit Exposure
Scan trigger and all dependent classes for:
- SOQL inside for-loops → **CRITICAL**
- DML inside for-loops → **CRITICAL**
- Synchronous HTTP callouts in trigger context → **HIGH**
- Aggregate queries without LIMIT → **MEDIUM**

### 4. Before/After Context Boundary
Identify which trigger contexts this trigger fires in (`before insert`, `before update`, `after insert`, etc.) and flag any logic that is in the wrong context:
- Field assignments (`SObject.field = value`) inside an `after` context — these changes are lost silently
- DML on the triggering record's SObject type inside a `before` context — redundant and can cause recursion
- Note which handler methods run in before vs. after — this must be preserved exactly during consolidation
- **Severity:** HIGH if misplaced logic found; LOW otherwise — but always output the context map regardless

### 5. Bypass Mechanism
Look for any per-trigger bypass or kill-switch pattern:
- Custom Setting or Custom Metadata field checks (`TriggerSettings__c`, `TriggerConfig__mdt`, etc.)
- Permission or profile checks used to skip trigger execution
- Static Boolean flags set externally to disable this trigger from test code or other triggers
- Record the exact field/class/method name used as the bypass
- **Severity:** LOW (informational) — but always output what was found; absence of a bypass is also notable

### 6. Static Variable Inventory
List every static variable declared in the trigger's handler or helper classes, especially those used as recursion guards or processed-ID sets:
- Name, type, declared class, and purpose
- Flag any name that is common/generic (`isRunning`, `processed`, `executed`) — collision risk during consolidation if another trigger uses the same name
- **Severity:** MEDIUM if generic names found; LOW otherwise

### 7. Exception and Error Handling Behavior
Scan for patterns that affect transaction behavior:
- `addError()` calls — note the field targeted and the condition that triggers it
- `try/catch` blocks that swallow exceptions silently (catch with no rethrow, no logging)
- Thrown exceptions that would roll back the entire transaction
- **Severity:** HIGH if `addError()` is present (affects which validation surfaces post-consolidation); MEDIUM for swallowed exceptions

---

## Output Format

Return a compact block for this trigger only — no tables, no cross-trigger comparison:

```
TRIGGER: {triggerName}
EVENTS: {comma-separated list}
LOC: {line count}
WHAT IT DOES: {2-3 sentence plain-English summary of the trigger's business purpose and main actions}

DIM1 - Execution Order Risk: {CRITICAL|HIGH|MEDIUM|LOW}
  Finding: {one-sentence description or "None"}

DIM2 - Recursion Trap: {CRITICAL|HIGH|LOW}
  Finding: {one-sentence description or "None"}

DIM3 - Governor Limits: {CRITICAL|HIGH|MEDIUM|LOW}
  Findings:
    - {finding or "None"}

DIM4 - Before/After Context Boundary: {HIGH|LOW}
  Context Map: {e.g. "before update: field assignments; after update: related record DML"}
  Finding: {one-sentence description or "None"}

DIM5 - Bypass Mechanism: {bypass field/class/method name or "None found"}

DIM6 - Static Variable Inventory:
  - {name} | {type} | {class} | {purpose} | Generic name risk: {YES|NO}

DIM7 - Exception/Error Handling: {HIGH|MEDIUM|LOW}
  Findings:
    - {finding or "None"}

TRIGGER RISK SCORE: {1–10}
TOP RISK: {highest-severity dimension name}
```

Return nothing else. This output is consumed by `apex-trigger-consolidation-analysis`.

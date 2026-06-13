# Trigger Audit Plan: Case

> **Object:** Case
> **Triggers analyzed:** 2
> **Overall risk score:** 6/10
> **Status:** DRAFT — review and edit before approving consolidation

---

## Trigger Inventory

| Trigger Name | Events | Lines of Code | Risk Score | Top Risk |
|---|---|---|---|---|
| SDO_Tool_SalesforceRewind_Case | after insert, after update, after delete | 4 (trigger body) + ~70 (handler) | 4/10 | No recursion guard; silent data loss when JSON > 32768 chars |
| CaseTrigger | before insert, before update | HIDDEN | 7/10 | Source body is hidden — cannot audit or safely consolidate |

---

## Risk Register

| Trigger | Dimension | Severity | Description | Recommendation |
|---|---|---|---|---|
| SDO_Tool_SalesforceRewind_Case | Recursion Guard | Medium | No static isRunning guard in trigger or handler. Re-entrant Case DML could re-fire the trigger. | Add recursion guard in consolidated handler |
| SDO_Tool_SalesforceRewind_Case | Silent Data Loss | Medium | JSON payloads > 32768 chars are silently skipped or flagged as Undoable with no user-facing alert | Add explicit error logging or Platform Event notification |
| SDO_Tool_SalesforceRewind_Case | Error Handling | Medium | DML errors call addError on the history record itself, not on the Case — errors are invisible to the triggering user | Surface errors to Case record or use try/catch with meaningful logging |
| SDO_Tool_SalesforceRewind_Case | Managed Package Dependency | Medium | Custom Setting (SDO_Tool_SalesforceRewind__c) and history object are likely installed package objects — fragile if package is uninstalled | Note dependency; do not replicate managed objects in scaffold |
| CaseTrigger | Source Unreadable | High | Trigger body, handler class (CaseTriggerHandler), and test class (TestP2CCaseTriggerHandler) are all hidden/inaccessible via Tooling API | Retrieve source via IDE, package XML, or org admin before consolidation |
| CaseTrigger | Deactivation Risk | High | Fires before insert and before update — may enforce validation or set required fields. Deactivating without reading logic risks breaking Case creation | Do not deactivate until source is reviewed |
| CaseTrigger | Conflict Risk | Medium | Fires in before context; Rewind trigger fires in after context. No direct execution conflict but implicit ordering dependency | Verify no field dependencies exist between before and after logic |
| CaseTrigger | Test Coverage | Medium | TestP2CCaseTriggerHandler exists but body is hidden — coverage level unknown | Obtain test class source; verify coverage >= 85% |

---

## Dependency Graph

```
Case (object)
├── SDO_Tool_SalesforceRewind_Case [after insert, after update, after delete]
│   └── SDO_Tool_SalesforceRewindTriggerHandler (readable)
│       ├── SDO_Tool_SalesforceRewind__c (Custom Setting — likely managed package)
│       └── Salesforce_Rewind_History_Record__c (Custom Object — likely managed package)
│
└── CaseTrigger [before insert, before update]
    └── CaseTriggerHandler (HIDDEN — body inaccessible via Tooling API)
        └── TestP2CCaseTriggerHandler (HIDDEN — test class, body inaccessible)
```

---

## Overall Risk Score: 6/10

One trigger is fully readable with manageable operational risks; the other is completely opaque — consolidation must not proceed until CaseTrigger source is obtained and reviewed.

---

## Logic Merge Map

### Before Insert
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| CaseTrigger | UNKNOWN — body hidden | Unknown | **BLOCKED: obtain source before merging** |

### Before Update
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| CaseTrigger | UNKNOWN — body hidden | Unknown | **BLOCKED: obtain source before merging** |

### After Insert
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| SDO_Tool_SalesforceRewind_Case | Check SFR.Recording__c custom setting; build Salesforce_Rewind_History_Record__c with Record_Name__c, RecordId__c, sObject__c, New_Values__c, Action__c = 'Insert'; batch insert all events | None | Merge as-is; add recursion guard |

### After Update
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| SDO_Tool_SalesforceRewind_Case | Same as after insert but sets Action__c = 'Update', captures Old_Values__c from Trigger.oldMap; sets Status__c = 'Undoable' + Error__c when old JSON > 32768 chars | None | Merge as-is; add recursion guard |

### After Delete
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| SDO_Tool_SalesforceRewind_Case | Iterates Trigger.oldMap; builds history record with Action__c = 'Delete', Old_Values__c from old object JSON (skips if > 32768 chars) | None | Merge as-is; add recursion guard |

---

## Apex Best Practices Compliance

| Best Practice | Current State | Required Action |
|---|---|---|
| One trigger per object | 2 triggers exist | Consolidate into CaseTrigger (or a new CaseTrigger if existing one is managed) |
| No logic in trigger body | SDO_Tool_SalesforceRewind_Case: minimal (batch guard + delegation). CaseTrigger: unknown | All logic moves to CaseTriggerHandler (consolidated) |
| Bulkified — no SOQL in loops | SDO_Tool_SalesforceRewind_Case: compliant. CaseTrigger: unknown | Verify CaseTrigger when source obtained |
| Bulkified — no DML in loops | SDO_Tool_SalesforceRewind_Case: compliant (insert Events is outside loop). CaseTrigger: unknown | Verify CaseTrigger when source obtained |
| Recursion guard present | Missing in both readable trigger and its handler | Add static Boolean isRunning guard in consolidated handler |
| Context-aware (Trigger.isInsert etc.) | SDO_Tool_SalesforceRewind_Case: uses isInsert/isUpdate/isDelete flags passed as params. CaseTrigger: unknown | Wrap all logic in correct Trigger.isInsert / Trigger.isUpdate context checks |
| No hardcoded IDs | SDO_Tool_SalesforceRewind_Case: compliant. CaseTrigger: unknown | Verify CaseTrigger when source obtained |
| No synchronous callouts | SDO_Tool_SalesforceRewind_Case: no callouts. CaseTrigger: unknown | Verify CaseTrigger when source obtained |
| Test coverage above 85% | SDO_Tool_SalesforceRewind_Case: no test class found. CaseTrigger: TestP2CCaseTriggerHandler exists but hidden | Generate CaseTriggerTest.cls covering all merged logic |
| Bulk test scenarios (200 records) | No evidence of bulk tests in readable code | Add bulk test methods (200 records minimum) in generated test class |

---

## Phased Consolidation Plan

### Phase 1 — Unblock: Obtain Hidden Source (REQUIRED BEFORE PHASES 2–3)

Before any consolidation can proceed, the following must be resolved:

1. **Retrieve CaseTrigger source** — use `sf project retrieve start --metadata "ApexTrigger:CaseTrigger"` or open in Developer Console / VS Code org browser.
2. **Retrieve CaseTriggerHandler source** — `sf project retrieve start --metadata "ApexClass:CaseTriggerHandler"`.
3. **Retrieve TestP2CCaseTriggerHandler source** — `sf project retrieve start --metadata "ApexClass:TestP2CCaseTriggerHandler"`.
4. If any of these are namespaced managed-package classes, note the namespace — treat as unmodifiable and call the managed handler directly from the consolidated trigger rather than absorbing its logic.
5. Re-run analysis against retrieved source before proceeding to Phase 2.

### Phase 2 — Refactor Before Merging

Once source is obtained:

1. **SDO_Tool_SalesforceRewind_Case / SDO_Tool_SalesforceRewindTriggerHandler**: Bulkification already compliant. No changes required. Preserve batch context guard.
2. **CaseTrigger / CaseTriggerHandler**: Audit for SOQL/DML in loops, hardcoded IDs, and synchronous callouts. Refactor any violations before merging.
3. Confirm all managed-package object references (SDO_Tool_SalesforceRewind__c, Salesforce_Rewind_History_Record__c) are preserved as-is — do not replicate or rename.

### Phase 3 — Merge and Consolidate

Once Phases 1 and 2 are complete:

1. Create new `CaseTrigger.trigger` covering the union of all events: `before insert, before update, after insert, after update, after delete`.
2. Create `CaseTriggerHandler.cls` with one method per event context and a static `isRunning` recursion guard.
3. Merge SDO_Tool_SalesforceRewindTriggerHandler logic into `afterInsert`, `afterUpdate`, `afterDelete` — wrapped in `SFR.Recording__c` guard and batch skip.
4. Merge CaseTriggerHandler logic (once readable) into `beforeInsert` and `beforeUpdate`.
5. Deactivate original triggers **only after** full production validation.

### Phase 4 — Validate and Clean Up

1. Run `CaseTriggerTest.cls` — all methods pass, coverage >= 85%.
2. Verify bulk test scenarios with 200 records pass governor limits.
3. Confirm `Salesforce_Rewind_History_Record__c` records are created correctly post-consolidation.
4. Search for `// CONFLICT` and `// ASYNC REQUIRED` comments — resolve each manually.
5. Deactivate and archive original triggers after production sign-off.

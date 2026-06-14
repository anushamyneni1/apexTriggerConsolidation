# Workflow: Trigger Consolidation

Retrieves all Apex triggers on any Salesforce object, analyzes risks across six
dimensions, writes an editable audit plan, waits for your approval, then
generates a consolidated trigger handler scaffold directly into your SFDX project.

Works for any standard or custom object — just provide the object API name when
prompted.

---

## Step 1 — Ask for the Target Object

Ask the user:

"Which Salesforce object do you want to consolidate triggers for?
Provide the API name (e.g. Opportunity, Case, Account, Invoice__c)."

Wait for the answer. Use that value as {objectName} throughout all remaining steps.

---

## Step 2 — Retrieve All Triggers from the Org

Using the Salesforce CLI, query the org for all active Apex triggers on {objectName}.

Run:
```
sf data query --query "SELECT Id, Name, TableEnumOrId, UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate, UsageBeforeDelete, UsageAfterDelete, UsageAfterUndelete, Status FROM ApexTrigger WHERE TableEnumOrId = '{objectName}' AND Status = 'Active'" --use-tooling-api --json
```

If zero triggers are returned, tell the user:
"No active triggers found on {objectName}. Please check the object API name and
confirm triggers exist in the connected org."
Then stop.

For each trigger found, retrieve its full source body:
```
sf data query --query "SELECT Id, Name, Body FROM ApexTrigger WHERE Name = '{triggerName}'" --use-tooling-api --json
```

Parse each trigger body and identify every Apex class it references
(helper classes, handler classes, utility classes, service classes).

For each referenced class, retrieve its source:
```
sf data query --query "SELECT Id, Name, Body FROM ApexClass WHERE Name = '{className}'" --use-tooling-api --json
```

Check for existing test classes for each trigger:
```
sf data query --query "SELECT Id, Name FROM ApexClass WHERE Name LIKE '%{triggerName}%' AND Name LIKE '%Test%'" --use-tooling-api --json
```

Summarize what was retrieved before moving to Step 3:
- Total triggers found and their names
- Total dependent classes retrieved
- Any classes that could not be retrieved (e.g. managed package — note as unreadable and skip)

---

## Step 3 — Analyze Risks

Load the .a4drules/skills/apex-trigger-analysis.md skill.

Apply every analysis dimension from the skill to all retrieved trigger source
code and dependent class source code.

Produce:
- A per-trigger risk summary
- A full risk register
- A dependency graph
- An overall risk score for {objectName}

---

## Step 4 — Write the Audit Plan File

Write all findings to: docs/trigger-audit-plan.md

Use this exact structure:

```
# Trigger Audit Plan: {objectName}

> **Object:** {objectName}
> **Triggers analyzed:** {count}
> **Overall risk score:** {score}/10
> **Status:** DRAFT — review and edit before approving consolidation

---

## Trigger Inventory

| Trigger Name | Events | Lines of Code | Risk Score | Top Risk |
|---|---|---|---|---|
| {row per trigger} |

---

## Risk Register

| Trigger | Dimension | Severity | Description | Recommendation |
|---|---|---|---|---|
| {row per finding} |

---

## Dependency Graph

{plain-text diagram of trigger → helper class relationships}

---

## Overall Risk Score: {score}/10

{one-sentence justification}

---

## Logic Merge Map

For each trigger context (before insert, after insert, before update, after update,
before delete, after delete, after undelete), list every piece of business logic
from every trigger that belongs to that context. This is the exact map the
consolidation will follow.

### Before Insert
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| {triggerName} | {what this code does} | {conflicts with another trigger?} | {merge as-is / refactor first / deduplicate} |

### After Insert
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|

### Before Update
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|

### After Update
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|

### Before Delete
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|

### After Delete
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|

(Only include contexts that exist across the original triggers)

---

## Apex Best Practices Compliance

For each best practice below, note the current state across all triggers and
what the consolidated code must do to comply:

| Best Practice | Current State | Required Action |
|---|---|---|
| One trigger per object | {count} triggers exist | Consolidate into {objectName}Trigger |
| No logic in trigger body | {compliant / violations found} | All logic moves to handler class |
| Bulkified — no SOQL in loops | {compliant / which triggers violate} | Refactor before merging |
| Bulkified — no DML in loops | {compliant / which triggers violate} | Refactor before merging |
| Recursion guard present | {present / missing in which triggers} | Add isRunning guard in handler |
| Context-aware (Trigger.isInsert etc.) | {compliant / violations} | Wrap all logic in correct context checks |
| No hardcoded IDs | {compliant / violations} | Replace with SOQL lookups or custom metadata |
| No synchronous callouts | {compliant / violations} | Move to @future or Queueable |
| Test coverage above 85% | {current coverage per trigger} | Generate comprehensive test class |
| Bulk test scenarios (200 records) | {present / missing} | Add bulk test methods |

---

## Phased Consolidation Plan

### Phase 1 — Refactor Before Merging
{List every trigger and class change required BEFORE merging — bulkification,
removing hardcoded IDs, moving callouts to async. No merge happens until
these are done.}

### Phase 2 — Merge and Consolidate
{List the exact order to merge logic from each trigger into the handler,
following the Logic Merge Map above. Note which duplicates to drop and which
to keep.}

### Phase 3 — Validate and Clean Up
{Final checks: recursion guard in place, all contexts tested, original triggers
deactivated only after production validation.}
```

After writing the file, tell the user:

"Audit complete. I've written the full plan to docs/trigger-audit-plan.md.

Overall risk score: {score}/10

Please open docs/trigger-audit-plan.md and review:
- Check the Logic Merge Map — this is what the consolidation will follow
- Verify the Best Practices Compliance table
- Adjust the consolidation phases if needed
- Add any team notes to the plan

When you are ready to generate the consolidated scaffold, reply YES.
To stop here and use the plan document only, reply NO."

Wait for the user's response before continuing.

---

## Step 5 — Generate the Consolidated Scaffold

Only proceed if the user replied YES.

Read docs/trigger-audit-plan.md to pick up any edits the user made.
Use the Logic Merge Map in the plan as the authoritative guide for what logic
goes into each method. Do not drop any logic — every piece of business logic
from every original trigger must appear in the consolidated code.

Apply all Apex best practices throughout generation:
- One trigger per object, no logic in the trigger body
- All SOQL queries collected outside loops (bulkified)
- All DML collected outside loops (bulkified)
- Recursion guard using a static Boolean isRunning flag
- Context-aware checks (Trigger.isInsert, Trigger.isUpdate etc.)
- No hardcoded IDs — use SOQL lookups or Custom Metadata
- Async pattern for any callouts (flag with comment if original used sync)
- Null-safe access — check Trigger.new and Trigger.old before use
- Meaningful method and variable names — no single-letter variables

Generate and write these four files into the SFDX project:

---

### File 1: force-app/main/default/triggers/{objectName}Trigger.trigger

- Single trigger covering only the events that existed across the original triggers
- Zero business logic in the trigger body — every line delegates to the handler
- Header comment listing every original trigger this replaces

```
// Consolidated trigger — replaces: {comma-separated list of original trigger names}
// Original triggers covered all of the following events: {list}
trigger {objectName}Trigger on {objectName} (
    {only the unique events present in the original triggers}
) {
    {objectName}TriggerHandler handler = new {objectName}TriggerHandler();
    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert(Trigger.new);
        if (Trigger.isUpdate) handler.beforeUpdate(Trigger.new, Trigger.oldMap);
        if (Trigger.isDelete) handler.beforeDelete(Trigger.old);
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert)   handler.afterInsert(Trigger.new);
        if (Trigger.isUpdate)   handler.afterUpdate(Trigger.new, Trigger.oldMap);
        if (Trigger.isDelete)   handler.afterDelete(Trigger.old);
        if (Trigger.isUndelete) handler.afterUndelete(Trigger.new);
    }
}
```

---

### File 2: force-app/main/default/classes/{objectName}TriggerHandler.cls

- One public method per trigger context — only for events in the original triggers
- Static Boolean isRunning recursion guard at the top of the class
- Each method calls into {objectName}TriggerHelper for the actual logic
- At the top of each method: a comment listing every source trigger and what
  logic was merged from it
- Logic from multiple triggers merged into the correct sequence within each method
  following the Logic Merge Map in docs/trigger-audit-plan.md
- Duplicate logic that appeared in more than one trigger: keep one copy, remove duplicates
- If original logic conflicts between triggers: flag with
  // CONFLICT: {triggerA} sets Field__c = X, {triggerB} sets Field__c = Y — review
- Any logic requiring async (callouts): flag with
  // ASYNC REQUIRED: original trigger used sync callout — move to @future or Queueable

```
public class {objectName}TriggerHandler {

    // Recursion guard — prevents re-entry when DML inside a method re-fires this trigger
    private static Boolean isRunning = false;

    // Consolidated from: {list of original trigger names}

    public void beforeInsert(List<{objectName}> newList) {
        if (isRunning) return;
        isRunning = true;
        try {
            // Merged from: {source trigger names for this context}
            // {description of what this method now does}
            {objectName}TriggerHelper.handleBeforeInsert(newList);
        } finally {
            isRunning = false;
        }
    }

    // ... one method per active event context, same pattern
}
```

---

### File 3: force-app/main/default/classes/{objectName}TriggerHelper.cls

- The actual business logic lives here — fully ported from the original triggers
- One static method per event context matching what the handler calls
- All SOQL outside loops: collect record IDs first, run a single query, map results back
- All DML outside loops: collect records into a list, single DML statement at the end
- Deduplicated: if two original triggers had the same logic, it appears once here
- No DML inside helper methods — helper methods prepare data, handler methods commit it
- Field assignments grouped by context so execution order is explicit and readable
- Inline comments on each logical block identifying its source trigger

```
public class {objectName}TriggerHelper {

    public static void handleBeforeInsert(List<{objectName}> newList) {
        // Source: {triggerName} — {description of logic}
        // {ported and bulkified business logic}
    }

    public static void handleAfterInsert(List<{objectName}> newList) {
        // Source: {triggerName} — {description of logic}
        // Collect IDs for bulk query
        Set<Id> recordIds = new Set<Id>();
        for ({objectName} rec : newList) {
            recordIds.add(rec.Id);
        }
        // Single bulkified query (was inside for-loop in {originalTrigger})
        // {ported and bulkified business logic}
    }

    // ... one method per active event
}
```

---

### File 4: force-app/main/default/classes/{objectName}TriggerTest.cls

- @IsTest class with @TestSetup for shared test data
- Test every piece of business logic merged from the original triggers —
  not just the scaffold, but the actual merged logic
- One test method per original trigger's key scenario so coverage is traceable
- Bulk test for every DML context (200 records minimum)
- Assert on the specific field values and record states the original triggers
  were responsible for — not generic existence checks
- Use Test.startTest() / Test.stopTest() to capture governor limit consumption

```
@IsTest
public class {objectName}TriggerTest {

    @TestSetup
    static void setup() {
        // Shared test data for all test methods
        // {create the minimum required related records}
    }

    // --- Tests covering logic from {sourceTrigerName1} ---

    @IsTest
    static void test_{logicDescription}_singleRecord() {
        // Arrange
        // Act
        Test.startTest();
        // {insert or update}
        Test.stopTest();
        // Assert — verify the specific outcome this trigger was responsible for
    }

    @IsTest
    static void test_{logicDescription}_bulkRecords() {
        // Arrange — 200 records
        List<{objectName}> records = new List<{objectName}>();
        for (Integer i = 0; i < 200; i++) {
            records.add(new {objectName}( /* required fields */ ));
        }
        // Act
        Test.startTest();
        insert records;
        Test.stopTest();
        // Assert — bulk outcome
    }

    // --- Tests covering logic from {sourceTriggerName2} ---
    // ... one test group per original trigger's key scenario
}
```

---

After writing each file confirm with path and line count:
✓ force-app/main/default/triggers/{objectName}Trigger.trigger (N lines)
✓ force-app/main/default/classes/{objectName}TriggerHandler.cls (N lines)
✓ force-app/main/default/classes/{objectName}TriggerHelper.cls (N lines)
✓ force-app/main/default/classes/{objectName}TriggerTest.cls (N lines)

Then tell the user:
"Consolidation complete. All logic from the original triggers has been merged
into the scaffold following Apex best practices. Search for // CONFLICT and
// ASYNC REQUIRED comments — these are the only places that need manual review
before the code is production-ready."

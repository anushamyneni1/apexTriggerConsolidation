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

## Step 2 — Retrieve Trigger List

**IMPORTANT: Use the Bash tool to run the CLI command below. Do NOT use any MCP Salesforce tool for this step.**

Run a single query to get all active triggers on {objectName}:

```
sf data query --query "SELECT Id, Name, NamespacePrefix, TableEnumOrId, UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate, UsageBeforeDelete, UsageAfterDelete, UsageAfterUndelete, Status FROM ApexTrigger WHERE TableEnumOrId = '{objectName}' AND Status = 'Active'" --use-tooling-api --json
```

From the results, **exclude any trigger where `NamespacePrefix` is non-null and non-empty** — those are managed package triggers and must be ignored for the rest of this workflow.

If zero unmanaged triggers remain after filtering, tell the user:
"No active unmanaged triggers found on {objectName}. Please check the object API name and
confirm unmanaged triggers exist in the connected org."
Then stop.

Record the filtered list of unmanaged trigger names as {triggerList}.

**Checkpoint 2a — print before continuing:**
```
CHECKPOINT 2a
Object: {objectName}
Triggers found (total): {count}
Managed (excluded): {count} — {list names with their namespace prefix, or 'none'}
Unmanaged (in scope): {count}
Names: {triggerList}
```

---

## Step 3 — Retrieve Trigger Bodies (Batched)

**IMPORTANT: Use the Bash tool to run the CLI command below. Do NOT use any MCP Salesforce tool for this step.**

Build a single IN-list query using all names from {triggerList}:

```
sf data query --query "SELECT Id, Name, Body FROM ApexTrigger WHERE Name IN ('{name1}','{name2}',...)" --use-tooling-api --json
```

Store each trigger's Body. Do not run one query per trigger.

**Step 3b — Save each trigger body to disk for local validation.**

First create the directory:
```bash
mkdir -p force-app/main/default/triggers
```

For each trigger in the results, write two files:

1. `force-app/main/default/triggers/{triggerName}.trigger` — the raw Body from the query
2. `force-app/main/default/triggers/{triggerName}.trigger-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexTrigger>
```

Write one trigger at a time and print `SAVED: {triggerName}.trigger` after each.

**Checkpoint 3a — print before continuing:**
```
CHECKPOINT 3a
Bodies retrieved: {count}/{count}
Saved to disk: {count}
Any failures: {none | list names that returned empty Body}
```

---

## Step 4 — Identify and Retrieve Dependent Classes (Batched)

**IMPORTANT: Use the Bash tool to run the CLI command below. Do NOT use any MCP Salesforce tool for this step.**

Parse each trigger body and collect every Apex class name referenced
(handler, helper, utility, service classes).

Build a single IN-list query for all referenced class names at once:

```
sf data query --query "SELECT Id, Name, Body FROM ApexClass WHERE Name IN ('{class1}','{class2}',...)" --use-tooling-api --json
```

If the class name set is empty (no external classes referenced), skip this query.

Mark any class whose Body is empty or null as **unreadable** (managed package).
Do not retry unreadable classes.

**Step 4b — Save each readable class body to disk for local validation.**

First create the directory:
```bash
mkdir -p force-app/main/default/classes
```

For each class with a non-empty Body, write two files:

1. `force-app/main/default/classes/{className}.cls` — the raw Body from the query
2. `force-app/main/default/classes/{className}.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Write one class at a time and print `SAVED: {className}.cls` after each.
Skip unreadable (managed) classes — do not write empty files.

**Checkpoint 4a — print before continuing:**
```
CHECKPOINT 4a
Referenced classes identified: {count}
Classes retrieved: {count}
Saved to disk: {count}
Unreadable (managed): {list or none}
```

---

## Step 5 — Retrieve Test Classes (Batched)

**IMPORTANT: Use the Bash tool to run the CLI command below. Do NOT use any MCP Salesforce tool for this step.**

Build a single query to retrieve the Name and Body of test classes for all triggers at once:

```
sf data query --query "SELECT Id, Name, Body FROM ApexClass WHERE (Name LIKE '%{trigger1}%' OR Name LIKE '%{trigger2}%' ...) AND Name LIKE '%Test%'" --use-tooling-api --json
```

Record which test classes exist for which triggers.

**Step 5b — Save each test class body to disk for local validation.**

For each test class with a non-empty Body, write two files under `force-app/main/default/classes/`:

1. `force-app/main/default/classes/{testClassName}.cls` — the raw Body from the query
2. `force-app/main/default/classes/{testClassName}.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Write one class at a time and print `SAVED: {testClassName}.cls` after each.

**Checkpoint 5a — print before continuing:**
```
CHECKPOINT 5a
Test classes found: {count}
Saved to disk: {count}
Coverage: {list trigger → test class name, or 'none' if missing}
```

---

## Step 5c — Retrieve Custom Metadata Types and Records Referenced by Triggers

**IMPORTANT: Use the Bash tool for all CLI commands below. Do NOT use any MCP Salesforce tool for this step.**

Parse every trigger body and dependent class body already retrieved. Collect every Custom Metadata type name referenced — these appear as `{TypeName}__mdt` in SOQL queries or dot-notation reads (e.g. `{TypeName}__mdt.getInstance()`, `[SELECT ... FROM {TypeName}__mdt]`).

If no Custom Metadata types are referenced, print:
```
CHECKPOINT 5c — no Custom Metadata types referenced, skipping
```
and continue to Step 6.

Otherwise, for each unique `{TypeName}__mdt` found:

### 5c-i — Retrieve the type schema (field definitions)

**IMPORTANT: Use the Bash tool to run the CLI command below. Do NOT use any MCP Salesforce tool for this step.**

```
sf data query --query "SELECT Id, DeveloperName, Label, QualifiedApiName FROM CustomObject WHERE QualifiedApiName = '{TypeName}__mdt'" --use-tooling-api --json
```

Then retrieve all custom fields for the type:

```
sf data query --query "SELECT Id, DeveloperName, Label, DataType FROM CustomField WHERE TableEnumOrId = '{TypeName}__mdt'" --use-tooling-api --json
```

Save the schema to disk:

1. Run: `mkdir -p force-app/main/default/objects/{TypeName}__mdt/fields`

2. Write `force-app/main/default/objects/{TypeName}__mdt/{TypeName}__mdt.object-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>{Label from query}</label>
    <pluralLabel>{Label from query}s</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
```

3. For each custom field returned, write `force-app/main/default/objects/{TypeName}__mdt/fields/{FieldDeveloperName}__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>{FieldDeveloperName}__c</fullName>
    <label>{FieldLabel}</label>
    <type>{DataType mapped to Metadata API type}</type>
</CustomField>
```

Print `SAVED SCHEMA: {TypeName}__mdt ({n} fields)` after each type.

### 5c-ii — Retrieve the records

**IMPORTANT: Use the Bash tool to run the CLI command below. Do NOT use any MCP Salesforce tool for this step.**

Query all records for this type, selecting every custom field retrieved in 5c-i:

```
sf data query --query "SELECT Id, DeveloperName, Label, {field1}__c, {field2}__c, ... FROM {TypeName}__mdt" --json
```

Save each record to disk under `force-app/main/default/customMetadata/`. Run `mkdir -p force-app/main/default/customMetadata` first.

For each record, write `force-app/main/default/customMetadata/{TypeName}.{DeveloperName}.md-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>{Label from record}</label>
    <protected>false</protected>
    <values>
        <field>{FieldDeveloperName}__c</field>
        <value xsi:type="xsd:{xsdType}">{value}</value>
    </values>
    <!-- one <values> block per custom field -->
</CustomMetadata>
```

Print `SAVED RECORD: {TypeName}.{DeveloperName}.md-meta.xml` after each record.

**Checkpoint 5c — print after all types are processed:**
```
CHECKPOINT 5c
Custom Metadata types found in code: {list or none}
Schema files written: {count}
Record files written: {count}
```

---

## Step 5d — Scan and Retrieve Named Credentials

**IMPORTANT: Use the Bash tool for all CLI commands below. Do NOT use any MCP Salesforce tool for this step.**

Scan every trigger body and dependent class body already retrieved for Named Credential references.
Look for patterns: `callout:{name}`, `HttpRequest.setEndpoint('callout:{name}')`, `'callout:{name}/`.

If none found, print:
```
CHECKPOINT 5d — no Named Credentials referenced, skipping
```
and continue to Step 5e.

Otherwise, retrieve all referenced Named Credentials in a single query:

```
sf data query --query "SELECT Id, DeveloperName, Endpoint, PrincipalType, Protocol FROM NamedCredential WHERE DeveloperName IN ('{name1}','{name2}',...)" --use-tooling-api --json
```

Run `mkdir -p force-app/main/default/namedCredentials` first.

For each Named Credential returned, write `force-app/main/default/namedCredentials/{DeveloperName}.namedCredential-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>{DeveloperName}</label>
    <endpoint>{Endpoint}</endpoint>
    <protocol>{Protocol}</protocol>
    <principalType>{PrincipalType}</principalType>
</NamedCredential>
```

Print `SAVED: {DeveloperName}.namedCredential-meta.xml` after each.

**Checkpoint 5d — print after processing:**
```
CHECKPOINT 5d
Named Credentials referenced in code: {list or none}
Files written: {count}
```

---

## Step 5e — Scan and Retrieve Static Resources

**IMPORTANT: Use the Bash tool for all CLI commands below. Do NOT use any MCP Salesforce tool for this step.**

Scan every trigger body and dependent class body for Static Resource references.
Look for patterns: `Test.loadData(...)`, `PageReference('/resource/{name}')`, `'/resource/{name}'`.

If none found, print:
```
CHECKPOINT 5e — no Static Resources referenced, skipping
```
and continue to Step 5f.

Otherwise, retrieve metadata for all referenced Static Resources in a single query:

```
sf data query --query "SELECT Id, Name, ContentType, CacheControl FROM StaticResource WHERE Name IN ('{name1}','{name2}',...)" --use-tooling-api --json
```

Note: Static Resource bodies (binaries, ZIPs) are not retrieved here — only the metadata stub is written so the SFDX project is aware of the dependency.

Run `mkdir -p force-app/main/default/staticresources` first.

For each Static Resource returned, write `force-app/main/default/staticresources/{Name}.resource-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<StaticResource xmlns="http://soap.sforce.com/2006/04/metadata">
    <cacheControl>{CacheControl}</cacheControl>
    <contentType>{ContentType}</contentType>
</StaticResource>
```

Print `SAVED STUB: {Name}.resource-meta.xml` after each. Note in the checkpoint that binary content must be retrieved separately with `sf project retrieve start`.

**Checkpoint 5e — print after processing:**
```
CHECKPOINT 5e
Static Resources referenced in code: {list or none}
Metadata stubs written: {count}
Note: binary content not retrieved — run sf project retrieve start to pull full files
```

---

## Step 5f — Scan and Retrieve Custom Labels

**IMPORTANT: Use the Bash tool for all CLI commands below. Do NOT use any MCP Salesforce tool for this step.**

Scan every trigger body and dependent class body for Custom Label references.
Look for patterns: `Label.{LabelName}`, `System.Label.{LabelName}`.

If none found, print:
```
CHECKPOINT 5f — no Custom Labels referenced, skipping
```
and continue to Step 5g.

Otherwise, retrieve all referenced labels in a single query using an IN clause:

```
sf data query --query "SELECT Id, Name, Value, Language, Protected FROM ExternalString WHERE Name IN ('{label1}','{label2}',...)" --use-tooling-api --json
```

Run `mkdir -p force-app/main/default/labels` first.

Check if `force-app/main/default/labels/CustomLabels.labels-meta.xml` exists.

- If it does not exist, write a new file with all labels as `<labels>` entries.
- If it already exists, use the Edit tool to append new `<labels>` entries inside the root `<CustomLabels>` element.

File format:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomLabels xmlns="http://soap.sforce.com/2006/04/metadata">
    <labels>
        <fullName>{Name}</fullName>
        <language>{Language}</language>
        <protected>{Protected}</protected>
        <shortDescription>{Name}</shortDescription>
        <value>{Value}</value>
    </labels>
    <!-- one <labels> block per referenced label -->
</CustomLabels>
```

Print `SAVED: CustomLabels.labels-meta.xml ({n} labels)`.

**Checkpoint 5f — print after processing:**
```
CHECKPOINT 5f
Custom Labels referenced in code: {list or none}
Labels written to file: {count}
```

---

## Step 5g — Scan for Platform Events

**IMPORTANT: Use the Bash tool for all CLI commands below. Do NOT use any MCP Salesforce tool for this step.**

Scan every trigger body and dependent class body for Platform Event references.
Look for patterns: `EventBus.publish(...)`, `new {EventName}__e(...)`, `[SELECT ... FROM {EventName}__e]`.

If none found, print:
```
CHECKPOINT 5g — no Platform Events referenced, skipping
```
and continue to Step 6.

Otherwise, retrieve the Platform Event object definitions:

```
sf data query --query "SELECT Id, DeveloperName, Label FROM PlatformEventChannel WHERE DeveloperName IN ('{event1}','{event2}',...)" --use-tooling-api --json
```

Do not write schema files for Platform Events — they are managed in the org. Instead, record the names and usage for the audit plan's External Dependencies section.

**Checkpoint 5g — print after processing:**
```
CHECKPOINT 5g
Platform Events referenced in code: {list or none}
Note: Platform Event schemas are not scaffolded — listed in audit plan External Dependencies only
```

---

## Step 6 — Per-Trigger Risk Scan (One Trigger at a Time)

Read the file `.a4drules/skills/apex-trigger-risk-scan.md` using the Read tool and apply every analysis dimension defined in that file.

Process **one trigger at a time**. For each trigger in {triggerList}:

1. Apply every analysis dimension from the skill to that trigger's body
   and all its dependent class bodies.
2. Produce a risk summary and risk register entries for that trigger.
3. Print the per-trigger output before moving to the next trigger:

```
--- RISK SCAN: {triggerName} ---
Events: {list}
Lines: {count}
Risk score: {n}/10
Key findings:
  - {finding 1}
  - {finding 2}
Risk register entries: {count}
---
```

Do not batch all triggers into a single analysis pass — process sequentially
and output each result before starting the next.

**Checkpoint 6a — print after all per-trigger scans:**
```
CHECKPOINT 6a
Per-trigger scans complete: {count}/{count}
Highest individual risk: {triggerName} ({score}/10)
```

---

## Step 7 — Cross-Trigger Analysis

Read the file `.a4drules/skills/apex-trigger-consolidation-analysis.md` using the Read tool and apply every cross-trigger dimension defined in that file.

Using all per-trigger scan outputs from Step 6 and all source code as input,
apply every cross-trigger dimension from that skill.

Produce:
- A dependency graph
- An overall risk score for {objectName}
- Cross-trigger conflict list
- Deduplication candidates

**Checkpoint 7a — print before continuing:**
```
CHECKPOINT 7a
Cross-trigger analysis complete
Overall risk score: {score}/10
Conflicts found: {count}
Deduplication candidates: {count}
```

---

## Step 8.1 — Audit Plan: Header + Trigger Inventory

Print to chat then immediately write to `docs/audit-sections/01-header.md`:

```
# Trigger Audit Plan: {objectName}

> **Object:** {objectName}
> **Triggers analyzed:** {count}
> **Overall risk score:** {score}/10
> **Status:** DRAFT — review and edit before approving consolidation

## Trigger Inventory

| Trigger Name | Events | Lines of Code | Risk Score | Top Risk |
|---|---|---|---|---|
| {one row per trigger} |
```

**Checkpoint 8.1:**
```
CHECKPOINT 8.1 — docs/audit-sections/01-header.md written
```

---

## Step 8.2 — Audit Plan: Risk Register + Dependency Graph

Print to chat then immediately write to `docs/audit-sections/02-risk.md`:

```
## Risk Register

| Trigger | Dimension | Severity | Description | Recommendation |
|---|---|---|---|---|
| {one row per finding} |

## Dependency Graph

{plain-text diagram of trigger → helper class relationships}

## Overall Risk Score: {score}/10

{one-sentence justification}
```

**Checkpoint 8.2:**
```
CHECKPOINT 8.2 — docs/audit-sections/02-risk.md written
```

---

## Step 8.2b — Audit Plan: External Dependencies

Using the results from Steps 5c through 5g, print to chat then immediately write to `docs/audit-sections/02b-dependencies.md`:

```
## External Dependencies

Components referenced by the triggers and their dependent classes that are not
defined in Apex. Review this section before consolidating — any missing or
changed dependency will break the consolidated handler.

### Named Credentials

| Name | Endpoint | Protocol | Referenced In | Local File |
|---|---|---|---|---|
| {name} | {endpoint} | {protocol} | {trigger or class name} | {path or 'not written — managed'} |

(If none: "None referenced.")

### Static Resources

| Name | Content Type | Referenced In | Notes |
|---|---|---|---|
| {name} | {type} | {trigger or class name} | Metadata stub written — binary must be retrieved separately |

(If none: "None referenced.")

### Custom Labels

| Label Name | Value | Referenced In |
|---|---|---|
| {name} | {value} | {trigger or class name} |

(If none: "None referenced.")

### Custom Metadata Types

| Type API Name | Records Retrieved | Referenced In | Local Files |
|---|---|---|---|
| {TypeName}__mdt | {count} | {trigger or class name} | {schema path} |

(If none: "None referenced.")

### Platform Events

| Event API Name | Usage | Referenced In | Notes |
|---|---|---|---|
| {EventName}__e | {publish / subscribe} | {trigger or class name} | Schema managed in org — not scaffolded |

(If none: "None referenced.")

### Custom Settings / Custom Objects (Manual Action Required)

List any Custom Settings (`__c` with `getInstance()`) or Custom Objects referenced
by the trigger logic that were not retrieved. These must be created or retrieved
manually before deployment.

| Name | Type | Referenced In | Action Required |
|---|---|---|---|
| {name} | Custom Setting / Custom Object | {trigger or class name} | Retrieve or create manually |

(If none: "None identified.")
```

**Checkpoint 8.2b:**
```
CHECKPOINT 8.2b — docs/audit-sections/02b-dependencies.md written
```

---

## Step 8.3 — Audit Plan: Logic Merge Map

**One trigger context at a time.** For each context that exists across the original triggers (Before Insert, After Insert, Before Update, After Update, Before Delete, After Delete), print the table for that context to chat, then move to the next. After all contexts are printed, write the complete merge map to `docs/audit-sections/03-merge-map.md`.

For each context, print to chat:
```
MERGE MAP — {Context Name}
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| {rows} |
{Context Name} DONE
```

After all contexts:
```
ALL CONTEXTS COMPLETE — writing 03-merge-map.md now
```

Write to `docs/audit-sections/03-merge-map.md`:
```
## Logic Merge Map

### {Context 1}
| Source Trigger | Logic Description | Conflicts | Merge Action |
|---|---|---|---|
| {rows} |

### {Context 2}
...
(only contexts present in the original triggers)
```

**Checkpoint 8.3:**
```
CHECKPOINT 8.3 — docs/audit-sections/03-merge-map.md written
```

---

## Step 8.4 — Audit Plan: Apex Best Practices Compliance

Print to chat then immediately write to `docs/audit-sections/04-best-practices.md`:

```
## Apex Best Practices Compliance

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
```

**Checkpoint 8.4:**
```
CHECKPOINT 8.4 — docs/audit-sections/04-best-practices.md written
```

---

## Step 8.5 — Audit Plan: Phase 1 — Refactor Before Merging

List every change required across all triggers BEFORE any merge — bulkification fixes, hardcoded ID replacements, callouts moved to async. One trigger per bullet. Print to chat then immediately write to `docs/audit-sections/05-phase1.md`.

**Checkpoint 8.5:**
```
CHECKPOINT 8.5 — docs/audit-sections/05-phase1.md written
```

---

## Step 8.6 — Audit Plan: Phase 2 — Merge and Consolidate

**One trigger context at a time.** For each context (Before Insert, After Insert, Before Update, After Update, Before Delete, After Delete) that exists across the original triggers:

Print to chat:
```
PHASE 2 — {Context}: merging {list of source triggers}
{numbered merge steps for this context only}
{Context} MERGE STEPS DONE
```

After all contexts are printed, write the complete Phase 2 section to `docs/audit-sections/06-phase2.md`.

**Checkpoint 8.6:**
```
CHECKPOINT 8.6 — docs/audit-sections/06-phase2.md written
```

---

## Step 8.7 — Audit Plan: Phase 3 — Validate and Clean Up

List final validation checks: recursion guard confirmed, all contexts tested, original triggers deactivated only after production validation. Print to chat then immediately write to `docs/audit-sections/07-phase3.md`.

**Checkpoint 8.7:**
```
CHECKPOINT 8.7 — docs/audit-sections/07-phase3.md written
```

---

## Step 8.8 — Assemble Final Audit Plan

Use the Bash tool to concatenate the seven section files directly on disk — do not read them into memory first:

```
cat docs/audit-sections/01-header.md \
    docs/audit-sections/02-risk.md \
    docs/audit-sections/02b-dependencies.md \
    docs/audit-sections/03-merge-map.md \
    docs/audit-sections/04-best-practices.md \
    docs/audit-sections/05-phase1.md \
    docs/audit-sections/06-phase2.md \
    docs/audit-sections/07-phase3.md \
    > docs/trigger-audit-plan.md
```

**Checkpoint 8.8:**
```
CHECKPOINT 8.8
docs/trigger-audit-plan.md written: YES
Line count: {n}
```

Then tell the user:

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

## Step 9 — Prepare Output Directories

Before writing any file, ensure all required directories exist. Run each mkdir in a single Bash call:

```bash
mkdir -p force-app/main/default/triggers \
          force-app/main/default/classes \
          force-app/main/default/customMetadata
```

Print:
```
CHECKPOINT 9 — output directories ready
```

---

## Step 10 — Generate File 1: Trigger + Metadata

Only proceed if the user replied YES.

Read docs/trigger-audit-plan.md to pick up any edits the user made.

Apply all Apex best practices:
- One trigger per object, no logic in the trigger body
- All SOQL queries collected outside loops (bulkified)
- All DML collected outside loops (bulkified)
- Recursion guard using a static Boolean isRunning flag
- Context-aware checks (Trigger.isInsert, Trigger.isUpdate etc.)
- No hardcoded IDs — use SOQL lookups or Custom Metadata
- Async pattern for any callouts (flag with comment if original used sync)
- Null-safe access — check Trigger.new and Trigger.old before use
- Meaningful method and variable names — no single-letter variables

The trigger body: single trigger, only the events present in original triggers, zero business logic, delegates entirely to the handler.

Write `force-app/main/default/triggers/{objectName}Trigger.trigger` (this file is small — write it in one step).

Then write the trigger metadata file `force-app/main/default/triggers/{objectName}Trigger.trigger-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexTrigger>
```

**Checkpoint 10a:**
```
CHECKPOINT 10a
✓ force-app/main/default/triggers/{objectName}Trigger.trigger
✓ force-app/main/default/triggers/{objectName}Trigger.trigger-meta.xml
```

---

## Step 11 — Generate File 2: Handler

Handler class rules:
- One public method per trigger context — only for events in the original triggers
- Static Boolean isRunning recursion guard at the top of the class
- Each method calls into {objectName}TriggerHelper for the actual logic
- Comment at top of each method listing source triggers and merged logic
- Logic merged in sequence per the Logic Merge Map in docs/trigger-audit-plan.md
- Duplicate logic: keep one copy, remove duplicates
- Conflicts: `// CONFLICT: {triggerA} sets X, {triggerB} sets Y — review`
- Async callouts: `// ASYNC REQUIRED: move to @future or Queueable`

**Write incrementally — one Write/Edit tool call per method. Never hold the entire class in memory before writing.**

Step 11a — Write the class opening to `force-app/main/default/classes/{objectName}TriggerHandler.cls` using the Write tool (header only, no methods yet):
```
public class {objectName}TriggerHandler {

    // Recursion guard
    private static Boolean isRunning = false;

    // Consolidated from: {list of original trigger names}
}
```
Print `HANDLER HEADER written`.

Step 11b — For each trigger context (only those present in original triggers, in order: Before Insert, After Insert, Before Update, After Update, Before Delete, After Delete, After Undelete):
1. Print to chat: `WRITING HANDLER METHOD: {context}`
2. Use the Edit tool to insert the fully-written method body **before the final closing `}`** in the file
3. Print: `HANDLER METHOD {context} written` before moving to the next

Then write the class metadata file `force-app/main/default/classes/{objectName}TriggerHandler.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

**Checkpoint 11a:**
```
CHECKPOINT 11a
✓ force-app/main/default/classes/{objectName}TriggerHandler.cls ({n} lines)
✓ force-app/main/default/classes/{objectName}TriggerHandler.cls-meta.xml
```

---

## Step 12 — Generate File 3: Helper

Helper class rules:
- All business logic lives here — fully ported from the original triggers
- One static method per event context matching what the handler calls
- All SOQL outside loops: collect IDs first, single query, map results back
- All DML outside loops: collect into list, single DML at the end
- Deduplicated: identical logic from multiple triggers appears once
- Inline comments on each block identifying its source trigger

**Write incrementally — one Write/Edit tool call per method. Never hold the entire class in memory before writing.**

Step 12a — Write the class opening to `force-app/main/default/classes/{objectName}TriggerHelper.cls` using the Write tool (header only):
```
public class {objectName}TriggerHelper {
}
```
Print `HELPER HEADER written`.

Step 12b — For each trigger context (only those present in original triggers):
1. Print to chat: `WRITING HELPER METHOD: handle{Context}`
2. Use the Edit tool to insert the fully-written static method **before the final closing `}`** in the file
3. Print: `HELPER METHOD handle{Context} written` before moving to the next

Then write the class metadata file `force-app/main/default/classes/{objectName}TriggerHelper.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

**Checkpoint 12a:**
```
CHECKPOINT 12a
✓ force-app/main/default/classes/{objectName}TriggerHelper.cls ({n} lines)
✓ force-app/main/default/classes/{objectName}TriggerHelper.cls-meta.xml
```

---

## Step 13 — Generate File 4: Test Class

Test class rules:
- @IsTest class with @TestSetup for shared test data
- One test method per original trigger's key scenario
- Bulk test for every DML context (200 records minimum)
- Assert on specific field values and record states — not generic existence checks
- Use Test.startTest() / Test.stopTest() in every test method

**Assertion rules — these are the only valid assertion forms. Never use any other:**

| Goal | Correct form | Never use |
|---|---|---|
| Value equals expected | `System.assertEquals(expected, actual, 'message')` | `Assert.areEqual` (requires v56+) |
| Condition is true | `System.assert(condition, 'message')` | `Assert.isTrue`, `assertTrue` |
| Condition is false | `System.assert(!condition, 'message')` | `System.assertFalse`, `Assert.isFalse` |
| Value is not null | `System.assertNotEquals(null, actual, 'message')` | `Assert.isNotNull` |
| Value is null | `System.assertEquals(null, actual, 'message')` | `Assert.isNull` |

`System.assertFalse` does not exist in Apex — always negate with `!` inside `System.assert`.

**Write incrementally — one Write/Edit tool call per test group. Never hold the entire class in memory before writing.**

Step 13a — Write the class opening + @TestSetup to `force-app/main/default/classes/{objectName}TriggerTest.cls` using the Write tool:
```
@IsTest
public class {objectName}TriggerTest {

    @TestSetup
    static void setup() {
        // {minimum required related records}
    }
}
```
Print `TEST SETUP written`.

Step 13b — For each original trigger's test group:
1. Print to chat: `WRITING TEST GROUP {n}/{total}: {sourceTriggerName}`
2. Use the Edit tool to insert the test group (single-record test + bulk test) **before the final closing `}`** in the file
3. Print: `TEST GROUP {n}/{total} written` before moving to the next

Each test group must follow this exact assertion pattern — no exceptions:
```apex
// Positive assertion
System.assertEquals(expectedValue, actualValue, 'message');

// Condition is true
System.assert(someCondition, 'message');

// Condition is false — ALWAYS negate with ! inside System.assert
System.assert(!someCondition, 'message');

// Not null
System.assertNotEquals(null, actualValue, 'message');
```

**NEVER write:** `System.assertFalse(...)`, `Assert.isFalse(...)`, `Assert.isTrue(...)`, `Assert.areEqual(...)`.
These do not exist in Apex or require API v56+ and will cause deploy errors.

Then write the class metadata file `force-app/main/default/classes/{objectName}TriggerTest.cls-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

**Checkpoint 13a:**
```
CHECKPOINT 13a
✓ force-app/main/default/classes/{objectName}TriggerTest.cls ({n} lines)
✓ force-app/main/default/classes/{objectName}TriggerTest.cls-meta.xml
```

---

## Step 14 — Dependent Components

Check the audit plan and trigger source code for any dependent components referenced that do not yet exist as local files.

### Custom Metadata Types (schema — not records)

If any trigger or helper class reads from a Custom Metadata type (e.g. `{TypeName}__mdt`), write the **type schema** — NOT a record file.

The type schema lives under `force-app/main/default/objects/{TypeName}__mdt/`:

**14a — Object definition** — write `force-app/main/default/objects/{TypeName}__mdt/{TypeName}__mdt.object-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>{TypeName}</label>
    <pluralLabel>{TypeName}s</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
```

**14b — One field file per custom field** — for each field the code reads, write `force-app/main/default/objects/{TypeName}__mdt/fields/{FieldName}__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>{FieldName}__c</fullName>
    <label>{FieldLabel}</label>
    <type>{FieldType}</type>
    <!-- add length/precision/referenceTo as needed for the type -->
</CustomField>
```

Do NOT write anything under `force-app/main/default/customMetadata/` — that folder holds data records, not schema. Records are managed in the org, not generated here.

Run `mkdir -p force-app/main/default/objects/{TypeName}__mdt/fields` before writing each type.

### Custom Labels

If any class references `System.Label.{LabelName}`, check `force-app/main/default/labels/CustomLabels.labels-meta.xml`. If the file does not exist, create it:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomLabels xmlns="http://soap.sforce.com/2006/04/metadata">
    <labels>
        <fullName>{LabelName}</fullName>
        <language>en_US</language>
        <protected>false</protected>
        <shortDescription>{LabelName}</shortDescription>
        <value>TODO: set label value</value>
    </labels>
</CustomLabels>
```
Run `mkdir -p force-app/main/default/labels` first.

### Custom Settings / Custom Objects

Do not generate these — flag for manual creation.

**Checkpoint 14a:**
```
CHECKPOINT 14a
Custom Metadata type schemas written: {list object paths or 'none'}
Custom Metadata field files written: {list field paths or 'none'}
Custom Labels written: {path or 'none'}
Flagged for manual creation: {list or 'none'}
```

---

## Step 15 — Final Summary

Print the complete file manifest:

```
CONSOLIDATION COMPLETE
✓ force-app/main/default/triggers/{objectName}Trigger.trigger
✓ force-app/main/default/triggers/{objectName}Trigger.trigger-meta.xml
✓ force-app/main/default/classes/{objectName}TriggerHandler.cls
✓ force-app/main/default/classes/{objectName}TriggerHandler.cls-meta.xml
✓ force-app/main/default/classes/{objectName}TriggerHelper.cls
✓ force-app/main/default/classes/{objectName}TriggerHelper.cls-meta.xml
✓ force-app/main/default/classes/{objectName}TriggerTest.cls
✓ force-app/main/default/classes/{objectName}TriggerTest.cls-meta.xml
{any dependent component files}
```

Then tell the user:
"Consolidation complete. All logic from the original triggers has been merged
into the scaffold following Apex best practices. Search for // CONFLICT and
// ASYNC REQUIRED comments — these are the only places that need manual review
before the code is production-ready."

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

## Step 2 — Discover and Filter Triggers on Object

> **Rules for this step and all retrieval steps below:**
> - Use Salesforce CLI commands only. Never use any MCP Salesforce tool for retrieval.
> - Use the Salesforce Metadata API (via `sf project retrieve start`) for all file retrieval — this ensures correct file syntax and structure on disk.
> - Ignore all managed package components. Any component with a non-empty `NamespacePrefix` is a managed package component and must be excluded before retrieval.

Query the org with the Tooling API to discover all active triggers on {objectName}:

```bash
sf data query \
  --query "SELECT Id, Name, NamespacePrefix, TableEnumOrId, UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate, UsageBeforeDelete, UsageAfterDelete, UsageAfterUndelete, Status FROM ApexTrigger WHERE TableEnumOrId = '{objectName}' AND Status = 'Active'" \
  --use-tooling-api --json
```

From the results, filter immediately:
- Keep only triggers where `NamespacePrefix` is null or empty — these are unmanaged triggers.
- Discard any trigger where `NamespacePrefix` is non-empty. These are managed package triggers and will not be retrieved, analyzed, or consolidated at any point in this workflow.

If no unmanaged triggers remain, tell the user:
"No active unmanaged triggers found on {objectName}. Please verify the object API name and confirm unmanaged triggers exist in the connected org."
Then stop.

Record the filtered list as **{triggerList}**. All remaining steps operate only on {triggerList}.

**Checkpoint 2 — print before continuing:**
```
CHECKPOINT 2
Object: {objectName}
Total active triggers found: {count}
Managed (ignored): {count} — {names + namespace prefix, or 'none'}
Unmanaged triggers in scope: {count}
{triggerList}: {names}
```

---

## Step 3 — Retrieve Triggers Locally via Metadata API

This step retrieves trigger source files into the local project using the Salesforce Metadata API so the correct `.trigger` and `.trigger-meta.xml` syntax is on disk.

Ask the user:

> "Ready to retrieve {count} ApexTrigger(s) for {objectName}:
>   {triggerList}
> Retrieve now? (YES / NO)"

If NO, stop.

Build one `--metadata` flag per name in {triggerList} and run:

```bash
sf project retrieve start \
  --metadata "ApexTrigger:{name1}" \
  --metadata "ApexTrigger:{name2}" \
  ...
```

The CLI writes files directly to `force-app/main/default/triggers/`. Do not create directories or write files manually.

After retrieval, verify the files exist on disk:

```bash
ls force-app/main/default/triggers/
```

**Checkpoint 3 — print before continuing:**
```
CHECKPOINT 3
Metadata type retrieved: ApexTrigger
Files stored in: force-app/main/default/triggers/
Retrieved: {list of .trigger filenames confirmed on disk}
Missing / not retrieved: {list or none}
```

---

## Step 4 — Identify Dependent Apex Classes and Retrieve by Type

Read the retrieved trigger files to identify every dependent Apex class — handlers, helpers, utilities, services, and test classes:

```bash
cat force-app/main/default/triggers/*.trigger
```

Collect every class name referenced via:
- Instantiation: `new ClassName()`
- Static call: `ClassName.method()`
- Test class naming convention: class names containing a trigger name + `Test`

Exclude any class from a managed package (any class whose name resolves to a namespaced component in the org). Managed classes that cannot be retrieved by the CLI will simply be absent from disk after retrieval — note them in the checkpoint.

If no classes are identified, print:
```
CHECKPOINT 4 — no dependent Apex classes found, skipping to Step 5
```
and continue.

Otherwise, present the class list and ask:

> "Found {count} dependent Apex class(es) for {objectName} triggers:
>   {classList}
> Retrieve now? (YES / NO)"

If NO, note that class bodies will not be available for analysis and continue to Step 5.

If YES:

```bash
sf project retrieve start \
  --metadata "ApexClass:{class1}" \
  --metadata "ApexClass:{class2}" \
  ...
```

The CLI writes files to `force-app/main/default/classes/`.

After retrieval, verify:

```bash
ls force-app/main/default/classes/
```

**Checkpoint 4 — print before continuing:**
```
CHECKPOINT 4
Metadata type retrieved: ApexClass
Files stored in: force-app/main/default/classes/
Retrieved: {count} — {names confirmed on disk}
Not retrieved (managed or missing): {list or none}
```

---

## Step 5 — Retrieve Remaining Dependent Components by Type

Scan all files retrieved so far to build a full dependency manifest before retrieving anything:

```bash
cat force-app/main/default/triggers/*.trigger force-app/main/default/classes/*.cls 2>/dev/null
```

Scan for references to these metadata types:

| Type | Pattern to look for |
|---|---|
| Custom Metadata | `{TypeName}__mdt` in SOQL or `.getInstance()` |
| Named Credentials | `callout:{name}` in endpoint strings |
| Static Resources | `Test.loadData(...)`, `'/resource/{name}'`, `PageReference('/resource/{name}')` |
| Custom Labels | `Label.{LabelName}`, `System.Label.{LabelName}` |
| Platform Events | `new {EventName}__e(...)`, `EventBus.publish(...)`, `FROM {EventName}__e` |
| Custom Settings | `{SettingName}__c.getInstance()`, `getOrgDefaults()`, `getValues(...)` |
| Email Templates | `setTemplateId(...)`, `Messaging.renderStoredEmailTemplate(...)` |
| Flows | `Flow.Interview.{FlowApiName}`, `new Flow.Interview.{FlowApiName}()` |

Print the full manifest before retrieving anything:
```
DEPENDENCY MANIFEST
Custom Metadata Types: {list or none}
Named Credentials: {list or none}
Static Resources: {list or none}
Custom Labels: {list or none}
Platform Events: {list or none}
Custom Settings: {list or none}
Email Templates: {list or none}
Flows: {list or none}
```

**Retrieve one metadata type at a time.** This avoids timeout issues caused by retrieving large mixed batches in a single call. For each type below, ask for user confirmation before running the retrieve command.

---

### Step 5a — Custom Metadata Types

If none found, print `CHECKPOINT 5a — no Custom Metadata Types referenced, skipping` and move to 5b.

Otherwise, ask:

> "Retrieve Custom Metadata Types: {list}?
> (Retrieves object schema + records. Recommended — required for trigger analysis.)
> Retrieve now? (YES / NO)"

If YES, retrieve **one type at a time** — schema first, then records:

```bash
# Object schema
sf project retrieve start --metadata "CustomObject:{TypeName}__mdt"

# Records
sf project retrieve start --metadata "CustomMetadata:{TypeName}__mdt"
```

Repeat for each type. The CLI writes schema to `force-app/main/default/objects/{TypeName}__mdt/` and records to `force-app/main/default/customMetadata/`. Do not write files manually.

**Checkpoint 5a:**
```
CHECKPOINT 5a — Custom Metadata Types
Retrieved: {list or none}
Schema: force-app/main/default/objects/
Records: force-app/main/default/customMetadata/
```

---

### Step 5b — Named Credentials

If none found, print `CHECKPOINT 5b — no Named Credentials referenced, skipping` and move to 5c.

Otherwise, ask:

> "Retrieve Named Credentials: {list}? (YES / NO)"

If YES:

```bash
sf project retrieve start \
  --metadata "NamedCredential:{name1}" \
  --metadata "NamedCredential:{name2}" \
  ...
```

Files stored in `force-app/main/default/namedCredentials/`.

**Checkpoint 5b:**
```
CHECKPOINT 5b — Named Credentials
Retrieved: {list or none}
Files: force-app/main/default/namedCredentials/
```

---

### Step 5c — Static Resources

If none found, print `CHECKPOINT 5c — no Static Resources referenced, skipping` and move to 5d.

Otherwise, ask:

> "Retrieve Static Resources: {list}? (YES / NO)"

If YES:

```bash
sf project retrieve start \
  --metadata "StaticResource:{name1}" \
  --metadata "StaticResource:{name2}" \
  ...
```

Files stored in `force-app/main/default/staticresources/`.

**Checkpoint 5c:**
```
CHECKPOINT 5c — Static Resources
Retrieved: {list or none}
Files: force-app/main/default/staticresources/
```

---

### Step 5d — Custom Labels

If none found, print `CHECKPOINT 5d — no Custom Labels referenced, skipping` and move to 5e.

Otherwise, ask:

> "Retrieve Custom Labels? (YES / NO)"

If YES:

```bash
sf project retrieve start --metadata "CustomLabels"
```

File stored at `force-app/main/default/labels/CustomLabels.labels-meta.xml`.

**Checkpoint 5d:**
```
CHECKPOINT 5d — Custom Labels
Retrieved: {YES / skipped}
File: force-app/main/default/labels/CustomLabels.labels-meta.xml
```

---

### Step 5e — Platform Events

If none found, print `CHECKPOINT 5e — no Platform Events referenced, skipping` and move to Step 6.

Otherwise, ask:

> "Retrieve Platform Event object definitions: {list}? (YES / NO)"

If YES, retrieve one event at a time:

```bash
sf project retrieve start --metadata "CustomObject:{EventName}__e"
```

Files stored in `force-app/main/default/objects/`. Note: only object definitions are retrieved — platform event channel subscriptions are managed in the org and are not scaffolded.

**Checkpoint 5e:**
```
CHECKPOINT 5e — Platform Events
Retrieved: {list or none}
Files: force-app/main/default/objects/
```

---

### Step 5f — Custom Settings

If none found, print `CHECKPOINT 5f — no Custom Settings referenced, skipping` and move to 5g.

Scan for: `{SettingName}__c.getInstance()`, `{SettingName}__c.getOrgDefaults()`, `{SettingName}__c.getValues(...)`.

Note: Custom Settings share the `__c` suffix with Custom Objects but are a distinct metadata type — only retrieve objects confirmed to be Custom Settings via the pattern above, not every `__c` reference.

Ask:

> "Retrieve Custom Settings: {list}? (YES / NO)"

If YES, retrieve one at a time:

```bash
sf project retrieve start --metadata "CustomObject:{SettingName}__c"
```

Files stored in `force-app/main/default/objects/{SettingName}__c/`.

**Checkpoint 5f:**
```
CHECKPOINT 5f — Custom Settings
Retrieved: {list or none}
Files: force-app/main/default/objects/
```

---

### Step 5g — Email Templates

If none found, print `CHECKPOINT 5g — no Email Templates referenced, skipping` and move to 5h.

Scan for: `setTemplateId(...)`, `Messaging.renderStoredEmailTemplate(...)`, `templateName` string literals matching a known template name pattern.

Note: Email Templates are stored in folders. The retrieve path is `EmailTemplate:{FolderName}/{TemplateName}`. If the folder name is not identifiable from the code, flag the template for manual retrieval.

Ask:

> "Retrieve Email Templates: {list}? (YES / NO)"

If YES:

```bash
sf project retrieve start \
  --metadata "EmailTemplate:{FolderName1}/{TemplateName1}" \
  --metadata "EmailTemplate:{FolderName2}/{TemplateName2}" \
  ...
```

Files stored in `force-app/main/default/email/{FolderName}/`.

For any template where the folder cannot be determined from the code, print:
`SKIPPED: {TemplateName} — folder name unknown, retrieve manually`

**Checkpoint 5g:**
```
CHECKPOINT 5g — Email Templates
Retrieved: {list or none}
Skipped (folder unknown): {list or none}
Files: force-app/main/default/email/
```

---

### Step 5h — Flows Invoked from Apex

If none found, print `CHECKPOINT 5h — no Flows referenced, skipping` and move to the overall Step 5 checkpoint.

Scan for: `Flow.Interview.{FlowApiName}`, `new Flow.Interview.{FlowApiName}()`, `Database.executeBatch` with a flow class name, and `Invocable` method references that resolve to a flow name.

Ask:

> "Retrieve Flows: {list}? (YES / NO)"

If YES:

```bash
sf project retrieve start \
  --metadata "Flow:{FlowApiName1}" \
  --metadata "Flow:{FlowApiName2}" \
  ...
```

Files stored in `force-app/main/default/flows/`.

**Checkpoint 5h:**
```
CHECKPOINT 5h — Flows
Retrieved: {list or none}
Files: force-app/main/default/flows/
```

---

**Checkpoint 5 — print after all types are processed:**
```
CHECKPOINT 5 — ALL DEPENDENT COMPONENTS RETRIEVED
Custom Metadata Types: {list or skipped}
Named Credentials: {list or skipped}
Static Resources: {list or skipped}
Custom Labels: {retrieved / skipped}
Platform Events: {list or skipped}
Custom Settings: {list or skipped}
Email Templates: {list or skipped}
Flows: {list or skipped}
All files stored locally and ready for trigger analysis in Step 6
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

Run the following Salesforce CLI shell command to concatenate the seven section files directly on disk — do not read them into memory first:

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

## Step 9 — Scaffold All Files via CLI

Only proceed if the user replied YES.

Read docs/trigger-audit-plan.md to pick up any edits the user made.

Use `sf apex generate` to scaffold all four files. The CLI reads `sourceApiVersion` from `sfdx-project.json` automatically and creates both the source file and its companion `-meta.xml` in one command. Do not create directories or write metadata files manually.

Run all four scaffold commands:

```bash
sf apex generate trigger --name {objectName}Trigger --sobject {objectName} --output-dir force-app/main/default/triggers

sf apex generate class --name {objectName}TriggerHandler --output-dir force-app/main/default/classes

sf apex generate class --name {objectName}TriggerHelper --output-dir force-app/main/default/classes

sf apex generate class --name {objectName}TriggerTest --output-dir force-app/main/default/classes
```

Each command creates two files: the source file and its `-meta.xml`. Do not touch the `-meta.xml` files — they are complete as generated.

**Checkpoint 9:**
```
CHECKPOINT 9
Scaffolded (CLI):
✓ force-app/main/default/triggers/{objectName}Trigger.trigger
✓ force-app/main/default/triggers/{objectName}Trigger.trigger-meta.xml
✓ force-app/main/default/classes/{objectName}TriggerHandler.cls
✓ force-app/main/default/classes/{objectName}TriggerHandler.cls-meta.xml
✓ force-app/main/default/classes/{objectName}TriggerHelper.cls
✓ force-app/main/default/classes/{objectName}TriggerHelper.cls-meta.xml
✓ force-app/main/default/classes/{objectName}TriggerTest.cls
✓ force-app/main/default/classes/{objectName}TriggerTest.cls-meta.xml
```

---

## Step 10 — Populate Trigger Body

Apply all Apex best practices:
- One trigger per object, no logic in the trigger body
- Only the event contexts present in the original triggers
- Zero business logic — delegates entirely to the handler
- Context-aware checks (Trigger.isInsert, Trigger.isUpdate etc.)
- Null-safe access — check Trigger.new and Trigger.old before use

Use the Edit tool to replace the generated body of `force-app/main/default/triggers/{objectName}Trigger.trigger` with the consolidated trigger. This file is small — replace it in one Edit call.

Do not touch `{objectName}Trigger.trigger-meta.xml`.

**Checkpoint 10:**
```
CHECKPOINT 10
✓ {objectName}Trigger.trigger — body populated
```

---

## Step 11 — Populate Handler Class

Handler class rules:
- One public method per trigger context — only for events in the original triggers
- Static Boolean isRunning recursion guard at the top of the class
- Each method delegates to {objectName}TriggerHelper
- Logic merged in sequence per the Logic Merge Map in docs/trigger-audit-plan.md
- Duplicate logic: keep one copy, remove duplicates
- Conflicts: `// CONFLICT: {triggerA} sets X, {triggerB} sets Y — review`
- Async callouts: `// ASYNC REQUIRED: move to @future or Queueable`

**Populate incrementally — one Edit call per method. Never hold the entire class in memory.**

Step 11a — Use the Edit tool to replace the generated class body of `{objectName}TriggerHandler.cls` with the class header (recursion guard, no methods yet):
```apex
public class {objectName}TriggerHandler {

    // Recursion guard
    private static Boolean isRunning = false;

    // Consolidated from: {list of original trigger names}
}
```
Print `HANDLER HEADER written`.

Step 11b — For each trigger context (only those present in original triggers, in order: Before Insert, After Insert, Before Update, After Update, Before Delete, After Delete, After Undelete):
1. Print: `WRITING HANDLER METHOD: {context}`
2. Use the Edit tool to insert the fully-written method body before the final closing `}`
3. Print: `HANDLER METHOD {context} written` before moving to the next

Do not touch `{objectName}TriggerHandler.cls-meta.xml`.

**Checkpoint 11:**
```
CHECKPOINT 11
✓ {objectName}TriggerHandler.cls — {n} methods populated
```

---

## Step 12 — Populate Helper Class

Helper class rules:
- All business logic lives here — fully ported from the original triggers
- One static method per event context matching what the handler calls
- All SOQL outside loops: collect IDs first, single query, map results back
- All DML outside loops: collect into list, single DML at the end
- Deduplicated: identical logic from multiple triggers appears once
- Inline comments on each block identifying its source trigger

**Populate incrementally — one Edit call per method. Never hold the entire class in memory.**

Step 12a — Use the Edit tool to replace the generated class body of `{objectName}TriggerHelper.cls` with the class header only:
```apex
public class {objectName}TriggerHelper {
}
```
Print `HELPER HEADER written`.

Step 12b — For each trigger context (only those present in original triggers):
1. Print: `WRITING HELPER METHOD: handle{Context}`
2. Use the Edit tool to insert the fully-written static method before the final closing `}`
3. Print: `HELPER METHOD handle{Context} written` before moving to the next

Do not touch `{objectName}TriggerHelper.cls-meta.xml`.

**Checkpoint 12:**
```
CHECKPOINT 12
✓ {objectName}TriggerHelper.cls — {n} methods populated
```

---

## Step 13 — Populate Test Class

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

**Populate incrementally — one Edit call per test group. Never hold the entire class in memory.**

Step 13a — Use the Edit tool to replace the generated class body of `{objectName}TriggerTest.cls` with the class header + @TestSetup:
```apex
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
1. Print: `WRITING TEST GROUP {n}/{total}: {sourceTriggerName}`
2. Use the Edit tool to insert the test group (single-record test + bulk test) before the final closing `}`
3. Print: `TEST GROUP {n}/{total} written` before moving to the next

**NEVER write:** `System.assertFalse(...)`, `Assert.isFalse(...)`, `Assert.isTrue(...)`, `Assert.areEqual(...)`.

Do not touch `{objectName}TriggerTest.cls-meta.xml`.

**Checkpoint 13:**
```
CHECKPOINT 13
✓ {objectName}TriggerTest.cls — {n} test groups populated
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

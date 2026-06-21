# Salesforce Trigger Consolidation — Agentforce Skills & Workflows

A set of Agentforce skills, workflows, and documentation for auditing and consolidating multiple Apex triggers on a Salesforce object into a single, best-practice trigger handler pattern. Built for use with the Agentforce VS Code extension.

---

## What's Included

| Path | Description |
|------|-------------|
| `.a4drules/skills/apex-trigger-risk-scan.md` | Skill: analyzes a single trigger across 7 risk dimensions and outputs a compact scan block |
| `.a4drules/skills/apex-trigger-consolidation-analysis.md` | Skill: analyzes all triggers on an object together across 8 cross-trigger dimensions and produces the full risk register |
| `.a4drules/workflows/trigger-consolidation.md` | Workflow: end-to-end orchestration — retrieves triggers from org, runs both skills, writes an audit plan, and generates the consolidated scaffold |
| `docs` | Example audit output for a object and an overall risk score of 10/10 |

---

## Prerequisites

- [Agentforce VS Code Extension](https://marketplace.visualstudio.com/items?itemName=salesforce.salesforcedx-vscode-agentforce) installed
- Salesforce CLI (`sf`) installed and authenticated to your org

---

## Setup

**1. Clone this repo**

```bash
git clone https://github.com/anushamyneni1/apexTriggerConsolidation.git
cd apexTriggerConsolidation
```

**2. Copy the skills and workflow into your Salesforce project**

```bash
cp -r /path/to/cloned/repo/.a4drules/ /path/to/your/salesforce/project/
```
Note: Replace `/path/to/cloned/repo/` with where you cloned the repo, and `/path/to/your/salesforce/project/` with your Salesforce project root.

The Agentforce extension picks up skills and workflows automatically from the `.a4drules/` directory at the root of your project.

---

### Alternative: install script

If you'd prefer a script instead of a manual copy, `install.sh` is included in this repo. **Read it before running** — it downloads files from GitHub and writes them into your project.

```bash
# Review the script first
cat /path/to/cloned/repo/install.sh

# Then run it from the root of your Salesforce project
bash /path/to/apexTriggerConsolidation/install.sh
```

The script does the following:

```bash
#!/bin/bash

REPO="https://raw.githubusercontent.com/anushamyneni1/apexTriggerConsolidation/main"
TARGET=".a4drules"

mkdir -p "$TARGET/skills" "$TARGET/workflows"

curl -sSL "$REPO/.a4drules/skills/apex-trigger-risk-scan.md"                 -o "$TARGET/skills/apex-trigger-risk-scan.md"
curl -sSL "$REPO/.a4drules/skills/apex-trigger-consolidation-analysis.md"    -o "$TARGET/skills/apex-trigger-consolidation-analysis.md"
curl -sSL "$REPO/.a4drules/workflows/trigger-consolidation.md"               -o "$TARGET/workflows/trigger-consolidation.md"
```

> **Do not pipe this directly from a remote URL** (`curl ... | bash`).
> Download or clone the repo first so you can inspect the script before it runs.

---

## Usage

Open the Agentforce panel in VS Code inside your Salesforce project and invoke the **`trigger-consolidation`** workflow. The workflow runs end-to-end and handles everything.

### How the workflow runs

**Step 1 — Target object**
The agent asks which Salesforce object to consolidate. Provide the API name (e.g. `Opportunity`, `Case`, `Invoice__c`).

**Step 2 — Retrieve from org**
The agent queries your org via the Salesforce CLI to retrieve:
- All active unmanaged Apex triggers on the object (managed/namespaced triggers are excluded)
- All dependent handler and helper classes
- Any Custom Metadata Type records referenced in the trigger code
- Active Flows and Process Builders on the object (used for automation re-entry analysis)

All source is saved locally to `force-app/main/default/` before analysis begins.

**Step 3 — Risk analysis (two passes)**
- **Pass 1:** Applies `apex-trigger-risk-scan` to each trigger one at a time. The agent pauses between triggers and asks if you want to continue.
- **Pass 2:** Applies `apex-trigger-consolidation-analysis` across all triggers together, producing the full risk register across all 16 dimensions.

**Step 4 — Audit plan**
The agent writes `docs/trigger-audit-plan.md` with the trigger inventory, risk register, dependency graph, logic merge map, best practices compliance table, and phased consolidation plan. It then pauses and asks:

> Reply **YES** to generate the consolidated scaffold.
> Reply **NO** to stop here and use the plan document only.

**Step 5 — Code generation (YES only)**
The agent reads your (optionally edited) audit plan and generates four files into your SFDX project following Apex best practices.

---

## Generated Files

When you reply YES in Step 4, the workflow writes:

| File | Description |
|------|-------------|
| `force-app/main/default/triggers/{Object}Trigger.trigger` | Single consolidated trigger — no business logic, delegates entirely to the handler |
| `force-app/main/default/classes/{Object}TriggerHandler.cls` | One method per trigger context; includes recursion guard and bypass mechanism |
| `force-app/main/default/classes/{Object}TriggerHelper.cls` | All business logic, fully bulkified, sourced and labeled from original triggers |
| `force-app/main/default/classes/{Object}TriggerTest.cls` | @IsTest class with single-record and 200-record bulk tests for every merged logic block |

The generated code is annotated with comment markers for anything that needs manual review before production:

| Marker | Meaning |
|--------|---------|
| `// CONFLICT` | Opposing logic between two original triggers |
| `// ASYNC REQUIRED` | Original trigger used a synchronous callout |
| `// CONTEXT BOUNDARY FIX` | Logic was in the wrong before/after context |
| `// BYPASS: review` | Bypass mechanisms were inconsistent across triggers |

---

## Risk Dimensions

Analysis runs across 16 dimensions split between the two skills.

### Per-trigger scan (7 dimensions — `apex-trigger-risk-scan`)

| # | Dimension | What it checks |
|---|-----------|----------------|
| 1 | Execution Order Risk | Flags assumptions the trigger makes about running before or after another specific trigger — comments, field reads that depend on values another trigger should set first |
| 2 | Recursion Traps | Flags absence of a static Boolean recursion guard when DML is present — CRITICAL if no guard and DML exists, HIGH if no guard only |
| 3 | Governor Limit Exposure | Scans for SOQL inside loops (CRITICAL), DML inside loops (CRITICAL), synchronous HTTP callouts in trigger context (HIGH), aggregate queries without LIMIT (MEDIUM) |
| 4 | Before/After Context Boundary | Maps which contexts the trigger fires in and flags misplaced logic — field assignments in after context (silently lost), DML on triggering record in before context (causes recursion) |
| 5 | Bypass Mechanism | Looks for kill-switch patterns — Custom Setting/Metadata checks, permission-based skips, static Boolean flags set externally — notes absence as well as presence |
| 6 | Static Variable Inventory | Lists every static variable in handler/helper classes, flags generic names (`isRunning`, `processed`) that collide with the same name in another trigger's class after consolidation |
| 7 | Exception and Error Handling Behavior | Scans for `addError()` calls, silent catch blocks (catch with no rethrow/logging), and thrown exceptions that roll back the full transaction |

### Cross-trigger analysis (8 dimensions — `apex-trigger-consolidation-analysis`)

| # | Dimension | What it checks |
|---|-----------|----------------|
| 8 | Logic Overlap | Compares all triggers and flags the same field assigned in multiple triggers, identical validation logic, and the same helper method called from multiple triggers |
| 9 | Conflicting Logic | Flags contradictions across triggers on the same event — opposing field values, one trigger nulling a field another reads, mutually exclusive conditionals, read-after-write dependencies |
| 10 | Helper Class Coupling | Maps helper/utility classes to dependent triggers — any class used by 2+ triggers is a consolidation risk since modifying it can break all callers |
| 11 | Test Coverage Gaps | Per trigger: whether a `*Test` class exists, coverage below 85%, absence of a bulk test with 200+ records |
| 12 | Static Variable Collision | Cross-references static variable inventories from all per-trigger scans and identifies name collisions — two classes with the same static variable name share JVM-level state after consolidation, corrupting recursion guards |
| 13 | Bypass Consolidation Strategy | Assesses whether bypass mechanisms can be unified — compatible bypasses merge into one; inconsistent bypasses require per-method flags; triggers with no bypass that inherit a unified bypass unintentionally are flagged |
| 14 | Automation Re-entry Risk | Identifies Flows, Process Builders, or Workflow Field Updates that can commit DML re-firing Apex triggers mid-transaction, and flags `@future`/`Queueable`/Platform Event calls that could loop back |
| 15 | Cumulative Governor Limit Budget | Sums SOQL, DML, and heap consumption across all triggers to surface compound risk invisible per-trigger — flags when the combined estimate approaches Salesforce limits even if no single trigger is problematic alone |

---

## Risk Scoring Guide

| Score | Meaning |
|-------|---------|
| 1–3 | Low — safe to consolidate with minimal prep |
| 4–6 | Medium — refactor required before merge |
| 7–9 | High — urgent action recommended |
| 10 | Critical — production incident likely without immediate action |

---

## Consolidation Approach

The workflow enforces a three-phase consolidation plan written into the audit document:

| Phase | Goal |
|-------|------|
| Phase 1 — Refactor Before Merging | Fix all governor limit violations, recursion issues, hardcoded IDs, and synchronous callouts in the original triggers before any merge happens |
| Phase 2 — Merge and Consolidate | Follow the Logic Merge Map in the audit plan to merge all trigger logic into the handler and helper in dependency order |
| Phase 3 — Validate and Clean Up | Run and verify the test class, confirm recursion guard and bypass mechanism work, deactivate original triggers after sandbox sign-off |

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
git clone https://github.com/amyneni1/triggerConsolidation.git
cd triggerConsolidation
```

**2. Copy the skills and workflow into your Salesforce project**

```bash
cp -r .a4drules/ /path/to/your/salesforce/project/
```

The Agentforce extension picks up skills and workflows automatically from the `.a4drules/` directory at the root of your project.

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

| # | Dimension |
|---|-----------|
| 1 | Execution Order Risk |
| 2 | Recursion Traps |
| 3 | Governor Limit Exposure |
| 4 | Before/After Context Boundary |
| 5 | Bypass Mechanism |
| 6 | Static Variable Inventory |
| 7 | Exception and Error Handling Behavior |

### Cross-trigger analysis (8 dimensions — `apex-trigger-consolidation-analysis`)

| # | Dimension |
|---|-----------|
| 8 | Logic Overlap |
| 9 | Conflicting Logic |
| 10 | Helper Class Coupling |
| 11 | Test Coverage Gaps |
| 12 | Static Variable Collision |
| 13 | Bypass Consolidation Strategy |
| 14 | Automation Re-entry Risk |
| 15 | Cumulative Governor Limit Budget |

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

# Salesforce Trigger Consolidation — Agentforce Skills & Workflows

A set of Agentforce skills, workflows, and documentation for auditing and consolidating multiple Apex triggers on a Salesforce object into a single, best-practice trigger handler pattern. Built for use with the Agentforce VS Code extension.

---

## What's Included

| Path | Description |
|------|-------------|
| `.a4drules/skills/apex-trigger-analysis.md` | Skill: analyzes triggers across 6 risk dimensions and produces a structured risk report |
| `.a4drules/skills/trigger-consolidation.md` | Skill: produces a phased consolidation plan and generates consolidated trigger + handler code |
| `docs/trigger-audit-plan.md` | Example audit output for a Case object with 2 triggers |

---

## Prerequisites

- [Agentforce VS Code Extension](https://marketplace.visualstudio.com/items?itemName=salesforce.salesforcedx-vscode-agentforce) installed
- A Salesforce org with the triggers you want to consolidate

---

## Setup

**1. Clone this repo**

```bash
git clone https://github.com/amyneni1/triggerConsolidation.git
cd triggerConsolidation
```

**2. Copy the skills into your Salesforce project**

```bash
cp -r .a4drules/ /path/to/your/salesforce/project/
```

The Agentforce extension picks up skills and workflows automatically from the `.a4drules/` directory at the root of your project.

---

## Usage

Open the Agentforce panel in VS Code inside your Salesforce project.

**Audit triggers on an object:**

Invoke the `apex-trigger-analysis` skill. Paste in your trigger source code when prompted. The agent analyzes it across 6 dimensions:

1. Execution order risk
2. Recursion traps
3. Governor limit exposure
4. Logic overlap
5. Helper class coupling
6. Test coverage gaps

Each finding is scored and added to a risk register with a recommendation.

**Consolidate triggers:**

Invoke the `trigger-consolidation` skill. The agent uses the audit findings to produce:

- A phased consolidation plan
- A single consolidated `<Object>Trigger.trigger` file
- A `<Object>TriggerHandler.cls` with one method per event context
- A `<Object>TriggerTest.cls` with bulk test scenarios

---

## Risk Scoring Guide

| Score | Meaning |
|-------|---------|
| 1–3 | Low — safe to consolidate with minimal prep |
| 4–6 | Medium — refactor required before merge |
| 7–9 | High — urgent action recommended |
| 10 | Critical — production incident likely without immediate action |

---

## Example Output

See [docs/trigger-audit-plan.md](docs/trigger-audit-plan.md) for a full worked example auditing two Case triggers with an overall risk score of 6/10.

---

## Consolidation Approach

The skills enforce a four-phase approach:

| Phase | Goal |
|-------|------|
| Phase 1 | Unblock — retrieve any hidden or managed trigger source |
| Phase 2 | Refactor — fix governor limit violations before merging |
| Phase 3 | Merge — create one trigger + one handler covering all events |
| Phase 4 | Validate — run tests, verify bulk scenarios, deactivate originals |

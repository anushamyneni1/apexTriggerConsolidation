#!/bin/bash

REPO="https://raw.githubusercontent.com/anushamyneni1/apexTriggerConsolidation/main"
TARGET=".a4drules"

echo "Installing Apex Trigger Consolidation skills and workflows..."

mkdir -p "$TARGET/skills" "$TARGET/workflows"

curl -sSL "$REPO/.a4drules/skills/apex-trigger-risk-scan.md" -o "$TARGET/skills/apex-trigger-risk-scan.md"
curl -sSL "$REPO/.a4drules/skills/apex-trigger-consolidation-analysis.md" -o "$TARGET/skills/apex-trigger-consolidation-analysis.md"
curl -sSL "$REPO/.a4drules/workflows/trigger-consolidation.md" -o "$TARGET/workflows/trigger-consolidation.md"

echo "Done. Files installed to .a4drules/"
echo "Open the Agentforce panel in VS Code to use them."

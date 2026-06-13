#!/bin/bash

REPO="https://raw.githubusercontent.com/anushamyneni1/apexTriggerConsolidation/main"
TARGET=".a4drules"

echo "Installing Apex Trigger Consolidation skills and workflows..."

mkdir -p "$TARGET/skills" "$TARGET/workflows"

curl -sSL "$REPO/.a4drules/skills/apex-trigger-analysis.md" -o "$TARGET/skills/apex-trigger-analysis.md"
curl -sSL "$REPO/.a4drules/skills/trigger-consolidation.md" -o "$TARGET/skills/trigger-consolidation.md"

echo "Done. Skills installed to .a4drules/skills/"
echo "Open the Agentforce panel in VS Code to use them."

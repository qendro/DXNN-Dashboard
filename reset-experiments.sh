#!/bin/bash
# Reset experiment links to empty state

EXPERIMENTS_FILE="dxnn_analyzer_web/data/experiments.json"

echo "Resetting experiment links..."

if [ -f "$EXPERIMENTS_FILE" ]; then
    echo '{"experiments":[]}' > "$EXPERIMENTS_FILE"
    echo "✓ Experiment links reset successfully"
    echo "  File: $EXPERIMENTS_FILE"
    echo ""
    echo "Restart the dashboard to see changes:"
    echo "  docker-compose restart"
else
    echo "✗ File not found: $EXPERIMENTS_FILE"
    echo "  Creating new file..."
    mkdir -p "$(dirname "$EXPERIMENTS_FILE")"
    echo '{"experiments":[]}' > "$EXPERIMENTS_FILE"
    echo "✓ Created new experiments file"
fi

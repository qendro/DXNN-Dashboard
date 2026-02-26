#!/bin/bash

echo "🚀 Starting NEAT Training Dashboard..."
echo ""

# Check if Flask is installed
if ! python3 -c "import flask" 2>/dev/null; then
    echo "📦 Installing Flask..."
    pip3 install -r requirements.txt
fi

# Start the dashboard
python3 dashboard.py

#!/bin/bash

echo "🐳 Starting NEAT Dashboard in Docker..."
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop first."
    exit 1
fi

# Check if logs directory exists
if [ ! -d "logs" ]; then
    echo "⚠️  Warning: logs directory not found!"
    echo "Creating empty logs directory..."
    mkdir -p logs/Benchmarker logs/exp_runner logs/System
fi

# Build and start the container
echo "📦 Building Docker image..."
docker-compose build

echo ""
echo "🚀 Starting dashboard container..."
docker-compose up -d

echo ""
echo "✅ Dashboard is starting!"
echo ""
echo "📊 Access dashboard at: http://localhost:5001"
echo ""
echo "Useful commands:"
echo "  View logs:    docker-compose logs -f"
echo "  Stop:         docker-compose down"
echo "  Restart:      docker-compose restart"
echo "  Status:       docker-compose ps"
echo ""

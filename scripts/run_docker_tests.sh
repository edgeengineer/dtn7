#!/bin/bash
# Script to run DTN7 tests using Docker Compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to cleanup containers
cleanup() {
    print_info "Cleaning up containers..."
    cd "${PROJECT_ROOT}/docker/compose"
    docker-compose -f 3-node-linear.yml down -v 2>/dev/null || true
    docker-compose -f epidemic-test.yml down -v 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Change to compose directory
cd "${PROJECT_ROOT}/docker/compose"

# Test 1: 3-node linear topology
print_info "Starting 3-node linear topology test..."
docker-compose -f 3-node-linear.yml up -d --build

# Wait for nodes to start
print_info "Waiting for nodes to initialize..."
sleep 10

# Check node health
print_info "Checking node health..."
for i in 1 2 3; do
    if curl -s -f "http://localhost:300${i}/status" > /dev/null; then
        print_info "Node ${i} is healthy"
    else
        print_error "Node ${i} is not responding"
        exit 1
    fi
done

# Test bundle transmission from node1 to node3
print_info "Testing bundle transmission from node1 to node3..."
docker exec dtn-node1 dtnsend --sender dtn://node1/test --receiver dtn://node3/incoming <<< "Test message from node1"

# Wait for bundle to propagate
sleep 5

# Check if bundle was received (would need to implement bundle query endpoint)
print_info "Bundle transmission test completed"

# Bring down 3-node test
docker-compose -f 3-node-linear.yml down -v

print_info "All tests completed successfully!"
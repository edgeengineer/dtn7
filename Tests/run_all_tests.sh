#!/bin/bash
# Run all DTN7 Swift shell tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0
SKIPPED=0

# Function to run a test
run_test() {
    local TEST_NAME=$1
    local TEST_SCRIPT=$2
    
    echo -e "\n${YELLOW}Running test: $TEST_NAME${NC}"
    echo "========================================"
    
    if [ ! -f "$TEST_SCRIPT" ]; then
        echo -e "${YELLOW}SKIPPED${NC} - Test script not found: $TEST_SCRIPT"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    
    if [ ! -x "$TEST_SCRIPT" ]; then
        echo -e "${YELLOW}SKIPPED${NC} - Test script not executable: $TEST_SCRIPT"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    
    # Run the test
    if $TEST_SCRIPT; then
        echo -e "${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAILED${NC}"
        FAILED=$((FAILED + 1))
    fi
}

# Run all tests
echo "DTN7 Swift Test Suite"
echo "===================="

# Basic functionality tests
run_test "Local Ping/Echo" "$SCRIPT_DIR/local_ping_echo.sh"
run_test "Bundle Lifetime" "$SCRIPT_DIR/lifetime.sh"
run_test "Store Delete" "$SCRIPT_DIR/store_delete.sh"

# Routing tests
run_test "Static Routing" "$SCRIPT_DIR/routing_static.sh"
run_test "Epidemic Routing" "$SCRIPT_DIR/erouting_epidemic.sh"
run_test "Spray and Wait" "$SCRIPT_DIR/routing_saw.sh"

# CLA tests
run_test "External CLA" "$SCRIPT_DIR/ecla_test.sh"
run_test "CLA Chain" "$SCRIPT_DIR/cla_chain_test.sh"

# Multi-node tests
run_test "Local Nodes DTN" "$SCRIPT_DIR/local_nodes_dtn.sh"
run_test "External Peer Management" "$SCRIPT_DIR/ext_peer_management.sh"

# Summary
echo -e "\n========================================"
echo "Test Summary:"
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
#!/bin/bash
# Shell test library for DTN7 Swift - adapted from dtn7-rs

echo "==> $(basename $0)"

# Function to prepare binaries and test environment
function prepare_test() {
    if [ -z "$BUILD_MODE" ]; then
        export BUILD_MODE=release
    fi

    echo "Building Swift binaries in $BUILD_MODE mode..."
    if [ "$BUILD_MODE" = "debug" ]; then
        swift build --product dtnd
        swift build --product dtnsend
        swift build --product dtnrecv
        swift build --product dtnquery
        swift build --product dtntrigger
    else
        swift build -c release --product dtnd
        swift build -c release --product dtnsend
        swift build -c release --product dtnrecv
        swift build -c release --product dtnquery
        swift build -c release --product dtntrigger
    fi

    if [ $? -ne 0 ]; then
        echo "Build failed."
        exit 1
    fi

    export DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    export PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export BINS="$PROJECT_ROOT/.build/$BUILD_MODE"
    
    # Create temp directory for test data
    export TEST_DATA_DIR=$(mktemp -d /tmp/dtn7-test.XXXXXX)
    echo "Test data directory: $TEST_DATA_DIR"
}

# Function to wait for key press (for interactive debugging)
function wait_for_key {
    if [[ $1 = "-k" ]]; then
        echo "Press any key to stop daemons and clean up logs"
        read -n 1
    else
        echo
        echo "Provide -k as parameter to keep session running."
        echo
    fi
}

# Node counter for unique port assignment
CURNODE=1

# Get current port based on node number
function get_current_port {
    echo $((CURNODE - 1 + 3000))
}

# Start a DTN daemon
function start_dtnd {
    local NODE_NUM=$CURNODE
    local OUT_NODE=$(mktemp $TEST_DATA_DIR/node$NODE_NUM.out.XXXXXX)
    local PORT_NODE=$((NODE_NUM - 1 + 3000))
    local WORKDIR="$TEST_DATA_DIR/node$NODE_NUM"
    
    mkdir -p "$WORKDIR"
    
    # Build command with all arguments
    local CMD="$BINS/dtnd -w $PORT_NODE --workdir $WORKDIR $@"
    
    echo "Starting node$NODE_NUM: $CMD"
    $CMD > "$OUT_NODE" 2>&1 &
    local PID_NODE=$!
    
    echo "node$NODE_NUM pid: $PID_NODE"
    echo "node$NODE_NUM out: $OUT_NODE"
    echo "node$NODE_NUM port: $PORT_NODE"
    echo "node$NODE_NUM workdir: $WORKDIR"
    
    FILES="$FILES $OUT_NODE"
    PIDS="$PIDS $PID_NODE"
    NODES["node$NODE_NUM"]=$PID_NODE
    PORTS["node$NODE_NUM"]=$PORT_NODE
    
    # Wait for daemon to be ready
    wait_for_daemon_ready $PORT_NODE
    
    CURNODE=$((CURNODE + 1))
}

# Wait for daemon to be ready by checking HTTP endpoint
function wait_for_daemon_ready {
    local PORT=$1
    local MAX_ATTEMPTS=30
    local ATTEMPT=0
    
    echo -n "Waiting for daemon on port $PORT to be ready"
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if curl -s -f "http://localhost:$PORT/status" > /dev/null 2>&1; then
            echo " OK"
            return 0
        fi
        echo -n "."
        sleep 0.5
        ATTEMPT=$((ATTEMPT + 1))
    done
    
    echo " TIMEOUT"
    echo "Daemon on port $PORT failed to start!"
    return 1
}

# Start a background task (like dtnecho, dtnrecv, etc.)
function start_task {
    local NAME=$1
    shift
    local OUT_TASK=$(mktemp $TEST_DATA_DIR/$NAME.out.XXXXXX)
    
    echo "Starting task $NAME: $BINS/$@"
    "$BINS/$@" > "$OUT_TASK" 2>&1 &
    local PID_TASK=$!
    
    echo "$NAME pid: $PID_TASK"
    echo "$NAME out: $OUT_TASK"
    
    FILES="$FILES $OUT_TASK"
    PIDS="$PIDS $PID_TASK"
    TASKS["$NAME"]=$PID_TASK
    
    return 0
}

# Send a bundle using dtnsend
function send_bundle {
    local SENDER=$1
    local RECEIVER=$2
    local PAYLOAD=$3
    shift 3
    
    echo "Sending bundle from $SENDER to $RECEIVER with payload: $PAYLOAD"
    echo "$PAYLOAD" | "$BINS/dtnsend" -s "$SENDER" -r "$RECEIVER" $@
}

# Check if a bundle was received
function check_bundle_received {
    local ENDPOINT=$1
    local EXPECTED_PAYLOAD=$2
    local TIMEOUT=${3:-5}
    
    echo "Checking for bundle at $ENDPOINT containing: $EXPECTED_PAYLOAD"
    
    # Start dtnrecv in background
    local RECV_OUT=$(mktemp $TEST_DATA_DIR/recv.out.XXXXXX)
    timeout $TIMEOUT "$BINS/dtnrecv" -e "$ENDPOINT" > "$RECV_OUT" 2>&1
    
    if grep -q "$EXPECTED_PAYLOAD" "$RECV_OUT"; then
        echo "Bundle received successfully!"
        rm "$RECV_OUT"
        return 0
    else
        echo "Bundle NOT received!"
        echo "Output was:"
        cat "$RECV_OUT"
        rm "$RECV_OUT"
        return 1
    fi
}

# Wait for peers to connect
function wait_for_peers {
    local PORT=$1
    local EXPECTED_COUNT=$2
    local MAX_ATTEMPTS=60
    local ATTEMPT=0
    
    echo -n "Waiting for $EXPECTED_COUNT peers on port $PORT"
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        local PEER_COUNT=$(curl -s "http://localhost:$PORT/peers" 2>/dev/null | grep -o '"eid"' | wc -l)
        if [ "$PEER_COUNT" -ge "$EXPECTED_COUNT" ]; then
            echo " OK ($PEER_COUNT peers)"
            return 0
        fi
        echo -n "."
        sleep 0.5
        ATTEMPT=$((ATTEMPT + 1))
    done
    
    echo " TIMEOUT"
    echo "Expected $EXPECTED_COUNT peers but found $PEER_COUNT"
    return 1
}

# Get bundle count from a node
function get_bundle_count {
    local PORT=$1
    curl -s "http://localhost:$PORT/bundles" 2>/dev/null | grep -o '"id"' | wc -l
}

# Cleanup function to kill all processes and remove temp files
function cleanup {
    echo "Cleaning up..."
    
    # Kill all processes
    if [ -n "$PIDS" ]; then
        echo "Killing processes: $PIDS"
        kill $PIDS 2>/dev/null
        sleep 1
        kill -9 $PIDS 2>/dev/null
    fi
    
    # Remove temp files
    if [ -n "$FILES" ]; then
        echo "Removing temporary files"
        rm -f $FILES
    fi
    
    # Remove test data directory
    if [ -n "$TEST_DATA_DIR" ] && [ -d "$TEST_DATA_DIR" ]; then
        echo "Removing test data directory: $TEST_DATA_DIR"
        rm -rf "$TEST_DATA_DIR"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Initialize arrays for tracking
declare -A NODES
declare -A PORTS
declare -A TASKS
FILES=""
PIDS=""
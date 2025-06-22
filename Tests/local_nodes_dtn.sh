#!/bin/bash

. $(dirname $0)/libshelltests.sh

prepare_test

# Create a 3-node linear topology: node1 <-> node2 <-> node3

echo "Setting up 3-node linear topology test"
echo "node1 <-> node2 <-> node3"
echo

# Start node2 (middle node) first
PORT_NODE2=$(get_current_port)
start_dtnd -d -i0 -r epidemic -n node2 -C tcp:port=4557

# Start node1 with node2 as static peer
PORT_NODE1=$(get_current_port)
start_dtnd -d -i0 -r epidemic -n node1 -e incoming -C tcp:port=4556 -s tcp://localhost:4557/node2

# Start node3 with node2 as static peer  
PORT_NODE3=$(get_current_port)
start_dtnd -d -i0 -r epidemic -n node3 -e incoming -C tcp:port=4558 -s tcp://localhost:4557/node2

echo
echo "Waiting for peers to connect..."
sleep 3

# Check peer connections
echo "Checking peer connections:"
echo -n "Node1 peers: "
curl -s "http://localhost:$PORT_NODE1/peers" | grep -o '"eid"' | wc -l
echo -n "Node2 peers: "
curl -s "http://localhost:$PORT_NODE2/peers" | grep -o '"eid"' | wc -l
echo -n "Node3 peers: "
curl -s "http://localhost:$PORT_NODE3/peers" | grep -o '"eid"' | wc -l

echo
echo "Sending bundle from node1 to node3 (should route through node2)"
echo "Hello from node1" | $BINS/dtnsend -s dtn://node1/test -r dtn://node3/incoming -p $PORT_NODE1

echo "Waiting for bundle to propagate..."
sleep 3

# Start receiver on node3
echo "Checking if bundle arrived at node3..."
RECV_OUT=$(mktemp $TEST_DATA_DIR/recv.out.XXXXXX)
timeout 5 $BINS/dtnrecv -e dtn://node3/incoming -p $PORT_NODE3 > "$RECV_OUT" 2>&1 &
RECV_PID=$!

sleep 2
kill $RECV_PID 2>/dev/null || true

if grep -q "Hello from node1" "$RECV_OUT"; then
    echo -e "SUCCESS: Bundle was delivered from node1 to node3!"
    RC=0
else
    echo -e "FAILED: Bundle was not delivered"
    echo "Receiver output:"
    cat "$RECV_OUT"
    RC=1
fi

rm "$RECV_OUT"

# Check bundle counts on each node
echo
echo "Bundle counts:"
echo -n "Node1: "
get_bundle_count $PORT_NODE1
echo -n "Node2: "
get_bundle_count $PORT_NODE2
echo -n "Node3: "
get_bundle_count $PORT_NODE3

wait_for_key $1

cleanup

exit $RC
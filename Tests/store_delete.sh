#!/bin/bash

. $(dirname $0)/libshelltests.sh

prepare_test

PORT_NODE1=$(get_current_port)

# Start dtnd with 5 second janitor interval
start_dtnd -d -j 5 -i0 -C tcp:port=2342 -e incoming -r epidemic -n node1

sleep 1

echo
echo "Sending 'test' to node3"
# Send bundle and capture the bundle ID from output
BID=$(echo test | $BINS/dtnsend -s dtn://node1/test -r dtn://node3/incoming -p $PORT_NODE1 | grep "Bundle ID:" | awk '{print $3}')

if [ -z "$BID" ]; then
    echo "Failed to get bundle ID from dtnsend output"
    exit 1
fi

echo "Created bundle with ID: $BID"

sleep 1

echo
echo -n "Bundles in store on node 1: "
NUM_BUNDLES=$($BINS/dtnquery bundles -p $PORT_NODE1 | grep "dtn://" | wc -l | awk '{print $1}')
echo -n $NUM_BUNDLES

EXPECTED_BUNDLES=1

echo " / $EXPECTED_BUNDLES"
if [ "$NUM_BUNDLES" = "$EXPECTED_BUNDLES" ]; then
  echo "Correct number of bundles in store!"
else
  echo "Incorrect number of bundles in store!"
  exit 1
fi

echo
echo "Deleting bundle $BID on node 1"
# Use HTTP API to delete bundle
curl -X DELETE "http://localhost:$PORT_NODE1/bundles/$BID" -s -o /dev/null
RC=$?

echo "Delete operation returned: $RC"

sleep 1

echo
echo -n "Bundles in store on node 1 after deletion: "
NUM_BUNDLES=$($BINS/dtnquery bundles -p $PORT_NODE1 | grep "dtn://" | wc -l | awk '{print $1}')
echo -n $NUM_BUNDLES

EXPECTED_BUNDLES=0

echo " / $EXPECTED_BUNDLES"
if [ "$NUM_BUNDLES" = "$EXPECTED_BUNDLES" ]; then
  echo "Correct! Bundle was successfully deleted from store."
  EXIT_CODE=0
else
  echo "Incorrect! Bundle was not deleted from store."
  EXIT_CODE=1
fi

wait_for_key $1

cleanup

exit $EXIT_CODE
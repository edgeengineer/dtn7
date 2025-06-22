#!/bin/bash

. $(dirname $0)/libshelltests.sh

prepare_test

PORT_NODE1=$(get_current_port)

# Start dtnd with 2 second janitor interval
start_dtnd -d -j 2 -i0 -C tcp:port=2342 -e incoming -r epidemic -n node1

sleep 1

echo
echo "Sending 'test' to node3 with a lifetime of 2 seconds"
echo test | $BINS/dtnsend -s dtn://node1/test -r dtn://node3/incoming -p $PORT_NODE1 -l 2

echo "Sending 'test' to self with a lifetime of 2 seconds"
echo test | $BINS/dtnsend -s dtn://node1/test -r dtn://node1/incoming -p $PORT_NODE1 -l 2

echo
echo "Waiting for 5 seconds (bundles should expire after 2 seconds)"
sleep 5

echo
echo -n "Bundles in store on node 1: "
NUM_BUNDLES=$($BINS/dtnquery bundles -p $PORT_NODE1 | grep "dtn://" | wc -l | awk '{print $1}')
echo -n $NUM_BUNDLES

EXPECTED_BUNDLES=0

echo " / $EXPECTED_BUNDLES"
if [ "$NUM_BUNDLES" = "$EXPECTED_BUNDLES" ]; then
  echo "Correct! All bundles expired and were removed from store."
  RC=0
else
  echo "Incorrect! Some bundles did not expire properly."
  RC=1
fi

wait_for_key $1

cleanup

exit $RC
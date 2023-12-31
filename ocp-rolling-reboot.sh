#!/bin/bash
# Perform rolling reboot of Openshift nodes
#
# Uses the node_order.sh utility to compute best order to reboot the nodes
#
# T.McGinnis
#
#set -x

initial_wait_interval="45"
initial_wait_interval="1"

SCRIPT_DIR="$(dirname $0)"

oc get nodes >/dev/null
if [ $? -ne 0 ]; then
   echo "You must be logged in to perform this action"
   exit 1
fi

echo ""
echo "About to reboot nodes for this cluster  >>> $(oc whoami --show-server)"
echo ""
read -p "Press \"Y\" to proceed:: " ans
if [ "${ans^^}" != "Y" ]; then
   echo "Reboots aborted."
   exit 2
fi

function waitforready {
while [ "$(oc get node $nodename --no-headers=true|grep -v " Ready ")" != "" ]
do
   oc get node $nodename
   sleep 5
done
}

NODELIST="$($SCRIPT_DIR/node_order.sh|awk '{print $2}')"
echo "NODELIST:$NODELIST"
#for nodename in $(oc get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
for nodename in $NODELIST
do
   echo "reboot node $nodename"
   echo "ssh -o StrictHostKeyChecking=no core@$nodename sudo shutdown -r -t 3"
   oc get node $nodename
   sleep $initial_wait_interval
   waitforready
done


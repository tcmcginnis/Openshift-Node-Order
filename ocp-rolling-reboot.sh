#!/bin/bash
# Perform rolling reboot of OCP nodes
#
# Note: This script uses a smart node order script to reboot with the least amount of impact on the cluster.
#
# T.McGinnis 12/2023
#
set -x
 
initial_wait_interval="45"
initial_wait_interval="4"
ping_after_reboot_threshold="120"       # Number of seconds to wait for a ping after rebooting the node.  Alert when this is exceeded.
 
SCRIPT_DIR="$(dirname $0)"
 
if [ "$1" = "-l" ]; then
   RESTART_AT_NODE="$2"
   if [ "$RESTART_AT_NODE" != "" ]; then
      RESTART="Y"
      echo "Restarting after node \"$RESTART_AT_NODE"
   fi
fi
 
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
echo "WaitForReady"
while [ "$(oc get node $nodename --no-headers=true|grep -v " Ready ")" != "" ]
do
   oc get node $nodename
   sleep 5
   ping -c 1 $nodedns >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      CURRENT_TIME=`date +%s`
      let ping_delay=CURRENT_TIME-SHUTDOWN_TIME
      if [ $ping_delay -ge $ping_after_reboot_threshold ]; then
         echo "WARNING: This node is still not reachable after $ping_delay seconds.  Might need to investigate why."
      fi
   fi
done
}
 
NODELIST="$($SCRIPT_DIR/node_order.sh)"
echo "NODELIST:$NODELIST"
while read nodename nodedns noderole
do
echo "node:$nodename dns:$nodedns role:$noderole"
   if [ "$RESTART" = "Y" ]; then
      if [ "$nodename" = "$RESTART_AT_NODE" ]; then
         RESTART="N"
      fi
      continue
   fi
   echo "rebooting node $nodename"
   #sudo ssh -o StrictHostKeyChecking=no core@$nodedns sudo shutdown -r 0
   if [ $? -ne 0 ]; then
      echo ""
      echo "ERROR!!!!!!    Failed to initiate node shutdown for $nodedns."
      echo ""
      read -p "  Press \"Y\" to continue or ctrl-c to abort: " ans
      if [ "${ans^^}" != "Y" ]; then
         echo "Reboots aborted."
         exit 3
      fi
   fi
   SHUTDOWN_TIME=`date +%s`
   oc get node $nodename
   sleep $initial_wait_interval
   waitforready
   oc get node $nodename
done <<< $(echo "$NODELIST"|grep -v "^#"; echo "**END**")

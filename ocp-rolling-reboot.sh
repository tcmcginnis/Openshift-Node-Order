#!/bin/bash
# Perform rolling reboot of Openshift nodes
#
# Note: This script uses a smart node order script to reboot with the least amount of impact on the cluster.
#
# T.McGinnis 12/2023
#set -x

# Constants  --------------------------------------------------------------------
ping_after_reboot_threshold="180"       # Number of seconds to wait for a ping after rebooting the node.  Alert when this is exceeded.
#ping_after_reboot_threshold="10"       # Number of seconds to wait for a ping after rebooting the node.  Alert when this is exceeded.

SCRIPT_DIR="$(dirname $0)"
# ---------------------------------------


oc get nodes >/dev/null
if [ $? -ne 0 ]; then
   echo "You must be logged in to perform this action"
   exit 1
fi

echo ""
echo "About to reboot nodes for this cluster  >>> $(oc whoami --show-server)"
echo ""
read -p "Press \"Y\" to proceed: " ans
if [ "${ans^^}" != "Y" ]; then
   echo "Reboots aborted."
   exit 2
fi

# Formulate the list of nodes to reboot (Either batch or single -----------------
if [ "$1" = "batch" ]; then
   CLUSTER_NODES="$(./node_order_batch.sh)"
   shift 1
else
   CLUSTER_NODES=$(./node_order.sh)
fi


# Setup restart node if option is present ---------------------------------------
if [ "$1" = "-l" ]; then
   RESTART_AFTER_NODE="$2"
   if [ "$RESTART_AFTER_NODE" != "" ]; then
      RESTART="Y"
      echo "Restarting after node \"$RESTART_AFTER_NODE"
   fi
fi
if [ "$1" = "-r" ]; then
   RESTART_AT_NODE="$2"
   if [ "$RESTART_AT_NODE" != "" ]; then
      RESTART="Y"
      echo "Restarting at node \"$RESTART_AT_NODE"
   fi
fi

 
# Funtions ======================================================================

# Loop through each node in the batch -------------------------------------------
function process_batch_of_node_reboots {
perform_reboots
waitforNOTready
waitforready
}
# -------------------------------------------------------------------------------


# Reboot all nodes in the batch -------------------------------------------------
function perform_reboots {
echo "==== $lastbatch ============================"
while read -u10 node nodedns noderole
do
   echo "reboot node $nodedns"
   ssh -o StrictHostKeyChecking=no core@$nodedns 'sleep 1; sudo shutdown -r now &'
   #ssh -o StrictHostKeyChecking=no core@$nodedns sudo shutdown -r -t 1
   #ssh -o StrictHostKeyChecking=no core@$nodedns sudo hostname
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
done 10<<< $(echo "$NODELIST")
SHUTDOWN_TIME=`date +%s`
}
# -------------------------------------------------------------------------------


# Wait for one of the nodes nodes in the batch to become NOT ready --------------
function waitforNOTready {
GETNODELIST=$(echo "$NODELIST"|awk '{print $1}'|xargs echo)
echo "WaitForNOTReady"
oc get node $GETNODELIST
until [ "$(oc get node $GETNODELIST --no-headers=true | grep " NotReady ")" != "" ]
do
   sleep 5
done
}
# -------------------------------------------------------------------------------


# Wait for all nodes in the batch to become healthy -----------------------------
function waitforready {
GETNODELIST=$(echo "$NODELIST"|awk '{print $1}'|xargs echo)
echo "WaitForReady"
oc get node $GETNODELIST
while [ "$(oc get node $GETNODELIST --no-headers=true | grep -v " Ready ")" != "" ]
do
   while read -u10 node nodedns noderole
   do
      node_status=$(oc get node $node --no-headers=true | awk '{print $2}')
      if [ "$node_status" != "ready" ]; then
         ping -c 1 $nodedns >/dev/null 2>&1
         if [ $? -ne 0 ]; then
            CURRENT_TIME=`date +%s`
            let ping_delay=CURRENT_TIME-SHUTDOWN_TIME
            if [ $ping_delay -ge $ping_after_reboot_threshold ]; then
               echo "WARNING: Node $node is still not reachable after $ping_delay seconds.  Might need to investigate why."
            fi
         fi
      fi
   done 10<<< $(echo "$NODELIST")
   sleep 5
done
}
# -------------------------------------------------------------------------------



# MAIN Process loop  ============================================================
while read -u10 batch node nodedns noderole
do
   if [ "$RESTART" = "Y" ]; then
      if [ "$node" != "$RESTART_AFTER_NODE" -a "$node" != "$RESTART_AT_NODE" ]; then
         continue
      fi
      if [ "$node" = "$RESTART_AFTER_NODE" -o "$node" = "$RESTART_AT_NODE" ]; then
         RESTART="N"
      fi
      if [ "$node" = "$RESTART_AFTER_NODE" ]; then
         continue
      fi
   fi
   nodeentry="$node $nodedns $noderole"
   if [ "$batch" != "$lastbatch" -a "$batch" != "" ]; then
      if [ "$lastbatch" != "" ]; then
         #echo "Batch:$lastbatch"
         #echo "$NODELIST"
         process_batch_of_node_reboots
      fi
      lastbatch="$batch"
      NODELIST="$nodeentry"
   else
      NODELIST="$NODELIST
$nodeentry"
   fi
done 10<<< $(echo "$CLUSTER_NODES"|grep -v "^#"; echo "**END**")

exit

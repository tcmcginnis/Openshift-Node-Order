#!/bin/bash
#
# Multi node reboot development
#

NODELIMIT=3
NODES=$(./node_order.sh|cut -f2-)
#NODES=$(cat bb)
#echo "$NODES"
#echo "==========================="
function batch_nodes {
batch=0
while [ "$NODES" != "" ]
do
   ((batch++))
   nodelist=""
   rolelist=""
   nodecount=0
   passcount=0
   while [ $nodecount -lt $NODELIMIT -a $passcount -lt 2 ]
   do
      ((passcount++))
      if [ "$rolelist" = "|master|" -o "$rolelist" = "|control-plane" ]; then
         break
      fi
      rolelist=""
      while read node dns role
      do
         #echo -e "$role \t $node \t $dns"
         if [ "$rolelist" = "|$role|" -a "$role" != "master" -a "$role" != "control-plane" ]; then
            if [ $nodecount -lt $NODELIMIT ]; then
               rolelist=""
            fi
         fi
         if [ "${rolelist/$role}" = "$rolelist" -a "$node" != "" ]; then
            ((nodecount++))
            rolelist="$rolelist|$role|"
            if [ "$nodelist" = "" ]; then
               nodelist="$node $dns $role"
            else
               nodelist="$nodelist
$node $dns $role"
            fi
            NODES="`echo "$NODES"|grep -v "^$node"`"
         fi
      done <<< $(echo "$NODES")
   done
   #echo "==========================="
   nodelist[$batch]="$nodelist"
   #echo "nodelist: batch=$batch `echo "${nodelist[$batch]}"|wc -l`"
   #echo "${nodelist[$batch]}"
   #echo "==========================="
   #echo "NODES:"
   #echo "$NODES"
done
batchcount=$batch
}

function display_batch {
echo "# ==========================="
echo "# nodelist: batch=$batch `echo "${nodelist[$batch]}"|wc -l`"
echo "${nodelist[$batch]}" | while read nodeent
do
   echo "$batch $nodeent"
done
}

# MAIN
batch_nodes

# Mix node batches from top to bottom and from bottom to top
top=1
bottom=$batchcount
while [ $bottom -ge $top ]
do
   batch=$top
   display_batch
   if [ $top -ne $bottom ]; then
      batch=$bottom
      display_batch
   fi
   ((top++))
   ((bottom--))
done


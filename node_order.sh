#!/bin/bash
#
# Calculate best order for cluster-wide maintenance functions
#
# Rules:
#   Highest in hostname order to lowest
#   Interleave compute nodes as much as possible within other special nodes like masters and Infra
#   Leave the primary master for last
#
# The node order produced in this script can be used for patching and
# other maintenance / remediation tasks that affect the entire cluster.
#
# T.McGinnis - June 2019
#
# Version 2.0
#         1.2 - 1/9/2020   - mcginnis - converted to Openshift / k8s compatibility
#         1.3 - 3/18/2020  - mcginnis - fixed noderec parsing for ROLE
#         1.4 - 6/12/2020  - mcginnis - added "ingress" as a node type
#         1.5 - 10/22/2020 - mcginnis - added "worker" as a node type for "compute"
#         1.6 - 10/22/2020 - mcginnis - added node FQDN
#         1.7 - 10/22/2020 - mcginnis - added node FQDN and modified output to include both node name and fqdn DNS name
#         2.0 - 11/24/2020 - mcginnis - Near complete rewrite. Dynamic tables for any type of node ROLE and dynamic interleave
#         2.1 - 11/25/2020 - mcginnis - dynamic number of interleaves with this calculation "let INTERLEAVE=ROLE_X/TOTAL_OTHERS"
#                                       and put "master"s at the end of the line :)
#         2.2 - 3/12/2021  - mcginnis - Add "-" to the list of characters to ignore in the ROLE name.
#         2.3 - 5/6/2021   - mcginnis - Add "day?of?" option for segmentation.  Example: day1of3, day2of3, day3of3
#         2.4 - 12/6/2023  - mcginnis - Fixed "THISNODE" processing.
#         2.4 - 12/6/2023  - mcginnis - Clarified primary master as being the last master to list but NOT the last node.
#         2.4 - 12/6/2023  - mcginnis - Modified role to include all node labels
#         2.4 - 12/8/2023  - mcginnis - Modified "-" in role names to "_" to match bash variable naming rules.
#         2.5 - 12/18/2023 - mcginnis - Fixed ROLE list management when a role name can be part of another in regex
#

if [ "$1" = "-h" ]; then
   echo ""
   echo "USAGE: `basename $0` [dayXofY] (Example: day1of3, day2of3 day3of3)"
   echo ""
   exit 1
fi
if [ "$1" = "-v" ]; then
   VERBOSE=1
   shift
fi
if [ "${1:0:3}" = "day" ]; then
   SPLIT_OPT=$1
   SPLIT_SECTION=${SPLIT_OPT:3}
   SPLIT_SECTION=${SPLIT_SECTION/of*}
   SPLIT_TOTAL=${SPLIT_OPT/*of}
   shift
else
   SPLIT_SECTION=1
   SPLIT_TOTAL=1
fi
THISHOST=`hostname|awk -F. '{print $1}'`

if [ -x /usr/bin/kubectl ]; then
   KUBECMD="/usr/bin/kubectl"
elif [ -x /usr/local/bin/kubectl ]; then
   KUBECMD="/usr/local/bin/kubectl"
else
   KUBECMD="`locate kubectl | grep kubectl$ | grep bin`"
   if [ "$KUBECMD" = "" ]; then
      KUBECMD="kubectl"
   fi
fi

#EXCLUDELIST="locp344a|locp345a|locp346a|locp347a|locp348a"
if [ "$EXCLUDELIST" = "" ]; then
   NODES="`$KUBECMD get nodes --no-headers|awk '{print $1","$3}'`"
else
   NODES="`$KUBECMD get nodes --no-headers|awk '{print $1","$3}'|egrep -ve "($EXCLUDELIST)"`"
fi

# Compute the beginning node number and ending node number.
# This code was developed to enable segmentation (like day3of4)   
nodecount=`echo "$NODES"|wc -l`
let SPLIT_SEG_SIZE=nodecount/SPLIT_TOTAL
let SPLIT_START=(SPLIT_SECTION-1)*SPLIT_SEG_SIZE+1
if [ $SPLIT_SECTION -eq $SPLIT_TOTAL ]; then
   SPLIT_END=$nodecount
else
   let SPLIT_END=SPLIT_SECTION*SPLIT_SEG_SIZE
fi
#echo "nodecount:$nodecount SPLIT_SEG_SIZE:$SPLIT_SEG_SIZE SPLIT_START:$SPLIT_START SPLIT_END:$SPLIT_END"


# Process node list and populate tables ========================================
NODEROLES=""
total_nodes=0
for noderec in $NODES
do
   NODENAME=${noderec/,*}
   test "$VERBOSE" = "1" && echo "node:$NODENAME"
   ROLE=`echo ${noderec/,/ }|awk '{print $2}'`
   ROLE="${ROLE//,/_}"
   ROLE="${ROLE//-/_}"
   test "$VERBOSE" = "1" && echo "$NODENAME $ROLE"
   if [ "${NODENAME/.*}" = "$THISHOST" ]; then
      THISNODE="$NODENAME"
      THISROLE="$ROLE"
   else
      if [ "${NODEROLES/ $ROLE //}" = "$NODEROLES" ]; then
         #echo "Adding new role:$ROLE"
         NODEROLES="$NODEROLES $ROLE "
      fi
      eval "NODE_$ROLE=\"$NODENAME \$NODE_$ROLE\""
   fi
   let total_nodes=total_nodes+1
done
# Force the master role to be last in the list
if [ "${NODEROLES/ master }" != "$NODEROLES" ]; then
   NODEROLES="${NODEROLES/ master} master"
else
   for role in $NODEROLES
   do
      if [ "$role" = "master" -o "${role/_master}" != "$role" ]; then
         NODEROLES="${NODEROLES/ $role} $role"
         break
      fi
   done
fi
NODEROLES=${NODEROLES//  / }


# Locate the largest group of nodes with same "ROLE" ======================
#echo "NODEROLES:$NODEROLES"
ROLE_X=0 # Number of nodes in the largest group
for ROLE in $NODEROLES
do
   eval "words=( \$NODE_$ROLE )"
   if [ ${#words[@]} -gt $ROLE_X ]; then
      ROLE_X=${#words[@]}
      ROLE_X_NAME="$ROLE"
   fi
   #eval "echo \"\$ROLE:\$NODE_$ROLE\""
done
#echo "TOTAL:$total_nodes ROLE_X_NAME:$ROLE_X_NAME ROLE_X:$ROLE_X"
let TOTAL_OTHERS=total_nodes-ROLE_X
let INTERLEAVE=ROLE_X/TOTAL_OTHERS
#echo "INTERLEAVE:$INTERLEAVE"
# Note: INTERLEAVE means adding a common node (usually compute) in between
#       all the others thereby adding space beween node types



# Main node distribution processing =======================================
# -functions-
function getfqdn {
   NODENAME=$1
   FQDN=`host $NODENAME|grep "has address"|awk '{print $1}'`
   NODEFQDN=${FQDN:=$NODENAME}
}

function getnode {
   ROLEOPT=$1
   eval "NODELIST=\$NODE_$ROLEOPT"
   NODE="${NODELIST/ *}"
   if [ "$NODE" != "" ]; then
      NODELIST="${NODELIST#* }"
      getfqdn $NODE
      if [ "$NODELIST" = "" ]; then
         NODEROLES="${NODEROLES/ $ROLEOPT}"
      fi
      eval "NODE_$ROLEOPT=\"$NODELIST\""
      #echo "ROLE:$ROLEOPT NODE:$NODE NODELIST:$NODELIST<"
      let node_num=node_num+1
      if [ $node_num -ge $SPLIT_START -a $node_num -le $SPLIT_END ]; then
         echo -e "$NODE\t$NODEFQDN\t$ROLEOPT"
      fi
   fi
}  

# -main loop-
test "$VERBOSE" = "1" && echo "Node Roles:$NODEROLES"
node_num=0
while [ "$NODEROLES" != "" ]
do
   for ROLE in $NODEROLES
   do
      if [ "$ROLE" = "$ROLE_X_NAME" -a $INTERLEAVE -gt 0 -a "$NODEROLES" != " $ROLE_X_NAME" ]; then
         #echo "Bypassing interleave role..."
         continue
      fi
      # Interleave section.  Padding the node spacing with common nodes (compute)
      if [ $INTERLEAVE -gt 0 -a "$NODEROLES" != "" ]; then
         for ((n=0;n<$INTERLEAVE;n++))
         do
            getnode $ROLE_X_NAME
         done
      fi
      getnode $ROLE
   done
done

# Save this node (AKA "$THISNODE") for last section
if [ "$THISNODE" != "" -a $SPLIT_SECTION -eq $SPLIT_TOTAL ]; then
   getfqdn $THISNODE
   echo -e "$THISNODE\t$NODEFQDN\t$THISROLE"
fi


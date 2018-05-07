#!/bin/bash -eu
<%
  require "shellwords"

  cluster_ips = link('mysql').instances.map(&:address)
  if_link('arbitrator') do
    cluster_ips += link('arbitrator').instances.map(&:address)
  end
%>
CLUSTER_NODES=(<%= cluster_ips.map{|e| Shellwords.escape e}.join(' ') %>)
MYSQL_PORT=<%= Shellwords.escape p("cf_mysql.mysql.port") %>

# if the node ain't running, ain't got nothin' to drain
if ! ps -p $(</var/vcap/sys/run/mysql/mysql.pid) >/dev/null then
  echo "mysql is not running: drain OK" 1>&2
  echo 0; exit 0 # drain success
fi

function wsrep_var() {
  local var_name="$1"
  local host=${2:-localhost}
  if [[ $var_name =~ ^wsrep_[a-z_]+$ ]]; then
    timeout 5 \
      mysql --defaults-file=/var/vcap/jobs/mysql/config/mylogin.cnf -h "$host" -P "$MYSQL_PORT" \
        --execute="SHOW STATUS LIKE '$var_name'" |\
      awk '{print $2}'
  fi
}

# check if all nodes are part of the PRIMARY component; if not then 
# something is terribly wrong (loss of quorum or split-brain) and doing a
# rolling restart can actually cause data loss (e.g. if a node that is out
# of sync is used to bootstrap the cluster): in this case we fail immediately.
for NODE in ${CLUSTER_NODES[@]}; do
  cluster_status=$(wsrep_var wsrep_cluster_status "$NODE")
  if [ "$cluster_status" != "Primary" ]; then
    echo "wsrep_cluster_status of node '$NODE' is '$cluster_status' (expected 'Primary'): drain failed" 1>&2
    exit -1 # drain failed
  fi
done

# Check if all nodes are synced: if not we wait and retry
# This check must be done against *ALL* nodes, not just against the local node.
# Consider a 3 node cluster: if node1 is donor for node2 and we shut down node3 
# -that is synced- then node1 is joining, node2 is donor and node3 is down: as
# a result the cluster lose quorum until node1/node2 complete the transfer!)
for NODE in ${CLUSTER_NODES[@]}; do
  state=$(wsrep_var wsrep_local_state_comment "$NODE")
  if [ "$state" != "Synced" ]; then
    echo "wsrep_local_state_comment of node '$NODE' is '$state' (expected 'Synced'): retry drain in 5 seconds" 1>&2
    # TODO: rewrite to avoid using dynamic drain (deprecated)
    echo -5; exit 0 # retry in 5 seconds
  fi
done

echo 0; exit 0 # drain success

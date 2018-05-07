#!/bin/bash -e
<%
  require "shellwords"

  cluster_ips = link('mysql').instances.map(&:address)
  if_link('arbitrator') do
    cluster_ips += link('arbitrator').instances.map(&:address)
  end
%>
EXPECTED_CLUSTER_SIZE=<%= cluster_ips.count %>
CLUSTER_NODES=(<%= cluster_ips.map{|e| Shellwords.escape e}.join(' ') %>)
MYSQL_PORT='<%= p("cf_mysql.mysql.port") %>'

# if the node is not running, ain't got nothin' to drain
if ! ps -p $(</var/vcap/sys/run/mysql/mysql.pid) >/dev/null then
  echo "mysql is not running: drain OK" 1>&2
  echo 0; exit 0 # drain success
fi

function wsrep_var() {
  local var_name=$1
  local host=${2:-localhost}
  if [[ $var_name =~ ^wsrep_[a-z_]+$ ]]; then
    timeout 5 \
      mysql --defaults-file=/var/vcap/jobs/mysql/config/mylogin.cnf -h "$host" -P "$MYSQL_PORT" \
        --execute="SHOW STATUS LIKE '$var_name'" |\
      awk '{print $2}'
  fi
}

# check if this node is part of the PRIMARY component; if it's not then 
# something is terribly wrong (loss of quorum or split-brain) and doing a
# rolling restart can actually cause data loss (e.g. if a node that is out
# of sync is used to bootstrap the cluster): in this case we fail immediately.
cluster_status=$(wsrep_var wsrep_cluster_status)
if [ "$cluster_status" != "Primary" ]; then
  echo "wsrep_cluster_status is '$cluster_status' (expected 'Primary'): drain failed" 1>&2
  exit -1 # drain failed
fi

# this node is part of the PRIMARY component; let's check if all the nodes are
# online; if they are not we wait and retry
cluster_size=$(wsrep_var wsrep_cluster_size)
if [ "$cluster_size" -lt "$EXPECTED_CLUSTER_SIZE" ]; then
  echo "wsrep_cluster_size is '$cluster_size' (expected '$expected_cluster_size'): retry drain in 5 seconds" 1>&2
  echo -5; exit 0 # retry in 5 seconds
fi

# Check if all nodes are synced: if not we wait and retry
# This check must be done against *ALL* nodes, not just against the local node.
# Consider a 3 node cluster: if node1 is donor for node2 and we shut down node3 
# -that is synced- then node1 is joining, node2 is donor and node3 is down: as
# a result the cluster lose quorum until node1/node2 complete the transfer!)
for NODE in ${CLUSTER_NODES[@]}; do
  state=$(wsrep_var wsrep_local_state_comment "$NODE")
  if [ "$state" != "Synced" ]; then
    echo "wsrep_local_state_comment of node '$NODE' is '$state' (expected 'Synced'): retry drain in 5 seconds" 1>&2
    echo -5; exit 0 # retry in 5 seconds
  fi
done

/var/vcap/packages/mariadb/support-files/mysql.server stop --pid-file=/var/vcap/sys/run/mysql/mysql.pid 1>&2
return_code=$?
if [ $return_code -ne 0 ]; then
  echo "mysql.server stop returned $return_code: drain failed" 1>&2
  exit ${return_code} # drain failed
fi

echo "mysql.server stop returned 0: drain OK" 1>&2
echo 0; exit 0 # drain success

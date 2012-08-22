#!/bin/bash

set -e
# set -x
set -u

STORAGE_IMAGE=${STORAGE_IMAGE:-25784378}
MGMT_IMAGE=${MGMT_IMAGE:-25762231}
FLAVOR_1G_ID=${FLAVOR_1G_ID:-3}
FLAVOR_2G_ID=${FLAVOR_2G_ID:-4}
CHEF_ENV=${CHEF_ENV:-cs-swift}

# Lets spin up the required nodes
MGMT_NODE_NAME=${MGMT_NODE_NAME:-shep-swift-mgmt.rcbops.me}
PROXY_NODE_NAME=${PROXY_NODE_NAME:-shep-swift-proxy.rcbops.me}
STORAGE_NODE1_NAME=${STORAGE_NODE1_NAME:-shep-swift-storage1.rcbops.me}
STORAGE_NODE2_NAME=${STORAGE_NODE2_NAME:-shep-swift-storage2.rcbops.me}
STORAGE_NODE3_NAME=${STORAGE_NODE3_NAME:-shep-swift-storage3.rcbops.me}

KNIFE_CONFIG=${KNIFE_CONFIG:-"~/.chef/knife.rb"}

host_list=( $MGMT_NODE_NAME $STORAGE_NODE1_NAME $STORAGE_NODE2_NAME $STORAGE_NODE3_NAME )

for host in ${host_list[@]}; do
    knife node delete -c $KNIFE_CONFIG -y ${host} || true;
    knife client delete -c $KNIFE_CONFIG -y ${host} || true;
done

echo "Booting MGMT Node"
knife rackspace server create -c $KNIFE_CONFIG -N $MGMT_NODE_NAME -S $MGMT_NODE_NAME -f ${FLAVOR_2G_ID} -I $MGMT_IMAGE -E $CHEF_ENV -r role[mysql-master],role[keystone],role[swift-management-server],role[swift-proxy-server],recipe[exerstack],recipe[kong]

echo "Booting Storate Node1"
knife rackspace server create -c $KNIFE_CONFIG -N $STORAGE_NODE1_NAME -S $STORAGE_NODE1_NAME -f ${FLAVOR_1G_ID} -I $STORAGE_IMAGE -E $CHEF_ENV -r role[swift-object-server],role[swift-container-server],role[swift-account-server]

echo "Setting swift zone on Storage Node1"
knife exec -c $KNIFE_CONFIG -E "nodes.find(:name => '$STORAGE_NODE1_NAME') {|n| n.set['swift']['zone'] = '1'; n.save }"

echo "Booting Storate Node2"
knife rackspace server create -c $KNIFE_CONFIG -N $STORAGE_NODE2_NAME -S $STORAGE_NODE2_NAME -f ${FLAVOR_1G_ID} -I $STORAGE_IMAGE -E $CHEF_ENV -r role[swift-object-server],role[swift-container-server],role[swift-account-server]

echo "Setting swift zone on Storage Node2"
knife exec -c $KNIFE_CONFIG -E "nodes.find(:name => '$STORAGE_NODE2_NAME') {|n| n.set['swift']['zone'] = '2'; n.save }"

echo "Booting Storate Node3"
knife rackspace server create -c $KNIFE_CONFIG -N $STORAGE_NODE3_NAME -S $STORAGE_NODE3_NAME -f ${FLAVOR_1G_ID} -I $STORAGE_IMAGE -E $CHEF_ENV -r role[swift-object-server],role[swift-container-server],role[swift-account-server]

echo "Setting swift zone on Storage Node3"
knife exec -c $KNIFE_CONFIG -E "nodes.find(:name => '$STORAGE_NODE3_NAME') {|n| n.set['swift']['zone'] = '3'; n.save }"

for i in 1 2 3; do
    for host in ${host_list[@]}; do
        echo "Running second passes on ${host}";
        ssh root@$(knife node show ${host} | grep IP | awk '{print $2}') chef-client;
    done
done

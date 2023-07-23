#!/bin/bash 

# export environmental variables
. env.sh


# add user and group in ubuntu22.04
if ! source add_user.sh; then
    return 1
fi


# run elasticsearch
cd ../es_cluster/


path_host_prefix=$PWD
export ES_NAME=$1

cd - &> /dev/null


if [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "es-" as the default prefix of the container name."
fi

es_nodes=("es01" "es02" "es03")
es_seed_hosts=("es02,es03" "es01,es03" "es01,es02")
es_master_nodes=("es01,es02,es03")


if ! docker network inspect ${NEW_NETWORK} &> /dev/null; then 
    docker network create -d bridge --subnet ${NET_SERVER} \
        --gateway ${GW_SERVER} ${NEW_NETWORK} &> /dev/null
fi


for ((port=9200,i=0; i<${ES_NODE_NUM}; ++port,++i)); do
    [ -z ${ES_NAME} ] && name=es-${port} || name=${ES_NAME}-${port} 

    docker run -d -p ${port}:9200 \
               -e "ES_JAVE_OPTS=-Xms521m -Xmx512m" \
               -e xpack.security.enabled=false \
               -e node.name=${es_nodes[$i]} \
               -e cluster.name=${ES_CLUSTER_NAME} \
               -e discovery.seed_hosts=${es_seed_hosts[$i]} \
               -e cluster.initial_master_nodes=${es_master_nodes} \
               -e bootstrap.memory_lock=true \
               -v ${path_host_prefix}/${es_nodes[$i]}/config:/usr/share/elasticsearch/config \
               --ulimit memlock=-1:-1 \
               --net ${NEW_NETWORK} --ip ${ES_NODES_IP[$i]} \
               --name ${name} \
               ${IMG_ES}
done


[ $? -gt 0 ] && return 1



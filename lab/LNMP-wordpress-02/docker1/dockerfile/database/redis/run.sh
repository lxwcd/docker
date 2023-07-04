#!/bin/bash 

# export variables to environment
. env.sh

# create apline and redis images
if ! source get_imgs.sh; then 
    return 1
fi 

# add user and group in ubuntu22.04
if ! source add_user.sh; then
    return 1
fi

# init data, copy shared data to host dir and modify owner and group
if ! source init_data.sh; then
    return 1
fi

# create new network for all severs
if ! docker network inspect ${NEW_NETWORK} &> /dev/null; then
    docker network create -d bridge --subnet ${NET_SERVER}  --gateway ${GW_SERVER} ${NEW_NETWORK} &> /dev/null
    [ $? -gt 0 ] && return 1 || echo "create new network ${NEW_NETWORK}"
fi


# run redis
cd ../../../redis/

PATH_HOST_PREFIX=$PWD
export REDIS_NAME=$1

cd - &> /dev/null

if [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "redis-" as the default prefix of the container name."
fi

# expose redis-server and redis-sentinel ports
for ((port=6370,s_port=26370, i=0; port<637${NODE_NUM}; ++port,++s_port,++i)); do
    dir=${PATH_HOST_PREFIX}/node_${port}
    [ -z ${REDIS_NAME} ] && name=redis-$port || name=${REDIS_NAME}-$port 
    
    docker run -d -p ${port}:6379 -p ${s_port}:26379 \
               -v ${dir}/data:/usr/local/redis/data \
               -v ${dir}/log:/usr/local/redis/log  \
               -v ${dir}/etc:/usr/local/redis/etc  \
               --name ${name} \
               --net ${NEW_NETWORK} --ip ${NODES_IP[$i]} \
               ${IMG_REDIS}
done

[ $? -gt 0 ] && return 1

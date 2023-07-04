#!/bin/bash 

# init shared data in init_data folder

DIR=$(mktemp -d)
#alias rm='mv -t ${DIR} '


clear_noempty_folde(){
    folder="$1"
    if [ -n "$(ls -A ${folder})" ]; then
        mv -t ${DIR} ${folder}/*
    fi
}

# data
PATH_INIT_DATA="init_data"
PATH_SHARE_DATA="../../../redis"

clear_noempty_folde ${PATH_SHARE_DATA}

is_master=true

# create folder for each redis server
for ((port=6370; port<637${NODE_NUM}; ++port)); do
    dir=${PATH_SHARE_DATA}/node_${port}
    mkdir -p ${dir} > /dev/null
    cp -a ${PATH_INIT_DATA}/* ${dir}/

    # modify redis port in container
    # sed -Ei "s/^port 6379/port ${port}/" ${dir}/etc/redis.conf

    # set requirepass, namely, password for user "default"
    sed -Ei "s/^requirepass .*/requirepass ${REDIS_USER_PW}/" ${dir}/etc/redis.conf

    # set masterauth for all servers, including the master server
    sed -Ei "s/^masterauth .*/masterauth ${MASTER_AUTH}/" ${dir}/etc/redis.conf

    if $is_master; then
        is_master=false
    else
        sed -Ei "/replicaof <masterip>/a\replicaof ${MASTER_IP} ${MASTER_PORT}" ${dir}/etc/redis.conf
    fi

    # modify sentinel configuration
    sed -Ei "s/^sentinel monitor .*/sentinel monitor mymaster ${MASTER_IP} ${MASTER_PORT} ${QUORUM}/" \
        ${dir}/etc/sentinel.conf

    sed -Ei "s/^sentinel auth-pass mymaster .*/sentinel auth-pass mymaster ${MASTER_AUTH}/" \
        ${dir}/etc/sentinel.conf

    chown -R redis:redis ${PATH_SHARE_DATA}
done


#unalias rm

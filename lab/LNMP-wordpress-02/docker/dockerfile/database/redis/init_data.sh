#!/bin/bash 

# 修改当前目录文件的权限
chown -R www.www entrypoint.sh
chmod +x *.sh

# init shared data in init_data folder

DIR=/tmp/rm_$(date +"%Y%m%d%H%M%S")
mkdir -p $DIR > /dev/null 


clear_noempty_folder(){
    folder="$1"
    subdir=$DIR/${folder}_$(mktemp -d)
    mkdir -p $subdir > /dev/null 

    if [ -n "$(ls -A ${folder})" ]; then
        mv ${folder}/* ${subdir} 
    fi
}

# clear old redis data
PATH_INIT_DATA="init_data"
PATH_SHARE_DATA="../../../redis"

clear_noempty_folder ${PATH_SHARE_DATA}


# init redis data
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

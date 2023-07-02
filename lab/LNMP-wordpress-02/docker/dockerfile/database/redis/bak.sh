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

#clear_noempty_folde ${PATH_SHARE_DATA}

for ((port=6370; port<637${NODE_NUM}; ++port)); do
    dir=${PATH_SHARE_DATA}/node_${port}
    echo $dir
    mkdir -p ${dir}
    cp -a ${PATH_INIT_DATA}/* ${dir}/
    sed -Ei "s/^port 6379/port ${port}/" ${dir}/etc/redis.conf
    chown -R redis:redis ${PATH_SHARE_DATA}
done




#unalias rm

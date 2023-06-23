#!/bin/bash 

# 删除创建容器后生成的数据，还原为初始数据

DIR=$(mktemp -d)
#alias rm='mv -t ${DIR} '


clear_noempty_folde(){
    folder="$1"
    if [ -n "$(ls -A ${folder})" ]; then
        mv -t ${DIR} ${folder}/*
    fi
}

# wordpress 数据
PATH_INIT_DATA="data"
PATH_SHARE_DATA="../../../web/data"

clear_noempty_folde ${PATH_SHARE_DATA}
cp -a ${PATH_INIT_DATA}/* ${PATH_SHARE_DATA}/
chown -R www:www ${PATH_SHARE_DATA}

# nginx 日志
PATH_N_log="../../../web/nginx/logs"
clear_noempty_folde ${PATH_N_log}


# mysql 数据
PATH_INIT_DB="../../database/mysql/data"
PATH_SHARE_DB="../../../mysql/data"

clear_noempty_folde ${PATH_SHARE_DB}
cp -a ${PATH_INIT_DB}/* ${PATH_SHARE_DB}/
chown -R 999:999 ${PATH_SHARE_DB}

#unalias rm

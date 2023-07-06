#!/bin/bash 

# 修改当前目录文件的权限
chown -R www.www entrypoint.sh
chmod +x *.sh

# 删除创建容器后生成的数据，还原为初始数据
#alias rm='DIR=/tmp/rm_$(date +"%Y%m%d%H%M%S"); mkdir ${DIR}; mv -t ${DIR} '
DIR=/tmp/rm_$(date +"%Y%m%d%H%M%S")
mkdir -p $DIR > /dev/null 


clear_noempty_folde(){
    folder="$1"
    subdir=$DIR/${folder}_$(mktemp -d)
    mkdir -p $subdir > /dev/null 

    if [ -n "$(ls -A ${folder})" ]; then
        mv ${folder}/* ${subdir} 
    fi
}

reinit(){
    init_dir=$1
    share_dir=$2
    uid=$3
    gid=$4

    clear_noempty_folde $share_dir
    cp -a ${init_dir}/* ${share_dir}/
    chown -R ${uid}:${gid} ${share_dir}
}


# wordpress 数据
PATH_INIT_DATA="data"
PATH_SHARE_DATA="../../../web/data"

reinit $PATH_INIT_DATA $PATH_SHARE_DATA www www


# nginx 日志和配置文件
PATH_INIT_NGINX="nginx"
PATH_SHARE_NGINX="../../../web/nginx"

reinit $PATH_INIT_NGINX $PATH_SHARE_NGINX www www


# php 配置文件
PATH_INIT_PHP="php82"
PATH_SHARE_PHP="../../../web/php82"

reinit $PATH_INIT_PHP $PATH_SHARE_PHP www www


# mysql 配置文件和数据
PATH_INIT_DB_CONF="../../database/mysql/conf"
PATH_SHARE_DB_CONF="../../../mysql/conf"

reinit $PATH_INIT_DB_CONF $PATH_SHARE_DB_CONF 999 999


# mysql data
PATH_INIT_DB_DATA="../../database/mysql/data"
PATH_SHARE_DB_DATA="../../../mysql/data"

reinit $PATH_INIT_DB_DATA $PATH_SHARE_DB_DATA 999 999


#unalias rm

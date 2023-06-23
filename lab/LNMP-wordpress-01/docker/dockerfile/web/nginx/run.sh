#!/bin/bash 


# docker run in ubuntu22.04
# run nginx


# add user and group in ubuntu22.04
. addUser.sh

[ $? -gt 0 ] && return 

cd ../../../web/

IMAGE="nginx-alpine:2.14-01"
#IMAGE="registry.cn-hangzhou.aliyuncs.com/lnmp_wordpress/nginx-alpine:2.14-01"
PORT_HOST="80"
PATH_HOST_PREFIX=$PWD
export NGINX_NAME=${1}

cd - &> /dev/null

if [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "nginx-01" as the default container name."
fi


docker run -d -p ${PORT_HOST}:80 \
           -v ${PATH_HOST_PREFIX}/nginx/conf:/usr/local/nginx/conf \
           -v ${PATH_HOST_PREFIX}/nginx/logs:/usr/local/nginx/logs \
           -v ${PATH_HOST_PREFIX}/php82:/etc/php82  \
           --name ${NGINX_NAME:=nginx-01} \
           ${IMAGE}


# run mysql
. run_mysql.sh

#!/bin/bash 

# create apline and nginx images
if ! source getImgs.sh; then 
    return 1
fi 

# add user and group in ubuntu22.04
if ! source addUser.sh; then
    return 1
fi

# init data, copy shared data to host dir and modify owner and group
if ! source init_data.sh; then
    return 1
fi


# run nginx+php-fpm
cd ../../../web/

#IMAGE="nginx-alpine:2.14-01"
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
           ${IMG_NGINX}

[ $? -gt 0 ] && return 1

# run mysql
if ! source run_mysql.sh; then
    return 1
fi

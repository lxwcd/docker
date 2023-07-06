#!/bin/bash 

# export environmental variables
. env.sh

# create apline and nginx images
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


# run nginx+php-fpm
cd ../../../web/

PORT_HOST_1="8080"
PORT_HOST_2="8081"
PATH_HOST_PREFIX=$PWD
export NGINX_NAME=$1

cd - &> /dev/null


if [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "nginx-" as the default prefix of the container name."
fi

# run the first nginx server
[ -z ${NGINX_NAME} ] && name1=nginx-${PORT_HOST_1} || name1=${NGINX_NAME}-${PORT_HOST_1} 

docker run -d -p ${PORT_HOST_1}:80 \
           -v ${PATH_HOST_PREFIX}/nginx/conf:/usr/local/nginx/conf \
           -v ${PATH_HOST_PREFIX}/nginx/logs:/usr/local/nginx/logs \
           -v ${PATH_HOST_PREFIX}/php82:/etc/php82  \
           --name ${name1} \
           --net ${NEW_NETWORK} --ip ${NGINX_IP[0]} \
           ${IMG_NGINX}

[ $? -gt 0 ] && return 1


# run the second nginx server
[ -z ${NGINX_NAME} ] && name2=nginx-${PORT_HOST_2} || name2=${NGINX_NAME}-${PORT_HOST_2} 

docker run -d -p ${PORT_HOST_2}:80 \
           --volumes-from ${name1}
           --name ${name2} \
           --net ${NEW_NETWORK} --ip ${NGINX_IP[1]} \
           ${IMG_NGINX}

[ $? -gt 0 ] && return 1


# run mysql
if ! source run_mysql.sh; then 
    return 1
fi 

# run redis
if ! source run_redis.sh; then 
    return 1
fi 



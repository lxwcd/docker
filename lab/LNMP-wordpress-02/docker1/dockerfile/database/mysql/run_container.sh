#!/bin/bash 

cd ../../../mysql/

#PORT_HOST="3306"
IMAGE="mysql:5.7"
PATH_HOST_PREFIX=$PWD
MYSQL_NAME=${1}

cd - &> /dev/null


if [ -z "$NGINX_NAME" ]; then 
    echo "please run the nginx container before starting the mysql container"
elif [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "mysql-01" as the default container name."
fi


docker run --name ${MYSQL_NAME:=mysql-01} \
           --network container:${NGINX_NAME} \
           --env-file ./env.list \
           -v ${PATH_HOST_PREFIX}/data:/var/lib/mysql \
           -v ${PATH_HOST_PREFIX}/conf/conf.d:/etc/mysql/conf.d \
           -v ${PATH_HOST_PREFIX}/conf/mysql.conf.d:/etc/mysql/mysql.conf.d \
           -d ${IMAGE} --character-set-server=utf8mb4 


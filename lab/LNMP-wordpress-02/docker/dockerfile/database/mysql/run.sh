#!/bin/bash 

cd ../../../mysql/

#PORT_HOST="3306"
IMAGE="mysql:5.7"
PATH_HOST_PREFIX=$PWD
MYSQL_NAME=${1}

cd - > /dev/null


if [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "mysql-" as the default prefix of the container name."
fi

docker run --name ${MYSQL_NAME:=mysql-01} \
           --net ${NEW_NETWORK} --ip ${MYSQL_IP[0]} \
           --env-file ./env.list \
           -v ${PATH_HOST_PREFIX}/data:/var/lib/mysql \
           -v ${PATH_HOST_PREFIX}/conf/conf.d:/etc/mysql/conf.d \
           -v ${PATH_HOST_PREFIX}/conf/mysql.conf.d:/etc/mysql/mysql.conf.d \
           -d ${IMAGE} --character-set-server=utf8mb4 


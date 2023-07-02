#!/bin/bash 

cd ../../../mysql/

PORT_HOST="3306"
IMAGE="mysql:5.7"
PATH_HOST_PREFIX=$PWD

cd - &> /dev/null


docker run --name ${1} \
           -p ${PORT_HOST}:3306 \
           --env-file ./env.list \
           -v ${PATH_HOST_PREFIX}/data:/var/lib/mysql \
           -v ${PATH_HOST_PREFIX}/conf/conf.d:/etc/mysql/conf.d \
           -v ${PATH_HOST_PREFIX}/conf/mysql.conf.d:/etc/mysql/mysql.conf.d \
           -d ${IMAGE} --character-set-server=utf8mb4 

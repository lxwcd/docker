#!/bin/bash 

IMAGE="mysql:5.7"
PORT_HOST="3306"

docker run --name ${1} \
           -p ${PORT_HOST}:3306 \
           --env-file ./env.list \
           -d ${IMAGE} --character-set-server=utf8mb4 

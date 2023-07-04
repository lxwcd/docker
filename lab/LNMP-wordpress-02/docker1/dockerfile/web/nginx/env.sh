#!/bin/bash 

export IMG_ALPINE="alpine-base:3.18-01"
export IMG_REDIS="redis-alpine:7.0.11-01"

#********************  redis variables *********************#
# number of redis server 
export NODE_NUM="3"

# new network in docker for backend severs
export NEW_NETWORK="net-server"    
export NET_SERVER="172.27.0.0/16"
export GW_SERVER="172.27.0.1"

# master requirepass
# ensure that the "requirepass" is the same for all redis servers
export REDIS_USER_PW="123456"

# master ip
export MASTER_IP="172.27.0.10"
export NODES_IP=("172.27.0.10" "172.27.0.11" "172.27.0.12")

# master port
export MASTER_PORT="6379"
# masterauth
export MASTER_AUTH="123456"

# redis sentinel configuration
export QUORUM="2"


#********************  nginx variables *********************#
export NGINX_IP=("172.27.0.20" "172.27.0.21")

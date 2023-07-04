#!/bin/bash 

for port in {1..6}; do
    mkdir -p /docker/redis/node-${port}/conf.d
    cat >> /docker/redis/node-${port}/conf.d/redis.conf <<EOF
port 6379
bind 0.0.0.0
masterauth 123456
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
cluster-announce-ip 172.18.0.1${port}
cluster-announce-port 6379
cluster-announce-bus-port 16379
appendonly yes
EOF
done

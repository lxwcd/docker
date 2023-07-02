#!/bin/bash 

for port in {1..6}; do
docker run -p 637${port}:6379 -p 1637${port}:16379 --name redis-${port} \
       -v /docker/redis/node-{port}/data:/data \
       -v /docker/redis/node-{port}/conf.d/redis.conf:/etc/redis/redis.conf \
       -d --net net-redis --ip 172.18.0.1${port} redis:7.0-alpine
done


#!/bin/bash 

       #-v /docker/redis/node-{port}/data:/data \
       #-v /docker/redis/node-{port}/conf.d/redis.conf:/etc/redis/redis.conf \

for port in {7..7}; do
docker run -p 637${port}:6379 -p 1637${port}:6379 --name redis-${port} \
       -d --privileged redis:7.0-alpine
done


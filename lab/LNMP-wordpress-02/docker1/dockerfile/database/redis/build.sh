#!/bin/bash 

#IMAGE="redis-alpine:7.0.11-01"

echo "***************** build redis: ${IMG_REDIS} *********************"

docker build --no-cache -t ${IMG_REDIS} -f Dockerfile .

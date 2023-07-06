#!/bin/bash 

#IMAGE="nginx-alpine:2.14-01"

echo "***************** build nginx: ${IMG_NGINX} *********************"

docker build --no-cache -t ${IMG_NGINX} -f Dockerfile .

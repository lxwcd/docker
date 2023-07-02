#!/bin/bash 

echo "***************** build alpine: ${IMG_ALPINE} *********************"

docker build -t ${IMG_ALPINE} -f Dockerfile .

#!/bin/bash 

IMAGE="nginx-alpine:2.14-01"

docker build --no-cache -t ${IMAGE} -f Dockerfile .

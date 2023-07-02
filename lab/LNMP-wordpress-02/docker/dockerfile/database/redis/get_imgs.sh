#!/bin/bash 

IMG_NAME=""

checkImg() {
    IMG_NAME=$1
    TAG=`docker images -q ${IMG_NAME}`

    while [ -n "${TAG}" ]; do 
        read -p "Image ${IMG_NAME} exists. Input 'y' to use the it, or enter a new name and tag (format: name:tag): " input 

        if [[ ${input} =~ ^[yY]$ ]]; then
            return 0
        fi

        if [[ "${input}" =~ ^[^:]+:[^:]+$ ]]; then 
            IMG_NAME=${input}
        else
            echo "Invalid format. Please enter the image name and tag in the format 'name:tag'."
        fi

        TAG=`docker images -q ${IMG_NAME}`
    done

    return 1
}


if ! checkImg "${IMG_ALPINE}"; then
    IMG_ALPINE=${IMG_NAME}
    if ! source ../../system/alpine/build.sh; then
        return 1
    fi
fi

if ! checkImg "${IMG_REDIS}"; then
    IMG_NGINX=${IMG_NAME}
    # modify redis Dockerfile 
    sed -i "1s/^/# /; 1s/^/FROM ${IMG_ALPINE}\n/" Dockerfile

    if ! source build.sh; then 
        return 1
    fi
fi

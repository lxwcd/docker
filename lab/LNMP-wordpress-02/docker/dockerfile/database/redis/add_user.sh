#!/bin/bash 

# create user and group in host system with a uid and gid of 998

UID_REDIS="998"
GID_REDIS="998"

UID_REDIS_HOST=$(id -u redis  2> /dev/null)
GID_REDIS_HOST=$(getent group redis | cut -d: -f3  2> /dev/null)

if getent group "${GID_REDIS}" &> /dev/null; then 
   if [ "${GID_REDIS_HOST}"  != "${GID_REDIS}"  ]; then
        echo "There is already a group with GID ${GID_REDIS}, please select another user "\
            "and modify the Dockerfile of REDIS."
        return 1
   fi
else
    groupadd -g "${GID_REDIS}"  -r redis
fi

if getent passwd "${UID_REDIS}"  &> /dev/null; then 
   if [ "${UID_REDIS_HOST}"  != "${UID_REDIS}"  ]; then
        echo "There is already a user with UID ${UID_REDIS} , please select another user "\
            "and modify the Dockerfile of REDIS."
        return 1
   fi
else
    useradd -s /sbin/nologin -u "${UID_REDIS}"  -g "${GID_REDIS}"  -r -M redis
fi

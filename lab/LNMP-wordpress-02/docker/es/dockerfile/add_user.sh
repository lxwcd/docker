#!/bin/bash 

# 为 elasticsearch 数据创建账号 Dockerfile 中指定的 uid 和 gid 为 1000

UID_ES="1000"
GID_ES="1000"

UID_H_ES=$(id -u elasticsearch  2> /dev/null)
GID_H_ES=$(getent group elasticsearch | cut -d: -f3  2> /dev/null)


if getent group "${GID_ES}" &> /dev/null; then 
   if [ "${GID_H_ES}"  != "${GID_ES}"  ]; then
        echo "There is already a group with GID ${GID_ES}, please select another user "\
            "and modify the Dockerfile of nginx."
        return 1
   fi
else
    groupadd -g "${GID_ES}"  -r elasticsearch
fi


if getent passwd "${UID_ES}"  &> /dev/null; then 
   if [ "${UID_H_ES}"  != "${UID_ES}"  ]; then
        echo "There is already a user with UID ${UID_ES} , please select another user "\
            "and modify the Dockerfile of nginx."
        return 1
   fi
else
    useradd -s /sbin/nologin -u "${UID_ES}"  -g "${GID_ES}"  -r -M elasticsearch
fi

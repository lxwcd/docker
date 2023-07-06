#!/bin/bash 

# 为 nginx 和 php-fpm 数据创建账号 Dockerfile 中指定的 uid 和 gid 为 124

UID_NGINX="124"
GID_NGINX="124"

UID_WWW=$(id -u www  2> /dev/null)
GID_WWW=$(getent group www | cut -d: -f3  2> /dev/null)

if getent group "${GID_NGINX}" &> /dev/null; then 
   if [ "${GID_WWW}"  != "${GID_NGINX}"  ]; then
        echo "There is already a group with GID ${GID_NGINX}, please select another user "\
            "and modify the Dockerfile of nginx."
        return 1
   fi
else
    groupadd -g "${GID_NGINX}"  -r www
fi

if getent passwd "${UID_NGINX}"  &> /dev/null; then 
   if [ "${UID_WWW}"  != "${UID_NGINX}"  ]; then
        echo "There is already a user with UID ${UID_NGINX} , please select another user "\
            "and modify the Dockerfile of nginx."
        return 1
   fi
else
    useradd -s /sbin/nologin -u "${UID_NGINX}"  -g "${GID_NGINX}"  -r -M www
fi


# 为 mysql 创建用户
# 宿主机装上 docker 后，有一个 docker (999) 的组，因此创建一个 mysql (999) 的用户，指定 gid 为 999

UID_MYSQL="999"
GID_MYSQL="999"
UID_MYSQL_HOST=$(id -u mysql 2> /dev/null)
GID_MYSQL_HOST=$(getent group mysql | cut -d: -f3  2> /dev/null)
GID_DOCKER_HOST=$(getent group docker | cut -d: -f3  2> /dev/null)

if getent group "${GID_MYSQL}"  &> /dev/null; then 
    if [ "${GID_MYSQL}"  != "${GID_MYSQL_HOST}"  ] && [ "${GID_MYSQL}"  != "${GID_DOCKER_HOST}"  ]; then
        echo "There is already a group with GID ${GID_MYSQL} , please select another user "\
            "and modify the Dockerfile of mysql."
        return 1
    fi
else
    groupadd -g "${GID_MYSQL}"  -r mysql
fi


if getent passwd "${UID_MYSQL}"  &> /dev/null; then 
    if [ "${UID_MYSQL}"  != "${UID_MYSQL_HOST}"  ]; then
        echo "There is already a user with UID ${UID_MYSQL}, please select another user "\
            "and modify the Dockerfile of nginx."
        return 1
    fi
else
    useradd -s /sbin/nologin -u "${UID_MYSQL}"  -g "${GID_MYSQL}"  -r -M mysql
fi



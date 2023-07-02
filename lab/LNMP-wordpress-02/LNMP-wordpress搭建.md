LNMP-wordpress 搭建博客-02

用容器是实现的第二个实验，加上一个 Haproxy 调度，nginx 实现负载均衡


redis 做会话保持，redis 3 个节点，哨兵监控
mysql 主从复制，MHA 高可用
NFS 存放数据


# 实验目的
- 熟悉 docker 制作镜像以及网络环境搭建
- 熟悉 Haproxy 做反向代理的使用
- 熟悉 redis 的使用
本实验中 web 服务器只有两个，但为了操作 redis 集群使用，用 6 个 redis 服务器
- 熟悉用 docker compose 来进行单机容器的编排

# 实验环境
- win11 上安装 vmware，vmware 中安装 ubuntu22.04 作为宿主机，实验在容器环境中进行
- 一个 Haproxy 做代理
- 两个 nginx+php-fpm 提供 web 服务
- 一个 mysql 存放数据
- 一个 redis 集群做会话保持（3 个 redis 容器，1主2从，配置哨兵）
- 将 web 网页数据存放在宿主机中，通过 rsync 将数据同步到另一个宿主机中保存备份
- 最后用 docker compose 来进行容器的编排
- 创建一个自定义网络 net_server，容器在自定义网络中运行



# 创建服务端自定义网络
- 创建自定义网络 net-server

```bash
[root@docker redis]$ docker network create -d bridge --subnet 172.27.0.0/16 --gateway 172.27.0.1 net-server
d089259c4b6b6d46d19a93714b52511bb6827cd1e85161f9f153eacf7b50f210
[root@docker redis]$ docker network ls
NETWORK ID     NAME         DRIVER    SCOPE
33536d4425f5   bridge       bridge    local
20043ee9ac13   host         host      local
d089259c4b6b   net-server   bridge    local
3f30de7abd8f   none         null      local
```


# redis 容器
> [redis](https://github.com/docker-library/redis/blob/2e6e8961037d8b2838a4105bb9a761441e1ae477/7.2-rc/alpine/docker-entrypoint.sh)


- 创建 3 个 redis 容器，指定网络为 net-server
- 如果实验在容器中做，可以不曝露端口，先将端口曝露，方便实验一些测试等
容器的端口可以不变，用默认的 6379，宿主机的端口分为 6370-6375
- 配置文件、数据和日志做持久化处理
- 配置哨兵，1主2从
- 配置好三个 redis server 的密码，使用默认用户 `default`，密码通过配置文件中 `requirepass` 指定
- 三个节点的密码相同
- 配置 `masterauth`，密码和 `requirepass`，即主节点的登录密码，主节点也配置，防止主节点出故障后恢复成为从节点
- 从节点配置 `replicaof <masterip> <masterport>`，即指定主节点的 ip 和端口
- entrypoint 需要将 redis-server 和 redis-sentinel 均启动
```bash
#!/bin/sh

set -e

redis-server /usr/local/redis/etc/redis.conf &
redis-sentinel /usr/local/redis/etc/sentinel.conf
```
在两者的配置文件中，均指定 `daemonize no`，即前提运行，但启动 redis-server 需要加上 `&`，
否则后面的 `redis-sentinel` 不能启动


# nginx+php-fpm Web 服务器
nginx+php-fpm 镜像可以用第一个实验的镜像
但这里运行两个容器，两个容器的数据共享，因此用数据卷容器


original content in /etc/apk # cat repositories
https://dl-cdn.alpinelinux.org/alpine/v3.18/main
https://dl-cdn.alpinelinux.org/alpine/v3.18/community


modify with sed command to the following:


https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.18/main
https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.18/community
https://dl-cdn.alpinelinux.org/alpine/v3.18/main
https://dl-cdn.alpinelinux.org/alpine/v3.18/community
# 客户端

## 创建独立网络
在宿主机中创建一个自定义网络 net_client，指定网段为 `172.18.0.0/16`
```bash
[root@docker ~]$ docker network ls
NETWORK ID     NAME      DRIVER    SCOPE
e3adb504d07c   bridge    bridge    local
20043ee9ac13   host      host      local
3f30de7abd8f   none      null      local
[root@docker ~]$ docker network create -d bridge --subnet 172.18.0.0/16 --gateway 172.18.0.1 net_client
1fadd5467009209e9049092883b78f3ea9ea6cb791d0756b3f9583d0e40a1855
[root@docker ~]$ docker network ls
NETWORK ID     NAME         DRIVER    SCOPE
e3adb504d07c   bridge       bridge    local
20043ee9ac13   host         host      local
1fadd5467009   net_client   bridge    local
3f30de7abd8f   none         null      local
```


## 创建客户端容器
```bash
[root@docker ~]$ docker ps -a
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
[root@docker ~]$ docker run -it --name client --network net_client alpine-base:3.18-01 sh
/ # hostname -i
172.18.0.2
```


# 路由器
路由器要与客户端和 LVS 的 vip 通信

## 创建路由器的网络
```bash
[root@docker ~]$ docker network create -d bridge --subnet 172.19.0.0/16 --gateway 172.19.0.1 net_router
62ae45ec221122588a5b357c776bdb464bad70f817a968d19714503e9b87b50f
[root@docker ~]$ docker network ls
NETWORK ID     NAME         DRIVER    SCOPE
e3adb504d07c   bridge       bridge    local
20043ee9ac13   host         host      local
1fadd5467009   net_client   bridge    local
62ae45ec2211   net_router   bridge    local
3f30de7abd8f   none         null      local
```


## 创建路由器容器
```bash
[root@docker ~]$ docker run -it --name router --network net_router alpine-base:3.18-01 sh
/ # hostname -i
172.19.0.2
```

## 让客户端能访问路由器
将客户端容器加入到路由器的网络中

```bash
[root@docker ~]$ docker network connect net_router client
```

查看客户端的 ip：
```bash
[root@docker ~]$ docker exec -it client sh
/ # ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
57: eth0@if58: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UP
    link/ether 02:42:ac:12:00:02 brd ff:ff:ff:ff:ff:ff
    inet 172.18.0.2/16 brd 172.18.255.255 scope global eth0
       valid_lft forever preferred_lft forever
61: eth1@if62: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UP
    link/ether 02:42:ac:13:00:03 brd ff:ff:ff:ff:ff:ff
    inet 172.19.0.3/16 brd 172.19.255.255 scope global eth1
       valid_lft forever preferred_lft forever
/ # ping 172.19.0.2
PING 172.19.0.2 (172.19.0.2): 56 data bytes
64 bytes from 172.19.0.2: seq=0 ttl=64 time=0.280 ms
```














- win11 上利用 vmware 创建 ubuntu22.04 虚拟机
- 虚拟机中创建 nginx+php-fpm 的镜像，暴露端口 80 提供 web 服务
- 拉取官方仓库的 mysql:5.7 镜像，不对外暴露端口，运行时以 container 模式和 nginx 容器使用一个网络
- nginx web 服务器的配置文件，日志和 wordpress 的网页文件做持久化，将宿主机的文件目录挂载到容器响响应的目录中
- mysql 容器的数据和配置文件做持久化处理

主运行脚本在如下目录：
```bash
docker/dockerfile/web/nginx
```
下面的 run.sh 为运行脚本
```bash
[root@docker nginx]$ tree -L 1
.
├── addUser.sh
├── build.sh
├── data
├── Dockerfile
├── entrypoint.sh
├── init_data.sh
├── nginx
├── php8
├── php82
├── run_mysql.sh
├── run.sh
└── src
```

# 宿主机建立账号
- nginx 和 php-fpm 使用的用户和组为 www(124)
- mysql 中使用的用户和组为 mysql(999)
- 数据做持久化，会将宿主机中相应的目录挂载到容器目录中，因此在宿主机中建立和容器中 id 相同的账号
如宿主机用 ubuntu22.04，无 www 用户和组，uid 124 也未被占用，因此创建该用户和组
```bash
groupadd -g 124 -r www
useradd -s /sbin/nologin -u 124 -g 124 -r -M www
```
宿主机装上 docker 后，有一个 docker (999) 的组，因此创建一个 mysql (999) 的用户，指定 gid 为 999
```bash
useradd -s /sbin/nologin -u 999 -g 999 -r -M mysql
```
- 上面创建的 user 和 group 已经写到 Dockerfile 中，而 mysql 是直接用官方的镜像，如果要修改 owner 和 group 需要重新做镜像

- 建账号的脚本为 `docker/dockerfile/web/nginx/addUser.sh`，在 `run.sh` 脚本中执行的第一个脚本，如果账号不满足要求则不能执行脚本


# 修改宿主机挂载的文件路径和属性
- 在 `docker/dockerfile` 中有初始镜像的数据，创建容器后挂载宿主机的一些目录到容器中存放容器的数据，
挂载的目录在 `docker/dockerfile/web/nginx/run.sh` 脚本中指明

初始挂载目录中的文件和 `docker/dockerfile` 中的初始数据相同，启动容器时会将宿主机的，目录挂载，因此容器的对应目录
中的内容会被覆盖，容器运行后会生成一些新数据

如果允许一个容器后，想将容器的数据目录还原初始数据，则执行 `docker/dockerfile/web/nginx/init_data.sh` 脚本，
该脚本会删除容器的数据，将初始数据拷贝过去并修改属性


# 拉取镜像
- nginx 镜像做好后上传到阿里云镜像仓库，可以用下面命令拉取
```bash
[root@nginx1 shell_scripts]$ docker pull registry.cn-hangzhou.aliyuncs.com/lnmp_wordpress/nginx-alpine:2.14-01
2.14-01: Pulling from lnmp_wordpress/nginx-alpine
31e352740f53: Pull complete
fa898d506f52: Pull complete
5e0c2d44d085: Pull complete
03298b2f5ee6: Pull complete
01b8894003d8: Pull complete
9e7fe484d7c9: Pull complete
98c016007037: Pull complete
4ca8d922b445: Pull complete
Digest: sha256:4c9a9028fad51d69fe38300530c3b0052099f5aa028144526e93b94fa115a83d
Status: Downloaded newer image for registry.cn-hangzhou.aliyuncs.com/lnmp_wordpress/nginx-alpine:2.14-01
registry.cn-hangzhou.aliyuncs.com/lnmp_wordpress/nginx-alpine:2.14-01
[root@nginx1 shell_scripts]$ docker images
REPOSITORY                                                      TAG       IMAGE ID       CREATED       SIZE
registry.cn-hangzhou.aliyuncs.com/lnmp_wordpress/nginx-alpine   2.14-01   ffbecc875ccb   5 hours ago   107MB
[root@nginx1 shell_scripts]$
```

- mysql 镜像使用官方镜像，可以直接从官方拉取 
```bash
[root@nginx1 shell_scripts]$ docker pull mysql:5.7
```

# 启动容器
镜像构建的 Dockerfile 以及运行的脚本均在同级 `docker` 目录中
```bash
➜  LNMP-wordpress-01 git:(master) ✗ \ls -l
total 4
-rwxrwxrwx 1 lx lx 1727 Jun 22 17:45 LNMP-wordpress搭建.md
drwxrwxrwx 1 lx lx 4096 Jun 22 16:53 docker
```

运行容器的脚本以及 Dockerfile 在 dockerfile 子目录中
```bash
➜  docker git:(master) ✗ ls
dockerfile  mysql  web
```

```bash
➜  docker git:(master) ✗ tree -L 3 dockerfile
dockerfile
├── database
│   └── mysql
│       ├── conf
│       ├── data
│       ├── env.list
│       ├── run.sh
│       ├── run_container.sh
│       └── run_init.sh
├── system
│   ├── alpine
│   │   ├── Dockerfile
│   │   └── build.sh
│   ├── centos
│   ├── debian
│   └── ubuntu
└── web
    ├── apache
    ├── nginx
    │   ├── Dockerfile
    │   ├── build.sh
    │   ├── data
    │   ├── entrypoint.sh
    │   ├── init_data.sh
    │   ├── nginx
    │   ├── php8
    │   ├── php82
    │   ├── run.sh
    │   └── src
    └── tomcat
```


1. 运行 nginx 容器，执行 run.sh 
使用宿主机 80 端口，提前查看确认宿主机的该端口未被占用
```bash
#!/bin/bash

IMAGE="nginx-alpine:2.14-01"
PORT_HOST="80"
PATH_HOST_PREFIX="/docker/web"
export NGINX_NAME=${1}

if [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "nginx-01" as the default container name."
fi

docker run -d -p ${PORT_HOST}:80 \
           -v ${PATH_HOST_PREFIX}/nginx/conf:/usr/local/nginx/conf \
           -v ${PATH_HOST_PREFIX}/nginx/logs:/usr/local/nginx/logs \
           -v ${PATH_HOST_PREFIX}/php82:/etc/php82  \
           --name ${NGINX_NAME:=nginx-01} \
           ${IMAGE}
```

2. 运行 mysql 容器，以 container 模式运行，则执行 `run_container.sh`
与 nginx 容器运行脚本在一个终端执行

```bash
#!/bin/bash

#PORT_HOST="3306"
IMAGE="mysql:5.7"
PATH_HOST_PREFIX="/docker/mysql"
MYSQL_NAME=${1}

if [ -z "$NGINX_NAME" ]; then
    echo "please run the nginx container before starting the mysql container"
elif [ "${1}" == "-h|--help" ]; then
    echo "Please provide an argument as the name of the container, \
        or use "mysql-01" as the default container name."
fi


docker run --name ${MYSQL_NAME:=mysql-01} \
           --network container:${NGINX_NAME} \
           --env-file ./env.list \
               -v ${PATH_HOST_PREFIX}/data:/var/lib/mysql \
           -v ${PATH_HOST_PREFIX}/conf/conf.d:/etc/mysql/conf.d \
           -v ${PATH_HOST_PREFIX}/conf/mysql.conf.d:/etc/mysql/mysql.conf.d \
           -d ${IMAGE} --character-set-server=utf8mb4
```

3. 查看容器的运行状态以及宿主机的端口
```bash
[root@docker mysql]$ docker ps
[root@docker mysql]$ ss -ntl
```

# 利用 wordpress 搭建博客
本地浏览器中输入宿主机的 IP 地址，默认会进入 wordpress 的安装界面，填写数据库和用户的信息如下：
![](img/2023-06-23-17-42-04.png)

注意数据库的主机写 `127.0.0.1`，因为 mysql 和 nginx 用相同的 IP，端口号 3306 为默认值可以不用写


# 后续改进
目前 nginx 和 mysql 都是单点，后续还需做高可用和负载均衡处理 
LNMP-wordpress 搭建博客-02

# 实验介绍
- 在第一个实验的基础上改进，nginx 用两个做负载均衡
    - 两个 nginx 用容器做
    - 两个 nginx 的容器的数据做持久化化，且共享，可以用容器数据卷容器实现
    - 相较于第一个实验，php-fpm 需要安装 session 扩展模块来支持 session 保存
    - 想要用 redis 存储 seesion 信息，需要安装 redis 扩展模块
      - redis 主从做会话保持，一主两从模式，配置三个哨兵，三个哨兵和三个redis server 分别在一个容器中

- 增加一个反向代理来调度两个 nginx 服务器
    - 方案一：用 LVS 来做反向代理调度
    LVS 需要用到内核模块，不做成容器
    - 方案二：两个 LVS 调度，用 keepalived 来实现 LVS 的高可用
    LVS 需要用到内核模块，不做成容器
    - 方案二：用 haproxy 做反向代理调度，并用 keepalived 实现高可用
    haproxy 用容器实现
  

# 实验一：单个 LVS 调度
- win11 上安装 vmware，vmware 中安装 ubuntu22.04 做实验
- 一个 ubuntu22.04，NAT 模式网卡，IP 10.0.0.208，运行下面容器：
    - 两个 nginx+php-fpm 提供 web 服务
    将 web 网页数据和配置文件、日志等做持久化处理，存放在宿主机中
    两个 web server 的数据共享
    - 一个 mysql 存放数据
    - 一个 redis 集群做会话保持（3 个 redis 容器，1主2从，配置哨兵）
- 一个 ubuntu22.04 宿主机


环境变量在 `env.sh` 中定义，包含镜像名，容器 IP 等


## 客户端
- ubuntu22.04 host-only 网络模式，IP：10.0.0.204

- 网卡配置
```bash
network:
  version: 2
 #renderer: networkd
  renderer: NetworkManager
  ethernets:
    eth0:
      match:
        name: eth0
      addresses: 
      - 192.168.10.204/24
      routes:
      - to: default
        via: 192.168.10.205
      - to: 10.0.0.0/24
        via: 10.0.0.205/24
      nameservers:
         addresses: [192.168.10.205]
```

默认网关指向路由器的接口 192.168.10.205

- 路由规则
```bash
[root@client ~]$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         192.168.10.205  0.0.0.0         UG    100    0        0 eth0
10.0.0.0        10.0.0.205      255.255.255.0   UG    24     0        0 eth0
10.0.0.205      0.0.0.0         255.255.255.255 UH    24     0        0 eth0
192.168.10.0    0.0.0.0         255.255.255.0   U     100    0        0 eth0
```

## 路由器
- ubuntu22.04 
- 一个 NAT 模式网卡，ip 为 10.0.0.205
- 一个 host-only 模式网卡，ip 为 192.168.10.205
- 开启 ip_forward
```bash
[root@router ~]$ cat /proc/sys/net/ipv4/ip_forward
0
[root@router ~]$ vim /etc/sysctl.conf
```
编辑 `/etc/sysctl.conf` 文件，取消下面注释，开启 ip_forward
```bash
# Uncomment the next line to enable packet forwarding for IPv4
net.ipv4.ip_forward=1
```
让配置生效：
```bash
[root@router ~]$ sysctl -p
net.ipv4.ip_forward = 1
[root@router ~]$ cat /proc/sys/net/ipv4/ip_forward
1
```

- 网卡配置
```bash
network:
  version: 2
 #renderer: networkd
  renderer: NetworkManager
  ethernets:
    eth0:
      match:
        name: eth0
      addresses: 
      - 10.0.0.205/24
      routes:
      - to: default
        via: 10.0.0.2
      nameservers:
         addresses: [10.0.0.2]
    eth1:
      match:
        name: eth1
      addresses: 
      - 192.168.10.205/24
```

- 查看路由规则
```bash
[root@router ~]$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         10.0.0.2        0.0.0.0         UG    100    0        0 eth0
10.0.0.0        0.0.0.0         255.255.255.0   U     100    0        0 eth0
192.168.10.0    0.0.0.0         255.255.255.0   U     101    0        0 eth1
```

## LVS
- ubuntu 22.04 
- 一个 NAT 模式网卡，IP 为 10.0.0.206，作为 VIP，与客户端通信
- 使用 NAT 工作模式进行调度
- LVS 调度使用 wrr 算法，而后端服务器的权重相同，因此应该是依次轮询调度

正常 LVS 应该配两个网络接口，一个 VIP，对外通信；一个 DIP 对内通信
但本实验后端服务器在另一个宿主机的容器中，配置网络环境达到一样的效果即可
客户端无法访问后端服务器，只能访问 LVS 的 VIP，然后 LVS 将客户端的请求调度到后端服务器中

### 网络配置
- 网卡配置
```bash
network:
  version: 2
 #renderer: networkd
  renderer: NetworkManager
  ethernets:
    eth0:
      match:
        name: eth0
      addresses: 
      - 10.0.0.206/24
      routes:
      - to: default
        via: 10.0.0.2
      - to: 192.168.10.0/24
        via: 192.168.10.205/24
      - to: 172.27.0.0/16
        via: 10.0.0.208/24
      nameservers:
         addresses: [10.0.0.2]
```

- 路由规则：
```bash
[root@lvs-1 ~]$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         10.0.0.2        0.0.0.0         UG    100    0        0 eth0
10.0.0.0        0.0.0.0         255.255.255.0   U     100    0        0 eth0
172.27.0.0      10.0.0.208      255.255.0.0     UG    24     0        0 eth0
192.168.10.0    192.168.10.205  255.255.255.0   UG    24     0        0 eth0
192.168.10.205  0.0.0.0         255.255.255.255 UH    24     0        0 eth0
```
需要加上和后端服务器通信的路由规则，即目标地址为 `172.27.0.0/16` 的路由


- 开启 ip_forward
```bash
[root@lvs-1 ~]$ cat /proc/sys/net/ipv4/ip_forward
1
```

### NAT 工作模式配置
#### 安装 ipvsadm 命令行工具
```bash
[root@lvs-1 ~]$ apt install -y ipvsadm
```

查看服务的状态：
```bash
[root@lvs-1 ~]$ systemctl status ipvsadm.service
● ipvsadm.service - LSB: ipvsadm daemon
     Loaded: loaded (/etc/init.d/ipvsadm; generated)
     Active: active (exited) since Tue 2023-07-04 19:48:02 CST; 1min 59s ago
       Docs: man:systemd-sysv-generator(8)
    Process: 3871 ExecStart=/etc/init.d/ipvsadm start (code=exited, status=0/SUCCESS)
        CPU: 6ms

Jul 04 19:48:02 lvs-1 systemd[1]: Starting LSB: ipvsadm daemon...
Jul 04 19:48:02 lvs-1 ipvsadm[3871]:  * ipvsadm is not configured to run. Please edit /etc/default/ipvsadm
Jul 04 19:48:02 lvs-1 systemd[1]: Started LSB: ipvsadm daemon.
```


#### 利用防火墙标记集群服务
添加 iptables 规则，在 mangle 表上大防火墙标签，将目标地址为 VIP，端口为 80 和 443 的
数据包都打上防火墙标签，归类为一个集群服务

```bash
[root@lvs-1 ~]$ iptables -t mangle -A PREROUTING -d 10.0.0.206 -p tcp -m multiport --dports 80,443 -j MARK --set-mark 1
```

- 保存防火墙规则
安装 `iptables-persistent` 包来保存 iptables 规则并开机自启
```bash
[root@lvs-1 ~]$ apt install -y iptables-persistent
```

当前已写入的规则自动保存到 `/etc/iptables/rules.v4` 文件中
```bash
[root@lvs-1 ~]$ cat /etc/iptables/rules.v4
# Generated by iptables-save v1.8.7 on Tue Jul  4 20:59:22 2023
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A PREROUTING -d 10.0.0.206/32 -p tcp -m multiport --dports 80,443 -j MARK --set-xmark 0x1/0xffffffff
COMMIT
# Completed on Tue Jul  4 20:59:22 2023
```

查看服务状态：
```bash
[root@lvs-1 ~]$ systemctl status netfilter-persistent.service
● netfilter-persistent.service - netfilter persistent configuration
     Loaded: loaded (/lib/systemd/system/netfilter-persistent.service; enabled; vendor preset: enabled)
    Drop-In: /etc/systemd/system/netfilter-persistent.service.d
             └─iptables.conf
     Active: active (exited) since Tue 2023-07-04 20:59:22 CST; 13min ago
       Docs: man:netfilter-persistent(8)
   Main PID: 5116 (code=exited, status=0/SUCCESS)
        CPU: 4ms

Jul 04 20:59:22 lvs-1 systemd[1]: Starting netfilter persistent configuration...
Jul 04 20:59:22 lvs-1 netfilter-persistent[5118]: run-parts: executing /usr/share/netfilter-persistent/plugins.d/15-ip4tables sta>
Jul 04 20:59:22 lvs-1 netfilter-persistent[5119]: Warning: skipping IPv4 (no rules to load)
Jul 04 20:59:22 lvs-1 netfilter-persistent[5118]: run-parts: executing /usr/share/netfilter-persistent/plugins.d/25-ip6tables sta>
Jul 04 20:59:22 lvs-1 netfilter-persistent[5120]: Warning: skipping IPv6 (no rules to load)
Jul 04 20:59:22 lvs-1 systemd[1]: Finished netfilter persistent configuration.
```


#### 添加 ipvs 规则
```bash
[root@lvs-1 ~]$ ipvsadm -L
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
[root@lvs-1 ~]$ ipvsadm -A -f 1 -s wrr
[root@lvs-1 ~]$ ipvsadm -a -f 1 -r 172.27.0.30:80 -m
[root@lvs-1 ~]$ ipvsadm -a -f 1 -r 172.27.0.31:80 -m
[root@lvs-1 ~]$ ipvsadm -L
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
FWM  1 wrr
  -> 172.27.0.30:80               Masq    1      0          0
  -> 172.27.0.31:80               Masq    1      0          0
```

#### 查看 ipvs 规则
```bash
[root@lvs-1 ~]$ cat /proc/net/ip_vs
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port Forward Weight ActiveConn InActConn
FWM  00000001 wrr
  -> AC1B001F:0050      Masq    1      0          0
  -> AC1B001E:0050      Masq    1      0          0
```

#### 保存 ipvs 规则
默认保存到 `/etc/ipvsadm.rules` 文件中
```bash
[root@lvs-1 ~]$ service ipvsadm save
 * Saving IPVS configuration...                                                                                            [ OK ]
[root@lvs-1 -r 172.27.0.30:80 -m -w 1
-a -f 1 -r 172.27.0.31:80 -m -w 1
```

#### 开机自动加载 ipvs 规则
将下列文件中的 `AUTO` 的值改为 `true`
```bash
[root@lvs-1 ~]$ vim /etc/default/ipvsadm
# ipvsadm

# if you want to start ipvsadm on boot set this to true
AUTO="true"

# daemon method (none|master|backup)
DAEMON="none"

# use interface (eth0,eth1...)
IFACE="eth0"

# syncid to use
# (0 means no filtering of syncids happen, that is the default)
# SYNCID="0"
```

该文件可以通过 `dpkg -L ipvsadm` 查找

## 后端服务器
- 宿主机为 ubuntu22.04
- NAT 模式网卡，IP 为 10.0.0.208
- 后端服务器运行在容器中，包含：
    - 两个 nginx+php-fpm 提供 web 服务
    将 web 网页数据和配置文件、日志等做持久化处理，存放在宿主机中
    两个 web server 的数据共享
    - 一个 mysql 存放数据
    - 一个 redis 集群做会话保持（3 个 redis 容器，1主2从，配置哨兵）
- 容器运行在一个自定义网络中，网段为 172.27.0.0/16 


### 创建服务端自定义网络
- 创建自定义网络 net-server
两个 nginx server，三个 redis server，mysql server 均在自定义网络中
运行容器时指定网络和 ip

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


### 后端服务器的网关指向 LVS
后端服务器的宿主机网卡配置文件为：
```bash
network:
  version: 2
 #renderer: networkd
  renderer: NetworkManager
  ethernets:
    eth0:
      match:
        name: eth0
      addresses: 
      - 10.0.0.208/24
      routes:
      - to: default
        via: 10.0.0.206
      nameservers:
         addresses: [10.0.0.2]
```
注意域名服务器指向 10.0.0.2，否则域名无法解析


路由表的路由规则：
```bash
[root@docker apt]$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         10.0.0.206      0.0.0.0         UG    100    0        0 eth0
10.0.0.0        0.0.0.0         255.255.255.0   U     100    0        0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 docker0
172.17.0.0      0.0.0.0         255.255.0.0     U     426    0        0 docker0
172.27.0.0      0.0.0.0         255.255.0.0     U     0      0        0 br-455a33a641b6
172.27.0.0      0.0.0.0         255.255.0.0     U     425    0        0 br-455a33a641b6
```


### redis 容器
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


### nginx+php-fpm Web 服务器
- nginx-1.24.0
- php82-fpm-8.2.7-r0

nginx+php-fpm 镜像可以用第一个实验的镜像
但这里运行两个容器，两个容器的数据共享，因此用数据卷容器

启动第一个 nginx 服务器，宿主机相关目录挂载到容器目录中，实现容器的配置文件和数据等持久化
第二个容器启动时用 `--volumes-from` 和第一个容器共享目录

运行时用 `--link` 选项将 mysql 的名字进行解析，需要运行时先运行 mysql 再运行 nginx
```bash
docker run -d -p ${PORT_HOST_1}:80 \
           -v ${PATH_HOST_PREFIX}/nginx/conf:/usr/local/nginx/conf \
           -v ${PATH_HOST_PREFIX}/nginx/logs:/usr/local/nginx/logs \
           -v ${PATH_HOST_PREFIX}/php82:/etc/php82  \
           -v ${PATH_HOST_PREFIX}/data:/data/www  \
           --name ${name1} \
           --net ${NEW_NETWORK} --ip ${NGINX_IP[0]} \
           --link ${MYSQL_NAME} \
           ${IMG_NGINX}
```

进入 nginx 容器测试：
```bash
/ # ping mysql-01
PING mysql-01 (172.27.0.20): 56 data bytes
64 bytes from 172.27.0.20: seq=0 ttl=64 time=0.440 ms
64 bytes from 172.27.0.20: seq=1 ttl=64 time=0.104 ms
```

### 配置 php 支持 redis 保存 session
未成功

#### 支持 session 模块
- 和第一个实验不同，安装 php-fpm 时，还需安装 `php82-session-8.2.7-r0`
```bash
/ # apk search php-session
php81-session-8.1.20-r0
php82-session-8.2.7-r0
```

安装完后查看 session 模块，安装成功应该会显示下面信息：
```bash
/ # php-fpm82 -m | grep session
session
```

同时在 php 的配置文件中设置 session 的保存路径
容器中 php 的配置文件的路径为 `/etc/php82/php.ini`，可以在宿主机中挂载的目录中修改
```bash
session.save_handler = files
session.save_path = "/tmp"
```
默认第二个保存路径注释了，默认 session 存放为文件的形式

问题：
在 `/tmp` 目录下没有 session 信息


#### 用 redis 存放 session
未成功

安装扩展模块支持 php 连 redis
```bash
/ # apk search php*redis
php81-pecl-redis-5.3.7-r1
php82-pecl-redis-5.3.7-r2
```

修改 php 的配置，session 改为 redis 存放
容器中的路径为 `/etc/php82/php-fpm.d/www.conf`
在该配置文件最后添加下面配置，redis 地址改为 redis 哨兵的地址和端口
```bash
php_value[session.save_handler]=redis
php_value[session.save_path]="tcp://172.27.0.10:26379"
```


## LVS 和 后端服务器网络连通
docker 设置一些防火墙规则，容器与外界通信，如不同宿主机通信，对容器的 IP 做了 SNAT 转换
即容器虽然能与外界通信，出去的地址是宿主机的 IP 而非容器的 IP，类似虚拟机中的宿主机用 NAT
模式网卡时，与外界通信时 IP 转换为 windows 的IP

可以通过抓包验证：
在 10.0.0.208 的容器中 ping 10.0.0.205，然后在 10.0.0.205 上抓包
```bash
[root@router ~]$ tcpdump -i eth0 -nn icmp and dst host 10.0.0.205
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes


17:10:44.289282 IP 10.0.0.208 > 10.0.0.205: ICMP echo request, id 37, seq 0, length 64
17:10:45.289814 IP 10.0.0.208 > 10.0.0.205: ICMP echo request, id 37, seq 1, length 64
```
可以看到来源的 IP 地址为 10.0.0.208 而非容器的 IP 

而在 10.0.0.205 宿主机直接 ping 容器的 IP 172.27.0.30 无法通信


- 安装 docker 后 ip_forward 默认打开
```bash
[root@docker redis]$ cat /proc/sys/net/ipv4/ip_forward
1
```

### 后端服务器上修改防火墙设置
在 10.0.0.208 的机器上，修改防火墙设置
```bash
iptables -A FORWARD -s 10.0.0.206 -j ACCEPT
```

对来源为 10.0.0.206 的数据包，全部接收，修改后防火墙规则如下：
```bash
[root@docker nginx]$ iptables -vnL
Chain INPUT (policy ACCEPT 11959 packets, 1548K bytes)
pkts bytes target     prot opt in     out     source  destination

Chain FORWARD (policy DROP 3 packets, 252 bytes)
pkts bytes target     prot opt in     out     source  destination
390K   51M DOCKER-USER  all  --  *      *       0.0.0.0/0  0.0.0.0/0
390K   51M DOCKER-ISOLATION-STAGE-1  all  --  *      *       0.0.0.0/0  0.0.0.0/0
0     0 ACCEPT     all  --  *      docker0  0.0.0.0/0  0.0.0.0/0  ctstate RELATED,ESTABLISHED
0     0 DOCKER     all  --  *      docker0  0.0.0.0/0  0.0.0.0/0
0     0 ACCEPT     all  --  docker0 !docker0  0.0.0.0/0  0.0.0.0/0
0     0 ACCEPT     all  --  docker0 docker0  0.0.0.0/0  0.0.0.0/0
390K   51M ACCEPT     all  --  *      br-455a33a641b6  0.0.0.0/0  0.0.0.0/0  ctstate RELATED,ESTABLISHED
78  4568 DOCKER     all  --  *      br-455a33a641b6  0.0.0.0/0  0.0.0.0/0
255 30269 ACCEPT     all  --  br-455a33a641b6 !br-455a33a641b6  0.0.0.0/0  0.0.0.0/0
36  2160 ACCEPT     all  --  br-455a33a641b6 br-455a33a641b6  0.0.0.0/0    0.0.0.0/0
4   336 ACCEPT     all  --  *      *       10.0.0.206  0.0.0.0/0

Chain OUTPUT (policy ACCEPT 11871 packets, 1185K bytes)
 pkts bytes target     prot opt in     out     source  destination

Chain DOCKER (2 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.10 tcp dpt:26379
    0     0 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.10 tcp dpt:6379
    0     0 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.11 tcp dpt:26379
    0     0 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.11 tcp dpt:6379
    0     0 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.12 tcp dpt:26379
    0     0 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.12 tcp dpt:6379
   35  1820 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.30 tcp dpt:80
    0     0 ACCEPT     tcp  --  !br-455a33a641b6 br-455a33a641b6  0.0.0.0/0  172.27.0.31 tcp dpt:80

Chain DOCKER-ISOLATION-STAGE-1 (1 references)
pkts bytes target     prot opt in     out     source               destination
0    0 DOCKER-ISOLATION-STAGE-2  all  --  docker0 !docker0  0.0.0.0/0  0.0.0.0/0
255 30269 DOCKER-ISOLATION-STAGE-2  all  --  br-455a33a641b6 !br-455a33a641b6  0.0.0.0/0  0.0.0.0/0
390K   51M RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain DOCKER-ISOLATION-STAGE-2 (2 references)
pkts bytes target     prot opt in     out     source  destination
0   0 DROP       all  --  *      docker0  0.0.0.0/0  0.0.0.0/0
0   0 DROP       all  --  *      br-455a33a641b6  0.0.0.0/0  0.0.0.0/0
255 30269 RETURN     all  --  *      *       0.0.0.0/0   0.0.0.0/0

Chain DOCKER-USER (1 references)
pkts bytes target     prot opt in     out     source  destination
390K   51M RETURN     all  --  *      *       0.0.0.0/0  0.0.0.0/0
```

当从 10.0.0.206 的 LVS 服务器发送数据包到 10.0.0.208 后端服务器宿主机时，根据路由表的路由规则，
目的地址为自定义容器的地址，因此转发给自定义网桥 `br-455a33a641b6`
根据防火墙的 filter 表的 FORWARD 链规则
```bash
Chain FORWARD (policy DROP 3 packets, 252 bytes)
pkts bytes target     prot opt in     out     source  destination
390K   51M DOCKER-USER  all  --  *      *       0.0.0.0/0  0.0.0.0/0
390K   51M DOCKER-ISOLATION-STAGE-1  all  --  *      *       0.0.0.0/0  0.0.0.0/0
0     0 ACCEPT     all  --  *      docker0  0.0.0.0/0  0.0.0.0/0  ctstate RELATED,ESTABLISHED
0     0 DOCKER     all  --  *      docker0  0.0.0.0/0  0.0.0.0/0
0     0 ACCEPT     all  --  docker0 !docker0  0.0.0.0/0  0.0.0.0/0
0     0 ACCEPT     all  --  docker0 docker0  0.0.0.0/0  0.0.0.0/0
390K   51M ACCEPT     all  --  *      br-455a33a641b6  0.0.0.0/0  0.0.0.0/0  ctstate RELATED,ESTABLISHED
78  4568 DOCKER     all  --  *      br-455a33a641b6  0.0.0.0/0  0.0.0.0/0
255 30269 ACCEPT     all  --  br-455a33a641b6 !br-455a33a641b6  0.0.0.0/0  0.0.0.0/0
36  2160 ACCEPT     all  --  br-455a33a641b6 br-455a33a641b6  0.0.0.0/0    0.0.0.0/0
4   336 ACCEPT     all  --  *      *       10.0.0.206  0.0.0.0/0
```

`in` 应为 eth0 网络接口，前面的规则都不匹配，最后一条规则是手动加的，如果没有则用默认策略，即 `DROP`，
而加了最后一条后，对于来源为 10.0.0.206 的数据包会 `ACCEPT`，因此除了 LVS 服务器，其他地址的包均会丢弃


#### 保存防火墙规则并开机自动加载
安装下面工具
```bash
[root@docker data]$ apt install -y iptables-persistent
```

查看当前保存的规则
```bash
[root@docker apt]$ cat /etc/iptables/rules.v4
```

查看服务状态：
```bash
[root@docker apt]$ systemctl status netfilter-persistent.service
● netfilter-persistent.service - netfilter persistent configuration
     Loaded: loaded (/lib/systemd/system/netfilter-persistent.service; enabled; vendor preset: enabled)
    Drop-In: /etc/systemd/system/netfilter-persistent.service.d
             └─iptables.conf
     Active: active (exited) since Tue 2023-07-04 22:23:10 CST; 3min 33s ago
       Docs: man:netfilter-persistent(8)
   Main PID: 23070 (code=exited, status=0/SUCCESS)
        CPU: 6ms

Jul 04 22:23:10 docker systemd[1]: Starting netfilter persistent configuration...
Jul 04 22:23:10 docker netfilter-persistent[23072]: run-parts: executing /usr/share/netfilter-persistent/plugins.d/15-ip4tables start
Jul 04 22:23:10 docker netfilter-persistent[23073]: Warning: skipping IPv4 (no rules to load)
Jul 04 22:23:10 docker netfilter-persistent[23072]: run-parts: executing /usr/share/netfilter-persistent/plugins.d/25-ip6tables start
Jul 04 22:23:10 docker netfilter-persistent[23074]: Warning: skipping IPv6 (no rules to load)
Jul 04 22:23:10 docker systemd[1]: Finished netfilter persistent configuration.
```


## 客户端验证
在后端服务器的宿主机 10.0.0.208 上挂载到 web 服务器的目录中添加一个测试文档：
```bash
[root@docker data]$ echo "10.0.0.208" > test.html
[root@docker data]$ cat test.html
10.0.0.208
```

客户端通过 curl 访问 LVS 服务器的 test.html 文件
```bash
[root@client ~]$ for((i=0;i<4;++i));do curl 10.0.0.206/test.html; sleep 1; done
10.0.0.208
10.0.0.208
10.0.0.208
10.0.0.208
```

同时在 10.0.0.208 (后端服务器的宿主机) 抓包，可以看见轮流调度到后端连个服务器上
```bash
[root@docker redis]$ tcpdump  -nn tcp port 80  and dst net 172.27.0.0/16
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes

22:32:44.028875 IP 192.168.10.204.44632 > 172.27.0.31.80: Flags [S], seq 2308927033, win 64240, options [mss 1460,sackOK,TS val 51717500 ecr 0,nop,wscale 7], length 0
22:32:44.030451 IP 192.168.10.204.44632 > 172.27.0.31.80: Flags [.], ack 1403329246, win 502, options [nop,nop,TS val 51717502 ecr 1749347118], length 0
22:32:44.030451 IP 192.168.10.204.44632 > 172.27.0.31.80: Flags [P.], seq 0:83, ack 1, win 502, options [nop,nop,TS val 51717502 ecr 1749347118], length 83: HTTP: GET /test.html HTTP/1.1
22:32:44.031736 IP 192.168.10.204.44632 > 172.27.0.31.80: Flags [.], ack 251, win 501, options [nop,nop,TS val 51717504 ecr 1749347120], length 0
22:32:44.032040 IP 192.168.10.204.44632 > 172.27.0.31.80: Flags [.], ack 262, win 501, options [nop,nop,TS val 51717504 ecr 1749347120], length 0
22:32:44.032436 IP 192.168.10.204.44632 > 172.27.0.31.80: Flags [F.], seq 83, ack 262, win 501, options [nop,nop,TS val 51717504 ecr 1749347120], length 0
22:32:44.033513 IP 192.168.10.204.44632 > 172.27.0.31.80: Flags [.], ack 263, win 501, options [nop,nop,TS val 51717505 ecr 1749347122], length 0
22:32:45.039746 IP 192.168.10.204.44644 > 172.27.0.30.80: Flags [S], seq 3387375546, win 64240, options [mss 1460,sackOK,TS val 51718511 ecr 0,nop,wscale 7], length 0
22:32:45.040528 IP 192.168.10.204.44644 > 172.27.0.30.80: Flags [.], ack 3683269897, win 502, options [nop,nop,TS val 51718512 ecr 2757209003], length 0
22:32:45.040528 IP 192.168.10.204.44644 > 172.27.0.30.80: Flags [P.], seq 0:83, ack 1, win 502, options [nop,nop,TS val 51718512 ecr 2757209003], length 83: HTTP: GET /test.html HTTP/1.1
22:32:45.041665 IP 192.168.10.204.44644 > 172.27.0.30.80: Flags [.], ack 251, win 501, options [nop,nop,TS val 51718513 ecr 2757209004], length 0
22:32:45.041729 IP 192.168.10.204.44644 > 172.27.0.30.80: Flags [.], ack 262, win 501, options [nop,nop,TS val 51718513 ecr 2757209004], length 0
22:32:45.041771 IP 192.168.10.204.44644 > 172.27.0.30.80: Flags [F.], seq 83, ack 262, win 501, options [nop,nop,TS val 51718514 ecr 2757209004], length 0
22:32:45.042844 IP 192.168.10.204.44644 > 172.27.0.30.80: Flags [.], ack 263, win 501, options [nop,nop,TS val 51718514 ecr 2757209005], length 0
```



# 实验二：keepalived 调度


# Haproxy 反向代理
利用 Haproxy 将客户端的请求调度到后端的两个 nginx 服务器上




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
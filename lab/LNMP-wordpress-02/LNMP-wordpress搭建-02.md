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
  
- 容器中的 nginx，mysql，redis 等的端口可以不用曝露，但为了测试运行容器时将端口曝露
正常端口应该不曝露，客户端访问反向代理的 IP 和端口，再调度到后端服务器

- lvs 调度后端 nginx 服务器用的 NAT 模式
在后端服务器 10.0.0.208 上抓包可以看到数据包来源 ip 为客户端 ip 192.168.10.204
```bash
[root@docker ~]$ tcpdump -nn tcp port 80 and src host 192.168.10.204 and dst net 172.27.0.0/16
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
16:33:26.083899 IP 192.168.10.204.51624 > 172.27.0.31.80: Flags [S], seq 2761002142, win 64240, options [mss 1460,sackOK,TS val 1141969744 ecr 0,nop,wscale 7], length 0
```

在客户端 192.168.10.204 上抓包可以看到数据包返回的 ip 为 lvs 的 vip 地址
```bash
[root@client ~]$ tcpdump -nn -i eth0 tcp and src net 10.0.0.0/24
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes

16:35:06.475184 IP 10.0.0.100.80 > 192.168.10.204.60112: Flags [S.], seq 992418820, ack 581816800, win 65160, options [mss 1460,sackOK,TS val 3709601076 ecr 1142069726,nop,wscale 7], length 0
```


实验二示意图如下：
![](img/2023-07-08-18-03-34.png)

实验一的 lvs 只有上图中的 lvs-1


# <font color=red>实验问题</font>
- php-fpm 的 session 看不到
session 信息保存到文件中也看不到？

- redis 无法做会话保持
见下面 redis 部分说明

- 实验二中浏览器跨域访问问题
客户端 192.168.10.204 用 curl 命令访问正常
windows 主机上用  curl 和网页浏览器通过反向代理 lvs 的 VIP 10.0.0.100 访问
windows 主机和网页浏览器可以访问后端服务器的宿主机 10.0.0.208:8080 或 10.0.0.208:8081



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

********************************************

# 实验二：keepalived 调度
在实验一的基础上，对 LVS 服务器实现高可用

- 后端服务器，即 10.0.0.208 宿主机上的容器不变
- 新增加一个 LVS 服务器，两个服务器在两个 ubuntu22.04 系统上，安装 keepalived 
  - lvs-1
  ubuntu 22.04，NAT 模式网卡，IP 为 10.0.0.206
  - lvs-2
  ubuntu 22.04，NAT 模式网卡，IP 为 10.0.0.207
  - 两个 lvs 对外的 VIP 为 10.0.0.100
  MASTER/BACKUP 模式，非抢占（nopreempt）
- 利用 keepalived 的 virtual_server 实现对后端两个 nginx 服务器的调度
  通过防火墙标签来指定 virtual_server
- keepalived 配置邮件通知脚本，实现故障等的邮件通知功能


## keepalived 实现两个 lvs 高可用


### 添加 host-only 模式网卡用于 vrrp 通告
active 节点会定期发送 vrrp 通告，默认设置用多播地址 224.0.0.18，或则自定义单播地址，
当 backup 节点未及时收到 vrrp 通告（默认 3 次），则会认为 active 节点出故障，从而选举新的 active 节点
默认通告时间为 1s

```bash
[root@lvs-2 ~]$ systemctl status keepalived.service
● keepalived.service - Keepalive Daemon (LVS and VRRP)
     Loaded: loaded (/lib/systemd/system/keepalived.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2023-07-07 20:10:17 CST; 18min ago
   Main PID: 1975 (keepalived)
      Tasks: 3 (limit: 2178)
     Memory: 2.3M
        CPU: 359ms
     CGroup: /system.slice/keepalived.service
             ├─1975 /usr/sbin/keepalived --dont-fork -D -S 6
             ├─1976 /usr/sbin/keepalived --dont-fork -D -S 6
             └─1977 /usr/sbin/keepalived --dont-fork -D -S 6

Jul 07 20:10:24 lvs-2 Keepalived_healthcheckers[1976]: Removing service [172.27.0.30]:none:80 from VS FWM 100
Jul 07 20:10:24 lvs-2 Keepalived_healthcheckers[1976]: HTTP_CHECK on service [172.27.0.31]:none:80 failed after 3 retries.
Jul 07 20:10:24 lvs-2 Keepalived_healthcheckers[1976]: Removing service [172.27.0.31]:none:80 from VS FWM 100
Jul 07 20:10:24 lvs-2 Keepalived_healthcheckers[1976]: Lost quorum 1-0=1 > 0 for VS FWM 100
Jul 07 20:10:26 lvs-2 Keepalived_vrrp[1977]: (VI_1) Sending/queueing gratuitous ARPs on eth0 for 10.0.0.100
Jul 07 20:10:26 lvs-2 Keepalived_vrrp[1977]: Sending gratuitous ARP on eth0 for 10.0.0.100
Jul 07 20:10:26 lvs-2 Keepalived_vrrp[1977]: Sending gratuitous ARP on eth0 for 10.0.0.100
Jul 07 20:10:26 lvs-2 Keepalived_vrrp[1977]: Sending gratuitous ARP on eth0 for 10.0.0.100
Jul 07 20:10:26 lvs-2 Keepalived_vrrp[1977]: Sending gratuitous ARP on eth0 for 10.0.0.100
Jul 07 20:10:26 lvs-2 Keepalived_vrrp[1977]: Sending gratuitous ARP on eth0 for 10.0.0.100
```


为了不干扰正常业务，也为了安全（vrrp 通告内容未加密，明文），可以单独用一个网卡

添加一个 host-only 模式网卡，因为客户端的宿主机也用 host-only 模式网卡，地址为 192.168.10.204,
虚拟机中仅主机模式配置的网段为 192.168.10.0/24，因此为了和其他机器隔离，用 192.168.0.0/24 网段

- lvs-1 server 配置 ip 为 192.168.0.206
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
    eth1:
      match:
        name: eth1
      addresses: 
      - 192.168.0.206/24
```

- lvs-2 server 配置 ip 为 192.168.0.207


### 安装 keepalived
两个 lvs server 均安装 keepalived
ubuntu22.04 包安装，安装版本为 v2.2.4

```bash
[root@lvs-1 ~]$ sudo apt update && sudo apt install -y keepalived
```

### 添加配置文件
默认安装 keepalived 后无法通过 systemctl 启动，因为缺少配置文件，配置文件可以从自带的 sample 复制到指定位置

- 查看 sample 配置文件
```bash
[root@lvs-1 ~]$ dpkg -L keepalived | grep -Ei ".conf"
/etc/dbus-1/system.d/org.keepalived.Vrrp1.conf
/usr/share/doc/keepalived/keepalived.conf.SYNOPSIS
/usr/share/doc/keepalived/samples/keepalived.conf.HTTP_GET.port
/usr/share/doc/keepalived/samples/keepalived.conf.IPv6
/usr/share/doc/keepalived/samples/keepalived.conf.PING_CHECK
/usr/share/doc/keepalived/samples/keepalived.conf.SMTP_CHECK
/usr/share/doc/keepalived/samples/keepalived.conf.SSL_GET
/usr/share/doc/keepalived/samples/keepalived.conf.UDP_CHECK
/usr/share/doc/keepalived/samples/keepalived.conf.conditional_conf
/usr/share/doc/keepalived/samples/keepalived.conf.fwmark
/usr/share/doc/keepalived/samples/keepalived.conf.inhibit
/usr/share/doc/keepalived/samples/keepalived.conf.misc_check
/usr/share/doc/keepalived/samples/keepalived.conf.misc_check_arg
/usr/share/doc/keepalived/samples/keepalived.conf.quorum
/usr/share/doc/keepalived/samples/keepalived.conf.sample
```

- 查看 keepalived 配置文件的指定位置
```bash
[root@lvs-1 ~]$ vim /lib/systemd/system/keepalived.service
```
```bash
[Unit]
Description=Keepalive Daemon (LVS and VRRP)
After=network-online.target
Wants=network-online.target
# Only start if there is a configuration file
ConditionFileNotEmpty=/etc/keepalived/keepalived.conf

[Service]
Type=notify
# Read configuration variable file if it is present
EnvironmentFile=-/etc/default/keepalived
ExecStart=/usr/sbin/keepalived --dont-fork $DAEMON_ARGS
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

- 根据配置文件路径，将样本配置拷贝到指定位置
```bash
[root@lvs-1 ~]$ cp /usr/share/doc/keepalived/samples/keepalived.conf.sample /etc/keepalived/keepalived.conf
```

- 配置文件设置参数时注意选项所在的位置


### 设置全局配置 global_defs
> 查看 keepalived 配置文件参数：[manpage](https://www.keepalived.org/manpage.html)

- 可以 `man keepalived.conf` 查看配置文件参数说明 


修改样本配置文件，全局配置放在 `/etc/keepalived/keepalived.conf` 文件中

```bash
! Configuration File for keepalived

global_defs {
   router_id lvs-1
   vrrp_skip_check_adv_addr
   ! vrrp_mcast_group4 224.0.0.20
}

include /etc/keepalived/conf.d/*.conf
```
- `router_id` 标识当前 keepalived server，因为 keepalived 通过 VRRP 协议实现 
high-availability，而 VRRP 最初是为了实现网关的高可用，因此名字为 `router_id`
- `vrrp_mcast_group4` 为多播地址，keepalived 各节点之间需要发布 VRRP 通告，默认使用
多播地址 `244.0.0.18`，可以修改，或者改为单播形式，这里不用多播


### 配置虚拟路由器 vrrp_instance
>  A  VRRP  Instance is the VRRP protocol key feature. 
> It defines and con-figures VRRP behaviour to run on a specific interface.  
> Each  VRRP  Instance is related to a unique interface.

一个 vrrp_instance 相当于一个业务，这里两个 lvs server 提供一个业务，因此属于一个
vrrp_instance，该配置可以单独在子文件夹中，即全局配置中包含的路径 `/etc/keepalived/con.d/*.conf`

1. lvs-1 上配置如下
```bash
vrrp_instance VI_1 {
    state BACKUP
    interface eth1
    nopreempt
    virtual_router_id 100
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass Byxf885j
    }
    virtual_ipaddress {
        10.0.0.100/24 dev eth0 label eth0:1
    }
    unicast_src_ip 192.168.0.206
    unicast_peer {
       192.168.0.207
    }
}
```
- state 
可以为 `MASTER|BACKUP`，如果为 `MASTER`，且优先级 priority 比 `BACKUP` 节点高，
则当主节点出故障， vip 漂移到从节点后，主节点又恢复，则会抢回 vip，即使设置非抢占 `nopreempt` 模式

本实验中使用非抢占模式，因为抢占后 vip 变化会引起抖动，客户端原先已经存了之前 vip 的 mac 地址，又要
变更 mac 地址

使用非抢占模式，即设置 `nopreempt`，则两个 lvs server 设置的状态都为 `BACKUP`，而优先级设置不同


- interface
vrrp 通告用的网络接口，这里用 host-only 模式的网卡，即 eth1

- nopreempt
非抢占模式

- priority
优先级高的在选举 master 的会当选为 master
优先级的范围为 1-255

但在最开始开启 keepalived 服务时，如果优先级低的节点先开启服务，则会成为 active server 得到 vip

- advert_int
vrrp 通告时间间隔，默认 1s，可以修改

- authentication 
用于认证身份，但该功能已经在 VRRPv2 中被移除，除非配置单播时仍可使用

```bash
# Note: authentication was removed from the VRRPv2 specification by
# RFC3768 in 2004.
#   Use of this option is non-compliant and can cause problems; avoid
#   using if possible, except when using unicast, where it can be helpful.
authentication {
    # PASS|AH
    # PASS - Simple password (suggested)
    # AH - IPSEC (not recommended))
    auth_type PASS

    # Password for accessing vrrpd.
    # should be the same on all machines.
    # Only the first eight (8) characters are used.
    auth_pass 1234
}
```

- virtual_ipaddress
即 virtual_instance 的 VIP 地址，可以配置多个，这里就用一个地址，客户端访问的地址
该地址绑定在 eth0 NAT 模式的网卡上，相当于在 eth0 网卡上增加一个网卡接口，设置一个别名

```bash
[root@lvs-1 conf.d]$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:0c:29:fb:90:06 brd ff:ff:ff:ff:ff:ff
    altname enp2s1
    altname ens33
    inet 10.0.0.206/24 brd 10.0.0.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
    inet 10.0.0.100/24 scope global secondary eth0:1
       valid_lft forever preferred_lft forever
    inet6 fe80::20c:29ff:fefb:9006/64 scope link
       valid_lft forever preferred_lft forever
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:0c:29:fb:90:10 brd ff:ff:ff:ff:ff:ff
    altname enp2s5
    altname ens37
    inet 192.168.0.206/24 brd 192.168.0.255 scope global noprefixroute eth1
       valid_lft forever preferred_lft forever
    inet6 fe80::20c:29ff:fefb:9010/64 scope link
       valid_lft forever preferred_lft forever
```

- unicast_src_ip and unicast_peer
用于配置单播，unicast_src_ip 为发送通告的源地址，这里为本主机 eth1 网卡的地址
unicast_peer 为一个 vrrp_instance 中其他节点的接收 vrrp 通告的地址，这里只有
两个节点，因此为另一个 lvs server 的 eth1 地址，即 192.168.0.207
 

2. lvs-2 配置
```bash
vrrp_instance VI_1 {
    state BACKUP
    interface eth1
    nopreempt
    virtual_router_id 100
    priority 80
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass Byxf885j
    }
    virtual_ipaddress {
        10.0.0.100/24 dev eth0 label eth0:1
    }
    unicast_src_ip 192.168.0.207
    unicast_peer {
       192.168.0.206
    }
}
```

- 注意 virtual_router_id 和 lvs-1 一致，因为属于一个集群
- authentication 的密码配置也要和 lvs-1 相同
- virtual_ipaddress 也和 lvs-1 相同
- unicast_src_ip 为本机 eth1 网卡的 ip，即 192.168.0.207
- unicast_peer 为 lvs-1 eth1 网卡的 ip，即 192.168.0.206

## keepalived 日志单独保存
默认 keepalived 没有单独的日志，日志在系统日志 `/var/log/syslog` 文件中，可以指定单独日志文件

### 查看 service 文件
```bash
[Unit]
Description=Keepalive Daemon (LVS and VRRP)
After=network-online.target
Wants=network-online.target
# Only start if there is a configuration file
ConditionFileNotEmpty=/etc/keepalived/keepalived.conf

[Service]
Type=notify
# Read configuration variable file if it is present
EnvironmentFile=-/etc/default/keepalived
ExecStart=/usr/sbin/keepalived --dont-fork $DAEMON_ARGS
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
```
启动时可以指定参数到环境变量 `$DAEMON_ARGS`，环境变量文件在 `/etc/default/keepalived` 文件中
初始该文件中环境变量没有参数
```bash
# Options to pass to keepalived

# DAEMON_ARGS are appended to the keepalived command-line
DAEMON_ARGS=""
```

### 查看 keepalived 参数
`man keepalived` 查看其支持的参数

```bash
-D, --log-detail
    Detailed log messages.

-S, --log-facility={0-7|local{0-7}|user|daemon}
    Set syslog facility to LOG_LOCAL[0-7], LOG_USER or LOG_DAEMON.  The default syslog facility is LOG_DAEMON.
```
因此可以设置 `-D` 显示详细的日志信息，通过 `-S` 指定 log facility，即日志类别，如指定未被使用的 6 
```bash
DAEMON_ARGS="-D -S 6"
```

- 修改配置后重新加载配置并重启服务
```bash
[root@lvs-1 rsyslog.d]$ systemctl daemon-reload
[root@lvs-1 rsyslog.d]$ systemctl restart rsyslog.service
```

### 修改 rsyslog 日志文件配置
默认的 rsyslog 日志文件的配置在 `/etc/rsyslog.d` 目录下，默认配置为 `50-default.conf`

```bash
[root@lvs-1 conf.d]$ cd /etc/rsyslog.d/
[root@lvs-1 rsyslog.d]$ ls
20-ufw.conf  21-cloudinit.conf  50-default.conf  51-custom.conf  postfix.conf
```

可以将自定义设置放在自定义文件 `51-custom.conf` 文件中，该文件为自己创建的文件，通过
前面的数字可以指定调用生效的顺序，在 `/etc/rsyslog.conf` 文件中包含了 `/etc/rsyslog.d/*.conf`
因此，该目录下以 `.conf` 结尾的文件都会被调用

定义规则如下：
```bash
local6.info           /var/log/keepalived.log
```

修改 rsyslog 规则后重启服务
```bash
[root@lvs-2 ~]$ systemctl restart rsyslog.service
```


## keepalived 配置后端 nginx 调度
### 防火墙打标签 
实验一中已经打过防火墙标签，这里需要替换原来的标签

实验一的防火墙标签设置：
```bash
[root@lvs-1 ~]$ iptables -t mangle -A PREROUTING -d 10.0.0.206 -p tcp -m multiport --dports 80,443 -j MARK --set-mark 1
```

查看 mangle 表的 PREROUTING 链的规则，通过 `--line-number` 显示序号，替换该规则的目标 ip 地址为 VIP 地址

```bash
[root@lvs-1 conf.d]$ iptables -t mangle -L PREROUTING -nv --line-number
```

替换规则，这里只有原来加的一条规则，因此序号为 1
```bash
iptables -t mangle -R PREROUTING 1 -i eth0 -d 10.0.0.100 -p tcp -m multiport --dports 80,443 -j MARK --set-mark 100
```

前面实验已经安装过 `iptables-persistent`，因此这里修改规则后将新规则保存到 `/etc/iptables/rule.v4` 文件中，
下次开机将自动加载新的规则
```bash
[root@lvs-2 keepalived]$ iptables-save > /etc/iptables/rules.v4
```


### 配置后端 nginx 服务器调度 

#### 配置后端服务器的调度规则
通过 virtual_server 配置 IPVS 集群，可以设置调度算法等，类似用 ipvsadm 创建的规则
可以通过 `man keepalived.conf` 查看配置，部分内容如下：

```bash
Virtual server(s)
  A virtual_server can be a declaration of one of <IPADDR> [<PORT>] , fwmark <INTEGER> or group <STRING>

  The syntax for virtual_server is :

  virtual_server <IPADDR> [<PORT>]  |
  virtual_server fwmark <INTEGER> |
  virtual_server group <STRING> {
      # LVS scheduler
      lvs_sched rr|wrr|lc|wlc|lblc|sh|mh|dh|fo|ovf|lblcr|sed|nq

      # Enable flag-1 for scheduler (-b flag-1 in ipvsadm)
      flag-1
      # Enable flag-2 for scheduler (-b flag-2 in ipvsadm)
      flag-2
      # Enable flag-3 for scheduler (-b flag-3 in ipvsadm)
      flag-3
      # Enable sh-port for sh scheduler (-b sh-port in ipvsadm)
      sh-port
      # Enable sh-fallback for sh scheduler  (-b sh-fallback in ipvsadm)
      sh-fallback
      # Enable mh-port for mh scheduler (-b mh-port in ipvsadm)
      mh-port
      # Enable mh-fallback for mh scheduler  (-b mh-fallback in ipvsadm)
      mh-fallback
      # Enable One-Packet-Scheduling for UDP (-o in ipvsadm)
      ops
```

前面已经打过防火墙标签了，因此可以通过 fwmark 指定设置的防火墙标签 100
```bash
virtual_server fwmark 100 {
    delay_loop 6
    lb_algo wrr
    lb_kind NAT
    persistence_timeout 50
    protocol TCP

    real_server 172.27.0.30 80 {
        weight 1
        HTTP_GET {
            url {
              path /index.html
              status_code 200
            }
            connect_timeout 3
            retry 3
            delay_before_retry 3
        }
    }

    real_server 172.27.0.31 80 {
        weight 1
        HTTP_GET {
            url {
              path /index.html
              status_code 200
            }
            connect_timeout 3
            retry 3
            delay_before_retry 3
        }
    }
}
```
- `real_server` 指定后端服务器的地址，即 10.0.0.208 服务器的两个 nginx 容器
- `persistence_timeout` 定义多长时间内将请求都调度到同一个后端服务器上，即持久连接时长，单位 s

keepalived 可以对后端服务器进行主动健康性检测，检测的方法可以用七层和四层的方式，
这里用七层的方式，即通过 `HTTP_GET` 方式，通过访问指定 url 文件，检测返回的状态码

如果用四层检测，用 `TCP_CHECK` 方式，指定 ip 和端口


#### 修改 ipvs 规则并保存
- 实验一中已经通过 ipvsadm 设置过调度规则，需要先清除原来的规则
```bash
[root@lvs-1 keepalived]$ ipvsadm -C
```

- 重启 keepalived 服务，可以通过 ipvsadm 查看 ipvs 规则
当两个 nginx server 都启动运行时，查看 ipvsadm 规则如下：
```bash
[root@lvs-1 keepalived]$ ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
FWM  1 wrr
  -> 172.27.0.30:80               Masq    1      0          0
  -> 172.27.0.31:80               Masq    1      0          0
FWM  100 wrr persistent 50
```

- 将新的规则保存到 `/etc/ipvsadm.rules` 文件中
前面安装过 `iptables-persistent` 工具，可以通过命令保存新的规则
```bash
[root@lvs-1 keepalived]$ service ipvsadm save
 * Saving IPVS configuration...   
```
保存后重新时新的规则生效


- 将其中一个 nginx 容器删除后，再次查看，无该服务器的调度规则
```bash
[root@lvs-1 keepalived]$ ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
FWM  100 wrr persistent 50
  -> 172.27.0.31:80               Masq    1      0          0
```

## 后端服务器路由和防火墙规则修改
实验一中将后端服务器的宿主机 10.0.0.208 的网关指向 lvs 的 vip，这里需要修改为 10.0.0.100
同样防火墙规则中的 ip 地址也需要修改为新的 vip 地址 10.0.0.100

- 修改网卡配置文件
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
        via: 10.0.0.100
      nameservers:
         addresses: [10.0.0.2]
```
修改后用 `netplan apply` 使其生效，查看路由规则
```bash
[root@docker nginx]$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         10.0.0.100      0.0.0.0         UG    100    0        0 eth0
10.0.0.0        0.0.0.0         255.255.255.0   U     100    0        0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 docker0
172.27.0.0      0.0.0.0         255.255.0.0     U     0      0        0 br-455a33a641b6
172.27.0.0      0.0.0.0         255.255.0.0     U     425    0        0 br-455a33a641b6
``` 

- 替换原来的防火墙规则
查看原来的规则
```bash
[root@docker nginx]$ iptables -t filter -L FORWARD -n --line-number
Chain FORWARD (policy DROP)
num  target     prot opt source               destination
1    DOCKER-USER  all  --  0.0.0.0/0            0.0.0.0/0
2    DOCKER-ISOLATION-STAGE-1  all  --  0.0.0.0/0            0.0.0.0/0
3    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
4    DOCKER     all  --  0.0.0.0/0            0.0.0.0/0
5    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0
6    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0
7    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
8    DOCKER     all  --  0.0.0.0/0            0.0.0.0/0
9    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0
10   ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0
11   ACCEPT     all  --  10.0.0.206           0.0.0.0/0
```

替换规则：
```bash
[root@docker nginx]$ iptables -t filter -R FORWARD 11 -s 10.0.0.100 -j ACCEPT
```


## 客户端连接测试
客户端为单独一个 ubuntu22.04 主机，ip 为 192.16.10.204，和实验一相同

### 客户端通过 curl 访问 nginx 服务器
```bash
[root@client ~]$ curl 10.0.0.100/index.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

### 抓包查看具体访问的 nginx 服务器 ip
- 在后端服务器的宿主机上抓包
```bash
[root@docker ~]$ tcpdump -nn tcp port 80 and src host 192.168.10.204 and dst net 172.27.0.0/16
```
客户端地址为  192.168.10.204


- 客户端通过 curl 命令访问
```bash
[root@client ~]$ for((i=0;i<4;++i));do curl -I 10.0.0.100/index.html; sleep 1; done
```

注意前面做了 50 秒的持久连接，因此抓包看到短时间内都是只调度到一个服务器上

将前面 virtual_server 中持久化设置注释，则可以看到后端服务器轮流提供服务
```bash
virtual_server fwmark 100 {
    delay_loop 6
    lb_algo wrr
    lb_kind NAT
    ! persistence_timeout 50
    protocol TCP

    real_server 172.27.0.30 80 {
        weight 1
        HTTP_GET {
            url {
              path /index.html
              status_code 200
            }
            connect_timeout 3
            retry 3
            delay_before_retry 3
        }
    }

    real_server 172.27.0.31 80 {
        weight 1
        HTTP_GET {
            url {
              path /index.html
              status_code 200
            }
            connect_timeout 3
            retry 3
            delay_before_retry 3
        }
    }
}
```
修改后重新加载配置文件 `systemctl reload keepalived.service` 使其生效

## <font color=red>浏览器访问是跨域问题</font>
客户端 192.168.10.204 通过 curl 命令访问 ip 能正常访问，但在本机 windows 上访问
vip 10.0.0.100 失败，但直接访问后端服务器的宿主机地址和端口（nginx 容器做了端口曝露）10.0.0.208:8080
能访问成功

通过 F12 可以查看失败提示，`Referrer Policy: strict-origin-when-cross-origin`


- 跨域问题解释：[跨源资源共享（CORS）](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/CORS)

- 跨域问题解决方案：
[How do I add Access-Control-Allow-Origin in NGINX?](https://serverfault.com/questions/162429/how-do-i-add-access-control-allow-origin-in-nginx)
[Nginx配置跨域请求 Access-Control-Allow-Origin *](https://segmentfault.com/a/1190000012550346)


添加头部信息用到模块 [ngx_http_headers_module](https://nginx.org/en/docs/http/ngx_http_headers_module.html)
该模块不用额外编译添加，直接可以使用，利用 `add_header` 添加头部信息

宿主机的目录挂载到容器中对配置文件做持久化，从宿主机中修改 nginx 配置文件
```bash
add_header Access-Control-Allow-Origin * always;
```
将上述指令添加到 http 指令块中

进入容器中，执行 `nginx -s reload` 重新加载配置文件


结果：
windows 主机上用  curl 和网页浏览器通过反向代理 lvs 的 VIP 10.0.0.100 访问
windows WSL 上用 curl 访问：
```bash
lx@LAPTOP-VB238NKA:~$ curl 10.0.0.100/index.html
curl: (7) Failed to connect to 10.0.0.100 port 80: Connection refused
```
网页浏览器访问：
```bash
Request URL: http://10.0.0.100/index.html
Referrer Policy: strict-origin-when-cross-origin
```

windows 主机和网页浏览器可以访问后端服务器的宿主机 10.0.0.208:8080 或 10.0.0.208:8081





# 实验三 Haproxy 反向代理
利用 Haproxy 将客户端的请求调度到后端的两个 nginx 服务器上



# 实验四 ELK 收集日志
- nginx 服务器所在的宿主机 10.0.0.208 上安装 filebeat，来收集日志
- filebeat 收集的日志发送到实验二中的 redis 集群中做缓存
redis 还是用实验二中配置的一主两从，配置时将三个 redis 的地址都写上


## 安装 filebeat

- 下载镜像安装包
> [filebeat](https://mirrors.tuna.tsinghua.edu.cn/elasticstack/apt/8.x/pool/main/f/filebeat/)

- 安装
```bash
[root@docker src]$ ls
filebeat-8.8.2-amd64.deb  
[root@docker src]$ dpkg -i filebeat-8.8.2-amd64.deb
```

- filebeat 和 elasticsearch 都用相同的版本 8.8.2


## 修改 nginx 日志格式
将 nginx 的访问日志改为 JSON 格式，错误日志保留原来格式
nginx 日志做了持久化处理

修改 nginx 配置文件中的访问日志的格式：
```bash
log_format access_json escape=json '{'
    '"@timestamp": "$time_iso8601",'
    '"remote_addr": "$remote_addr",'
    '"request_method": "$request_method",'
    '"request_uri": "$request_uri",'
    '"status": "$status",'
    '"body_bytes_sent": "$body_bytes_sent",'
    '"http_referer": "$http_referer",'
    '"http_user_agent": "$http_user_agent"'
'}';
access_log  logs/access_json.log;  
```

## 配置 filebeat 收集 nginx 的日志
> [filestream input](https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-input-filestream.html)

修改 filebeat.yml 文件：

- 输入为 filestream 类型
```bash
filebeat.inputs:
# filestream is an input for collecting log messages from files.
- type: filestream
  # Unique ID among all inputs, an ID is required.
  id: nginx-access-log
  # Change to true to enable this input configuration.
  enabled: true
  # Paths that should be crawled and fetched. Glob based paths.
  paths:
    - /docker-02/web/nginx/logs/access_json.log
  tags: ["nginx-access"]
  parsers:
    - ndjson:
      target: ""
      add_error_key: true
      message_key: log

- type: filestream
  id: nginx-error-log
  enabled: true
  paths:
    - /docker-02/web/nginx/logs/error.log
  tags: ["nginx-error"]
  parsers:
    - ndjson:
      target: ""
      add_error_key: true
      message_key: log
```

- 输出到 redis 
> [Configure the Redis output](https://www.elastic.co/guide/en/beats/filebeat/current/redis-output.html)

```bash
# ------------------------------ Redis Output -------------------------------
output.redis:
  hosts: 
    - "10.0.0.208:6370"
    - "10.0.0.208:6371"
    - "10.0.0.208:6372"
  password: "123456"
  db: 0
  timeout: 5
  key: "nginx"
  keys:
    - key: "nginx-access"   
      when.contains:
        tags: "nginx-access"
    - key: "nginx-error"  
      when.contains:
        tags: "nginx-error"
```

- 可以利用 inputs 模块定义的 tags 将访问日志和错误日志分别存放在 nginx 不同的 key 中 
- filebeat 支持 hosts 写多个
> If load balancing is enabled, the events are distributed to the servers in the list. 
> If one server becomes unreachable, the events are distributed to the reachable servers only.


## 测试 redis 接收日志
- 共有三个 redis 容器，配置哨兵，分别进入三个 redis 容器中查看
```bash
127.0.0.1:6379> keys  nginx*
1) "nginx-error"
2) "nginx-access"
```
可以通过 `info replication` 查看各节点状态，最初一个 master，两个 slave
从节点配置只读，因此 filebeat 会找到 master 节点写入再同步到 slave 节点

- 用 `docker stop` 命令将 master 节点的 redis 容器停止
通过访问 nginx 网页，查看两外两个 slave 节点中的一个变为 master，数据写入到 redis 不受影响

- 用 `docker start` 命令将之前停止的 redis 容器重新启动
可以看到新的数据同步到改节点，该节点变为 slave 节点


## logstash 过滤日志
- logstash 从 redis 获取数据，进行过滤处理后发送给 elasticsearch

### <font color=red>问题</font>
- logstash redis input 插件中 host 如果将三个 redis 服务器都写上，
虽然也能获取数据，但会报错，因为不能从 slave 节点采集数据

```bash
input {
	redis {
        host => "10.0.0.208"
        port => "6370"
		password => "123456"
		db => "0"
		data_type => 'list'
		key => "nginx"
	}
	redis {
        host => "10.0.0.208"
        port => "6371"
		password => "123456"
		db => "0"
		data_type => 'list'
		key => "nginx"
	}
	redis {
        host => "10.0.0.208"
        port => "6372"
		password => "123456"
		db => "0"
		data_type => 'list'
		key => "nginx"
	}
}
```

- 不支持 host 写多个，host 和 port 要分开写
和 filebeat 不同，filebeat 可以写多个 host，跳过不能写的 host
```bash

```




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
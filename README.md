# Cluster


## 架构

运维主机：192.168.10.100

nginx 代理：192.168.10.8

master 节点：192.168.10.10-12

worker 节点：192.168.10.13-15



## 准备
**所有操作都在运维节点上运行，步骤如下：**

- clone 项目
  - git clone https://gitee.com/mings135/k8s-cluster.git
- 设置 ssh 免密登录到所有 k8s 节点
  - ssh-keygen -t rsa -b 2048
  - ssh-copy-id -i ~/.ssh/id_rsa.pub root@x.x.x.x
- 根据实际情况修改 config 目录下的 kube.conf 配置



**安装配置代理（master 节点 > 1）：**

- 安装集群前：`Nginx` 4 层代理需配置到第一个台 k8s 的主节点
- 安装集群后，`Nginx` 4 层代理需配置到所有 k8s 的主节点



## 初始化
**所有操作都在运维节点上运行**



### 自签 CA（可选）

- K8s 的  CA 证书默认10 年，其余 1 年
- 如果对默认有效期不满足的，可以执行本步骤（有效期可以自定义）

```shell
# 运维主机：本地生成 ca（生成后最好做个备份，以免重复执行后，覆盖掉）
sh remote_install.sh ca

# 生成证书后最好备份一下，以防丢失
tar -zcvf pki.tar.gz pki/
```



### 配置环境

```shell
# 分发 k8s project（cluster 目录） 到各个节点
sh remote_install.sh distribute

# 为各个节点生成配置文件
sh remote_install.sh make

# 为各个节点运行初始化安装
sh remote_install.sh initial

# 也可用使用如下命令，自动依次运行上面命令
sh remote_install.sh all
```

**注意：非并发执行，节点过多会比较慢**



### 生成证书（可选）

- K8s 的  CA 证书默认10 年，其余 1 年
- 如果对默认有效期不满足的，可以执行本步骤（有效期可以自定义）
- 执行之前，请确认已经执行过`自签CA`，如果没有，请重复`初始化`的所有步骤

```shell
# 运维主机：为 master 节点创建自定义有效期的证书（不包含 kubelet 证书）
sh  remote_install.sh certs
```



### 更新 hosts
**注意：如果已使用外部 DNS 解析各个 k8s 节点的域名，请跳过此步骤**

- 添加各个节点的主机名解析信息到 /etc/hosts 中
- 如果是二次安装或者扩容，请将 `INIT_ETC_HOSTS` 设置为 'y'

```shell
# 该操作会更新 kube.conf，然后根据 kube.conf 更新 /etc/hosts
sh remote_install.sh update_hosts
```



## 安装

- 在第一台 k8s master 节点上初始化集群
  - 请确认已经配置好 4 层代理到 api server 6443 端口
  - 请确认已经配置好 DNS 域名解析 或 执行过 update_hosts

```shell
# pull 集群所需镜像
kubeadm config --config kubeadm-config.yaml images pull

# 初始化集群
kubeadm init --config kubeadm-config.yaml --upload-certs | tee kubeadm-init.log

# 执行 init 后产生的 命令
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
kubeadm join xxx

# 同时 scp 到运维主机上
mkdir ~/.kube
scp 192.168.10.10:/etc/kubernetes/admin.conf ~/.kube/config

# 创建 flannel 网络
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```



## 优化

### kubelet 证书（可选）

- 运维主机：执行远程签发所有 k8s 节点 kubelet 证书
  - 执行之前，请确认已经执行过`自签CA` 和 `生成证书`,，如果没有，请勿执行！

```shell
sh remote_install.sh kubelet
```



### Nginx 配置

修改 nginx 代理配置，使其代理至所有 master 节点的 api server（负载均衡）

也可以添加 keepalived 实现高可用

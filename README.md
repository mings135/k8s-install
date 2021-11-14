# K8S Install

基于 kubeadm 自动部署 k8s 集群



## Environment

- `Linux：`CentOS7.9，支持 Rocky8.4、Debian10、Debian11
- `Kubernetes：`1.20.7，支持 1.18.* ~ 1.22.* 版本
- `CRI：` Containerd or Docker，推荐：Containerd
- `Docker：`19.03.15，建议不要超过 19.03
  - Debian10：不推荐
  - Rocky8.4：仅支持 19.03.13+，建议切换 CgroupV2，使用最新版Docker
  - Debian11：仅支持 20.10.6+，建议使用最新版 Docker
- `Containerd 版本：`1.4.3+，默认使用最新版本
  - Debian10：建议升级内核，否则加入集群会有警告
- `Python 版本：`3.6+
- `Shell：` bash

- `nginx 代理：`无（CLUSTER_VIP 直接用 m1 的 IP 和 api server port）

| Domain | IP            | Role      |
| ------ | ------------- | --------- |
| m1.k8s | 192.168.1.100 | m1/devops |
| m2.k8s | 192.168.1.110 | master    |
| m3.k8s | 192.168.1.120 | master    |
| w1.k8s | 192.168.1.130 | work      |



### Upgrade

- Debian 10 升级内核（推荐）

```shell
echo "deb http://mirrors.aliyun.com/debian buster-backports main" > /etc/apt/sources.list.d/backports.list
apt-get update
apt -t buster-backports  install linux-image-amd64
update-grub
reboot

dpkg --list | grep linux-image
apt purge linux-image-4.19.0-17-amd64
dpkg --list | grep linux-headers
apt purge linux-headers-4.19.0-17-amd64
update-grub
reboot
```



- Rocky 8 切换 CgroupV2（推荐）

```shell
dnf install -y grubby && \
grubby \
  --update-kernel=ALL \
  --args="systemd.unified_cgroup_hierarchy=1"
```



## Ready
- Clone Project

```shell
# 安装必要工具
yum install -y git python3 sshpass rsync
apt-get install -y git python3 sshpass rsync

# clone project
git clone https://gitee.com/mings135/k8s-install.git

# 进入 k8s-install
cd k8s-install
```



- 配置 config 目录下 kube.conf 和 nodes.conf
- 如有 Proxy，须提前配置好，api server 先临时代理到 m1，安装完集群再做修改



## Quick start

```shell
bash remote.sh freelogin
bash remote.sh auto

# 在 m1 上创建 fannel 网络，就可以使用了
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```



## Initial system

- 分发安装脚本到各个节点

```shell
# 配置免密登录
bash remote.sh freelogin

# 分发文件到各个节点
bash remote.sh distribute
```



- 安装集群所需的环境和工具

```shell
# all 一键安装（也可以分步执行 hosts --> init --> cri --> k8s）
bash remote.sh all

# 更新 nodes.conf，然后依据 nodes.conf 更新 /etc/hosts
bash remote.sh hosts

# 初始化和优化系统
bash remote.sh init

# 安装容器运行时
bash remote.sh cri

# 安装 kubeadm 等
bash remote.sh k8s
```



### 证书（可选）

- K8s 的  CA 证书默认10 年，其余 1 年
- 执行以下命令优先创建 50 年的证书（不包含 kubelet，kubelet 需要集群安装后 执行）

```shell
# 本地生成 ca，并分发到各个节点
bash remote.sh ca

# 各个 master 节点自签 k8s 证书
bash  remote.sh certs
```



## Install cluster

- 初始化集群

```shell
# 查看所需镜像
bash remote.sh imglist

# download images
bash remote.sh imgpull

# m1 上初始化集群
bash remote.sh initcluster
```



- 加入集群

```shell
# 生成加入命令
bash remote.sh joincmd

# 加入集群
bash remote.sh joincluster
```



### Kubelet（可选）

- 执行之前，必须先确认已经执行过`证书` 步骤

```shell
# 签发 kubelet 证书
bash remote.sh kubelet

# 完成后可以删除 work 节点上的 pki 目录
bash remote.sh deletepki
```



# Install docker

本地只安装 Docker：

```shell
git clone https://gitee.com/mings135/k8s-install.git
cd k8a-install

# 版本修改成想要安装的
sed -i '/^DOCKER_VERSION=/c DOCKER_VERSION="19.03.15"' config/kube.conf
sed -i '/^K8S_CRI=/c K8S_CRI="docker"' config/kube.conf
sed -i "/=m1/c localhost=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')=m1" config/nodes.conf
bash local.sh record init cri
```


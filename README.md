# K8S Install

基于 kubeadm 自动部署 k8s 集群



## 环境

- `Linux：`CentOS7.9，支持 Rocky8.4、Debian10、Debian11
- `Kubernetes：`1.20.7，支持 1.18.* ~ 1.22.* 版本
- `CRI：` Containerd or Docker，推荐：Containerd
- `Docker：`19.03.15，建议不要超过 19.03
  - Debian10：不推荐，警告较多，建议升级内核
  - Rocky8.4：仅支持 19.03.13+，建议最新版 Docker，切换 CgroupV2
  - Debian11：仅支持 20.10.6+，建议最新版 Docker
- `Containerd 版本：`1.4.3+，默认使用最新版本
  - Debian10：建议升级内核，否则加入集群会有警告
- `Python 版本：`3.6+
- `Shell：` bash



## Cluster node

- `nginx 代理：`无（CLUSTER_VIP 直接用 m1 的 IP 和 api server port）

| Domain | IP            | Role      |
| ------ | ------------- | --------- |
| m1.k8s | 192.168.1.100 | m1/devops |
| m2.k8s | 192.168.1.110 | master    |
| m3.k8s | 192.168.1.120 | master    |
| w1.k8s | 192.168.1.130 | work      |



## Optimization（可选）

> 推荐 ：CentOS7、Debian10 升级内核，Rocky8.4 切换 CgroupV2



### CentOS7

- 升级内核

```shell
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum install https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
# yum --disablerepo="*" --enablerepo="elrepo-kernel" list available
yum install -y --enablerepo="elrepo-kernel" kernel-lt
# grub2-set-default 'CentOS Linux (5.4.107-1.el7.elrepo.x86_64) 7 (Core)'
grub2-set-default 0
grub2-mkconfig -o /boot/grub2/grub.cfg
reboot

rpm -qa | grep kernel
yum remove -y kernel-3.10.0-1160.el7.x86_64 kernel-tools-libs-3.10.0-1160.el7.x86_64 kernel-tools-3.10.0-1160.el7.x86_64
reboot
```



### Rocky8

- 切换 Cgroup V2

```shell
dnf install -y grubby && \
grubby \
  --update-kernel=ALL \
  --args="systemd.unified_cgroup_hierarchy=1"
```



### Debian10

- 升级内核

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



## 准备
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

```


# K8S Install

基于 kubeadm 自动部署 k8s 集群。



## Env

- `Linux：`CentOS7.9，支持 Rocky8、Debian11
- `Kubernetes：`1.20.7，支持 1.20.* ~ 1.24.* 版本
- `Containerd CRI：`默认最新版本，支持 1.4.* ~ 1.6.* （不同系统版本范围有所不同）
  - Debian10：建议升级内核，否则加入集群会有警告
- `Python：`3.6+
- `Shell：` bash
- `Proxy：`None（CLUSTER_VIP 直接用 m1 的 IP）

| Domain | IP            | Role             |
| ------ | ------------- | ---------------- |
| m1.k8s | 192.168.1.100 | master/m1/devops |
| m2.k8s | 192.168.1.110 | master           |
| m3.k8s | 192.168.1.120 | master           |
| w1.k8s | 192.168.1.130 | work             |



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
**Clone Project：**

```shell
# 安装必要工具
yum install -y git python3 sshpass rsync
apt-get install -y git python3 sshpass rsync

# clone project
git clone https://gitee.com/mings135/k8s-install.git

# 进入 k8s-install
cd k8s-install
```



**配置 config 目录下 kube.conf 和 nodes.conf**

- 如存在 Proxy，请先配置 Proxy，IP 和 Port 写入 CLUSTER_VIP 和 CLUSTER_PORT
- 如果没有，直接将 m1 的 IP 填入 CLUSTER_VIP 即可



`注意：`所有操作在 devops 节点上执行



## Quick

**快速安装：**

- 由于网络等问题可能会导致出错，此时脚本会自动退出（部分流程是并发的，可能存在延迟）
- 如果出错，手动解决问题后继续运行 `auto` 即可

```shell
# 配置免密登录，所有节点必须统一密码（否则请自行配置）
bash remote.sh freelogin

# 自动安装
bash remote.sh auto

# 安装完集群后，在 m1 上创建 fannel 网络（也可以使用其他 CNI）
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```



## Initial system

**分发安装脚本到所有节点：**

```shell
# 配置免密登录，所有节点必须统一密码（否则请自行配置）
bash remote.sh freelogin

# 分发文件到各个节点
bash remote.sh distribute
```



**所有节点初始化系统环境：**

```shell
# 更新 nodes.conf，然后依据 nodes.conf 更新 /etc/hosts
bash remote.sh hosts

# 初始化和优化系统
bash remote.sh init

# 安装容器运行时
bash remote.sh cri

# 安装 kubeadm 等
bash remote.sh k8s
```



### Certs（可选）

- K8s 的  CA 证书默认10 年，其余 1 年
- 执行以下命令优先创建 50 年的证书（不包含 kubelet，kubelet 需要集群安装后 执行）

```shell
# 本地生成 ca，并分发到各个节点
bash remote.sh ca

# 各个 master 节点自签 k8s 证书
bash  remote.sh certs
```



## Install cluster

**初始化集群：**

```shell
# 查看所需镜像
bash remote.sh imglist

# download images
bash remote.sh imgpull

# m1 上初始化集群
bash remote.sh initcluster
```



**加入集群：**

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

# 完成后可以清理 work 节点上的 pki 目录
bash remote.sh deletepki
```


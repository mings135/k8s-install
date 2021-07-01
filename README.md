# Cluster

本安装脚本大部分使用的时 shell 编写，极小部分使用了 Python3，用以实现并发远程安装




## 架构

运维节点：192.168.100.31

nginx 代理：无

master 节点：192.168.10.31

worker 节点：192.168.10.32



## 环境

1. 系统版本：Centos7、Centos8
2. k8s 版本：1.19.x、1.20.x（其余版本自行测试）
3. docker 版本：19.03.9
4. Python 版本：3.6+（仅运维主机需要）
5. shell 环境： bash



## 准备
**运维节点上运行如下步骤：**

- clone 项目
  - git clone https://gitee.com/mings135/k8s-install.git
- 设置 ssh 免密登录到所有 k8s 节点
  - ssh-keygen -t rsa -b 2048
  - ssh-copy-id -i ~/.ssh/id_rsa.pub root@x.x.x.x
- 根据实际情况修改 config 目录下的 kube.conf 配置



**安装配置代理（可选）：**

- 请将 `Nginx` 4 层代理配置到第一台 k8s 的主节点
- 具体如何配置 `Nginx` 代理，自行解决，也可以使用其他代理



## 初始化
**所有操作都在运维节点上运行**



### 自签 CA（可选）

- K8s 的  CA 证书默认10 年，其余 1 年
- 如果对默认有效期不满足的，可以执行本步骤（有效期可以自定义）

```shell
# 运维主机：本地生成 ca（生成后做好备份，以免重复执行后，被覆盖）
sh remote.sh ca

# 生成证书后最好备份一下，以防丢失
tar -zcvf pki.tar.gz pki/
```



### 配置环境

```shell
# 分发 k8s project（cluster 目录） 到各个节点
sh remote.sh distribute

# 为各个 mater 节点生成配置文件
sh remote.sh make

# 为各个节点运行初始化、安装应用
sh remote.sh initial

# 也可用使用如下命令，自动依次运行上面命令
sh remote.sh all
```



### 生成证书（可选）

- K8s 的  CA 证书默认10 年，其余 1 年
- 如果对默认有效期不满足的，可以执行本步骤（有效期可以自定义）
- 执行之前，请确认已经执行过`自签CA`，如果没有，请删除记录，重复`初始化`的所有步骤

```shell
# 为 master 节点创建自定义有效期的证书（不包含 kubelet 证书）
sh  remote.sh certs
```



### 更新 hosts
**`注意：`如果已使用外部 DNS 解析各个 k8s 节点的域名，请跳过此步骤**

- 添加各个节点的主机名解析信息到 /etc/hosts 中
- 如需修改或删除原解析信息，请将 `INITIAL_HOSTS` 设置为 'y'

```shell
# 该操作会更新 kube.conf，然后根据 kube.conf 更新 /etc/hosts
sh remote.sh update_hosts
```



## 安装

**所有操作在第一台 k8s master 节点上**



- 请确认已经完成以下内容
  - 配置好 4 层代理到 api server 6443 端口
  - 配置好 DNS 域名解析 或 执行过 update_hosts

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
scp 192.168.10.31:/etc/kubernetes/admin.conf ~/.kube/config

# 创建 flannel 网络
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```



## 优化

### kubelet 证书（可选）

- 运维主机：执行远程签发所有 k8s 节点 kubelet 证书
  - 执行之前，请确认已经执行过`自签CA` 和 `生成证书`，如果没有，请勿执行！

```shell
sh remote.sh kubelet
```



### Nginx 配置（可选）

修改 nginx 代理配置，使其代理至所有 master 节点的 api server（负载均衡）

也可以添加 keepalived 实现高可用

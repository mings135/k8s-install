# K8S Install

基于 kubeadm 自动部署 k8s 集群。所有操作均在运维主机上完成。所有 k8s 节点只需统一 root 密码，开启 ssh 即可，一般情况下无需其他操作。



## Request

- `Linux:` 
  - 支持 AlmaLinux 8、AlmaLinux 9、Debian 11、Debian 12
  - 目前所有资源默认将使用对应的官方资源，请检查自己的网络是否支持
- `Kubernetes:` 
  - 支持 1.22+
  - 1.22 ~ 1.24 官方镜像仓库地址：`k8s.gcr.io`
  - 1.25+ 官方镜像仓库地址：`registry.k8s.io`
  - 国内镜像仓库地址：`registry.cn-hangzhou.aliyuncs.com/google_containers`
  - debian 中，当 k8s 版本 >= 1.25 时，cri-tools  版本须 >= 1.25
  - k8s 版本设置后，建议自行测试 cri-tools 和 containerd 版本是否支持，或使用默认值
  - 1.28 开始官方修改了 k8s 的 apt 和 yum 源
- `Containerd：` 
  - 支持 1.5+
  - 当 cri-tools  版本 >= 1.26 时，containerd 版本须 >= 1.6



**测试环境：**

| Domain | IP             | Role           | System      |
| ------ | -------------- | -------------- | ----------- |
| m1.k8s | 192.168.11.101 | master1/devops | AlmaLinux 8 |
| m2.k8s | 192.168.11.102 | master         | AlmaLinux 9 |
| m3.k8s | 192.168.11.103 | master         | Debian 11   |
| w1.k8s | 192.168.11.104 | work           | Debian 12   |



## Install

- 由于网络/镜像源等问题可能会报错，此时脚本会自动退出（部分流程是并发的，可能存在延迟）
- 如果出错，手动解决问题后继续运行 `auto` 即可
- 如果 debian 安装软件失败，尝试：`apt-get update --allow-releaseinfo-change`

```shell
# 安装必要工具
dnf install -y git python3 sshpass rsync
apt-get update && apt-get install -y git python3 sshpass rsync

# 克隆 project
git clone https://github.com/mings135/k8s-install.git

# 进入 k8s-install
cd k8s-install

# 配置 kube.yaml
vi config/kube.yaml

# 自动安装(-c 安装自签证书, -f 部署 flannel)
bash remote.sh -cf auto
```



## Upgrade

在 config/kube.yaml 中修改或添加如下配置：

```yaml
cluster:
  # 更新到哪个版本
  kubernetesVersion: "1.29.0"
  # 是否更新证书, 默认为 false, 执行 auto 命令时如果没有使用 -c, 建议改为 true
  certificateRenewal: "false"
```



升级集群版本：

- 如果出错，手动解决问题后继续运行 `upgrade` 即可

```shell
# 更新前建议备份下 etcd
bash remote.sh backup
# 更新版本(必须满足 k8s 更新条件, 请自行查看官网)
bash remote.sh upgrade
```


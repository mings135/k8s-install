# K8S Install

基于 kubeadm 自动部署 k8s 集群。

一般情况所有操作均在运维主机上完成即可。

所有 k8s 节点须统一账号密码（非 root 账号须支持 sudo 命令），并开启 ssh。



## Request

- `Linux:` 
  - 支持 AlmaLinux 8、AlmaLinux 9、Debian 11、Debian 12
- `Kubernetes:` 
  - 支持 1.24+
  - 1.24 官方镜像仓库地址：`k8s.gcr.io`
  - 1.25 官方镜像仓库地址：`registry.k8s.io`
  - 国内镜像仓库地址：`registry.cn-hangzhou.aliyuncs.com/google_containers`
- `Containerd：` 
  - 支持 1.5+
- `Other:`
  - 默认所有资源将使用官方地址，请检查自己的网络是否支持
  - 默认安装最新版本的依赖软件，如自定义，请注意版本兼容性



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

# 自动安装(-f 部署 flannel, -la 配置免密登录)
bash remote.sh -fla auto
```



## Upgrade

在 config/kube.yaml 中修改或添加如下配置：

```yaml
cluster:
  # 更新到哪个版本
  kubernetesVersion: "1.31.0"
```



升级集群版本：

- 如果出错，手动解决问题后继续运行 `upgrade` 即可

```shell
# 更新前建议备份下 etcd
bash remote.sh backup
# 更新版本(必须满足 k8s 更新条件, 请自行查看官网)
bash remote.sh upgrade
```



## criUpgrade

在 config/kube.yaml 中修改或添加如下配置：

```yaml
container:
  # 更新到哪个版本(默认 latest)
  criVersion: "1.6.9"
  # 是否重新配置 cri config(默认 false)
  criUpgradeReconfig: "true"
```



升级容器运行时版本：

- 如果出错，手动解决问题后继续运行 `criupgrade` 即可

```shell
bash remote.sh criupgrade
```



## Other

更改集群镜像仓库地址，须同步更改 kube.yaml 相关配置：

```shell
# 集群配置修改
kubectl edit cm -n kube-system kubeadm-config
```



添加集群节点，只须更改 kube.yaml，然后运行 `bash remote.sh auto` 即可

删除集群节点，须同步更改 kube.yaml 相关配置：

```shell
kubectl drain w1.k8s --ignore-daemonsets
kubectl delete nodes w1.k8s
```


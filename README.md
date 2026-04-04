# K8S Install

基于 kubeadm 自动部署 k8s 集群。

正常情况在运维主机上完成所有操作即可。

所有 k8s 节点须统一账号密码（非 root 账号须支持 sudo 命令）。



## Request

- `Linux:` 
  - 支持 Debian 12、Debian 13
- `Kubernetes:` 
  - 支持 1.31.0+
  - 官方镜像仓库地址：`registry.k8s.io`
  - 国内镜像仓库地址：`registry.cn-hangzhou.aliyuncs.com/google_containers`
- `Containerd：` 
  - 支持 1.7.0+
- `Other:`
  - 默认所有资源将使用官方地址，请检查自己的网络是否支持



**测试环境：**

| Domain | IP            | Role           | System    |
| ------ | ------------- | -------------- | --------- |
| m1.k8s | 192.168.11.50 | master1/devops | Debian 13 |
| m2.k8s | 192.168.11.51 | master         | Debian 13 |
| m3.k8s | 192.168.11.52 | master         | Debian 13 |
| w1.k8s | 192.168.11.53 | work           | Debian 13 |



## Install

- 配置文件：`config/kube.yaml`

- 安装报错：由于网络等原因导致，此时脚本会自动退出（部分流程是并发的，可能存在延迟）
- 处理问题：手动解决问题，继续运行 `auto` 原命令
- 常见问题：
  - debian 安装软件失败，尝试：`apt-get update --allow-releaseinfo-change`
  - 网络问题，导致无法下载软件或镜像，尝试：参考 config/example.yaml 修改配置


```shell
# 安装必要工具
apt-get update && apt-get install -y git sshpass rsync curl tar

# 克隆 project
git clone https://github.com/mings135/k8s-install.git

# 进入 k8s-install
cd k8s-install

# 自动安装(-f 部署 flannel, -la 免密登录, 如无配置文件, 将自动生成极简配置, 参考 example.yaml)
bash remote.sh -fla auto
```



## Upgrade cri

在 config/kube.yaml 中修改或添加如下配置：

```yaml
container:
  # 更新到哪个版本(默认 latest)
  criVersion: "2.2.2"
  # 是否重新配置 cri config(默认 false)
  criUpgradeReconfig: "true"
```



升级容器运行时版本：

- 如果出错，手动解决问题后继续运行 `cri` 即可

```shell
bash remote.sh cri
```



## Upgrade cluster

在 config/kube.yaml 中修改配置：

```yaml
cluster:
  # 更新到哪个版本
  kubernetesVersion: "1.35.3"
```



升级集群版本：

- 如果出错，手动解决问题后继续运行 `upgrade` 即可

```shell
# 更新版本(必须满足 k8s 更新条件, 请自行查看官网)
bash remote.sh upgrade
```



## Other

后续功能

- 配置后，可以自动删除节点
- 尝试增加 cilium
- 节点并发更新






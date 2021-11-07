# 安装 k8s 所需应用

# install_docker：安装 docker（支持 centos 7，私有仓库必须 http）
#DOCKER_VERSION='19.03.9'
#PRIVATE_REPOSITORY='192.168.10.38'

# install_containerd：安装 containerd（支持 centos 7 和 8，私有仓库必须 http）
#PRIVATE_REPOSITORY='192.168.10.38'
#IMAGE_REPOSITORY='mings135'

# install_kubeadm：安装 k8s 部署工具和环境（支持 centos 7 和 8，私有仓库必须 http）
#K8S_CRI='containerd'
#K8S_VERSION='1.20.7'


install_docker() {
  # yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo &> /dev/null
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null
  result_msg "添加 docker-ce.repo" || exit 1

  sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
  result_msg "修改 repo 至国内源" || exit 1

  yum install -y docker-ce-${DOCKER_VERSION} docker-ce-cli-${DOCKER_VERSION} containerd.io &> /dev/null
  result_msg "安装 docker ${DOCKER_VERSION}" || exit 1

  mkdir -p /etc/docker
      
  cat > /etc/docker/daemon.json << EOF
{
  "data-root": "/var/lib/docker",
  "storage-driver": "overlay2",
  "insecure-registries": ["${PRIVATE_REPOSITORY}"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m" }
}
EOF

  systemctl enable --now docker &> /dev/null
  result_msg "启动 docker" || exit 1
}


install_containerd() {
  # yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo &> /dev/null
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null
  result_msg "添加 docker-ce.repo" || exit 1

  sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
  result_msg "修改 docker-ce.repo 国内连接" || exit 1

  yum install -y containerd.io &> /dev/null
  result_msg "安装 containerd.io" || exit 1

  mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml
  result_msg "生成 containerd 默认配置" || exit 1

  sed -i "/sandbox_image/s#k8s.gcr.io#${IMAGE_REPOSITORY}#" /etc/containerd/config.toml && \
  sed -i '/endpoint/a \        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor_ip_or_hostname"]\n          endpoint = ["http://harbor_ip_or_hostname"]' /etc/containerd/config.toml && \
  sed -i "/harbor_ip_or_hostname/s#harbor_ip_or_hostname#${PRIVATE_REPOSITORY}#" /etc/containerd/config.toml
  # sed -i '/registry-1.docker.io/s#"https://registry-1.docker.io"#"https://qc20rc43.mirror.aliyuncs.com", "https://registry-1.docker.io"#' /etc/containerd/config.toml
  result_msg "修改 containerd 仓库配置" || exit 1

  sed -i '/runc.options/a \            SystemdCgroup = true' /etc/containerd/config.toml
  result_msg "配置 containerd SystemdCgroup" || exit 1

  systemctl enable --now containerd &> /dev/null
  result_msg "启动 containerd" || exit 1
}
# 安装 CRI（容器运行时），docker or containerd，提供以下函数：
# install_cri

# 必须先执行 init.sh


# 添加 docker repo（centos）
docker_repo_centos() {
  if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null
    result_msg "添加 docker repo"
    sed -e 's+download.docker.com+mirrors.aliyun.com/docker-ce+' \
      -e '/^gpgcheck=1/s/gpgcheck=1/gpgcheck=0/' \
      -i /etc/yum.repos.d/docker-ce.repo
    result_msg "修改 repo source"
  fi
}


# 添加 docker repo（debian）
docker_repo_debian() {
  local docker_list_file='/etc/apt/sources.list.d/docker.list'

  if [ ! -f ${docker_list_file} ]; then
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    result_msg "添加 docker gpg"
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee ${docker_list_file} > /dev/null
    result_msg "添加 docker repo"
    sed -i 's+download.docker.com+mirrors.tuna.tsinghua.edu.cn/docker-ce+' ${docker_list_file}
    result_msg "修改 repo source"
    ${sys_pkg} update > /dev/null
    result_msg "更新 apt"
  fi
}


# 安装 containerd
install_containerd() {
   docker_repo_${sys_release}

   local apps='containerd.io'
   install_apps "${apps}"
}


# 配置 docker
docker_config() {
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
  result_msg "配置 docker"
}


# 配置 containerd
containerd_config() {
  local config_file='/etc/containerd/config.toml'
  local ver=$(containerd -v | awk '{print $3}')

  mkdir -p /etc/containerd && containerd config default > ${config_file}
  result_msg "创建 containerd 默认配置"

  sed -i "/sandbox_image/s#k8s.gcr.io#${IMAGE_REPOSITORY}#" ${config_file}
  result_msg "修改 仓库地址"

  if [ $(echo "${ver%.*} >= 1.6" | bc) -eq 1 ]; then
    sed -i '/SystemdCgroup/s#SystemdCgroup = false#SystemdCgroup = true#' ${config_file}
    result_msg "修改 containerd Cgroup"
    sed -i '/registry.mirrors/a \        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ip_or_hostname"]\n          endpoint = ["http://ip_or_hostname"]' ${config_file} && \
    sed -i "/ip_or_hostname/s#ip_or_hostname#${PRIVATE_REPOSITORY}#" ${config_file}
    result_msg "修改 containerd 私有仓库"
  else
    sed -i '/runc.options/a \            SystemdCgroup = true' ${config_file}
    result_msg "配置 containerd Cgroup"
    sed -i '/endpoint/a \        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ip_or_hostname"]\n          endpoint = ["http://ip_or_hostname"]' ${config_file} && \
    sed -i "/ip_or_hostname/s#ip_or_hostname#${PRIVATE_REPOSITORY}#" ${config_file}
    result_msg "修改 containerd 私有仓库"
  fi
}


# 安装 docker，并配置参数（centos）
docker_centos() {
  install_containerd

  # 必须先安装 docker-ce-cli，否则 docker-ce-cli 将安装最新版本
  local apps="docker-ce-cli-${DOCKER_VERSION} docker-ce-${DOCKER_VERSION}"
  install_apps "${apps}"

  docker_config

  systemctl enable --now docker &> /dev/null
  result_msg "启动 docker"
}


# 安装 docker，并配置参数（debian）
docker_debian() {
  install_containerd

  local apps="docker-ce-cli=5:${DOCKER_VERSION}~3-0~debian-$(lsb_release -cs) docker-ce=5:${DOCKER_VERSION}~3-0~debian-$(lsb_release -cs)"
  install_apps "${apps}"

  docker_config
  
  systemctl restart docker &> /dev/null
  result_msg "重启 docker"
}


# 安装 containerd，并配置参数（centos）
containerd_centos() {
  install_containerd

  containerd_config

  systemctl enable --now containerd &> /dev/null
  result_msg "启动 containerd"
}


# 安装 containerd，并配置参数（debian）
containerd_debian() {
  install_containerd

  containerd_config

  systemctl restart containerd &> /dev/null
  result_msg "重启 containerd"
}


install_cri() {
  ${K8S_CRI}_${sys_release}
}


docker_compose() {
  curl -L "https://get.daocloud.io/docker/compose/releases/download/${DOCKER_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
  chmod +x /usr/local/bin/docker-compose
  result_msg "安装 docker-compose"
}
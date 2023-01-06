# 安装 CRI（容器运行时），docker or containerd，提供以下函数：
# install_cri

# 必须先执行 init.sh


# 添加 docker repo（centos）
docker_repo_centos() {
  if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null
    result_msg "添加 docker repo"
    sed -e 's+download.docker.com+mirrors.tuna.tsinghua.edu.cn/docker-ce+' \
      -e '/^gpgcheck=1/s/gpgcheck=1/gpgcheck=0/' \
      -i /etc/yum.repos.d/docker-ce.repo
    result_msg "修改 docker repo"
    ${sys_pkg} makecache > /dev/null
    result_msg "运行 ${sys_pkg} makecache"
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
  local apps='containerd.io'

  docker_repo_${sys_release}

  # CentOS 查看更多版本：yum list containerd.io --showduplicates | sort -r
  if [ ${sys_release} = 'centos' ] && [ ${CRI_VERSION} ]; then
    apps="${apps}-${CRI_VERSION}"
  fi

  # Debian 查看更多版本：apt-cache madison containerd.io
  if [ ${sys_release} = 'debian' ] && [ ${CRI_VERSION} ]; then
    apps="${apps}=${CRI_VERSION}-1"
  fi

  install_apps "${apps}"
}


# 配置 containerd
containerd_config() {
  local config_file='/etc/containerd/config.toml'
  local ver=$(containerd -v | awk '{print $3}')

  mkdir -p /etc/containerd && containerd config default > ${config_file}
  result_msg "创建 containerd config"

  sed -i "s#\(sandbox_image = \"\).*\(/pause:.*\"\)#\1${IMAGE_REPOSITORY}\2#" ${config_file}
  result_msg "修改 sandbox image"

  if [ $(echo "${ver%.*} >= 1.5" | bc) -eq 1 ]; then
    sed -i 's#SystemdCgroup = false#SystemdCgroup = true#' ${config_file}
    result_msg "修改 containerd Cgroup"
    sed -i '/registry.mirrors/a \        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ip.or.hostname"]\n          endpoint = ["http://ip.or.hostname"]' ${config_file}
    result_msg "增加 containerd 私库配置"
  else
    sed -i '/runc.options/a \            SystemdCgroup = true' ${config_file}
    result_msg "配置 containerd Cgroup"
    sed -i '/endpoint/a \        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ip.or.hostname"]\n          endpoint = ["http://ip.or.hostname"]' ${config_file}
    result_msg "增加 containerd 私库配置"
  fi

  if [ ${PRIVATE_REPOSITORY} ]; then
    sed -i "/ip.or.hostname/s#ip.or.hostname#${PRIVATE_REPOSITORY}#" ${config_file}
    result_msg "修改 containerd 私有仓库"
  fi
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
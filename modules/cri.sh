# 安装 CRI


# 安装 containerd
cri_install_containerd() {
  if [ ${criVersion} = 'latest' ]; then
    local apps="containerd.io"
  elif [ ${SYSTEM_RELEASE} = 'centos' ]; then
    # CentOS 查看更多版本：yum list containerd.io --showduplicates | sort -r
    local apps="containerd.io-${criVersion}"
  elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
    # Debian 查看更多版本：apt-cache madison containerd.io
    local apps="containerd.io=${criVersion}"
  fi
  install_apps "${apps}"
}


# 设置 containerd
cri_config_containerd() {
  local config_file='/etc/containerd/config.toml'
  local config_path='/etc/containerd/certs.d'
  # 创建默认配置
  mkdir -p /etc/containerd && containerd config default > ${config_file}
  result_msg "创建 containerd config"
  # 修改默认配置 sandbox_image
  if [ ${imageRepository} ]; then
    sed -i "s#\(sandbox_image = \"\).*\(/pause:.*\"\)#\1${imageRepository}\2#" ${config_file}
    result_msg "修改 sandbox image"
  fi
  # 修改默认配置 SystemdCgroup
  if cat ${config_file} | grep -Eqi 'SystemdCgroup = '; then
    sed -i 's#SystemdCgroup = false#SystemdCgroup = true#' ${config_file}
    result_msg "修改 containerd Cgroup"
  else
    sed -i '/runtimes.runc.options/a \            SystemdCgroup = true' ${config_file}
    result_msg "新增 containerd Cgroup"
  fi
  # 新增配置 registry.mirrors
  if [ ${privateRepository} ]; then
    # 修改 config_path 值
    sed -i "s#\(config_path = \"\).*\(\"\)#\1${config_path}\2#" ${config_file}
    result_msg "修改 containerd config_path"
    # 增加私库配置
    local scheme=${privateRepository%%://*}
    local url=${privateRepository#*://}
    mkdir -p ${config_path}/${url} \
      && echo "[host.\"${privateRepository}\"]" > ${config_path}/${url}/hosts.toml
    result_msg "增加 containerd 私有仓库"
    # https 开启 skip_verify
    if [ ${scheme} = 'https' ]; then
      echo '  skip_verify = true' >> ${config_path}/${url}/hosts.toml
    fi
  fi
}


# 启动 containerd
cri_start_containerd() {
  # 不同系统启动方式不一样
  if [ ${SYSTEM_RELEASE} = 'centos' ]; then
    systemctl enable containerd &> /dev/null \
      && systemctl restart containerd
    result_msg "启动 containerd"
  elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
    systemctl restart containerd &> /dev/null
    result_msg "重启 containerd"
  fi
}


cri_install() {
  cri_install_containerd
  cri_config_containerd
  cri_start_containerd
}

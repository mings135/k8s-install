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
  mkdir -p ${config_path} && containerd config default > ${config_file}
  result_msg "创建 containerd config"
  # 修改默认配置 sandbox_image
  if [ "${imageRepository}" ]; then
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
  if [ "${privateRepository}" ]; then
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
    if [ "${scheme}" = 'https' ]; then
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


# 更新 containerd 版本   basic_set_repos_cri   update_mirror_source_cache
cri_upgarde_containerd() {
  local config_dir='/etc/containerd'
  local backup_dir="${script_dir}/config/containerd_backup-${criVersion}"
  # 备份 config
  if [ ! -e ${backup_dir}/config.toml ]; then
    mkdir -p ${backup_dir} && /usr/bin/cp -a ${config_dir}/* ${backup_dir}
    result_msg "备份 config"
  fi
  # 停止 kubelet
  kubectl drain ${HOST_NAME} --ignore-daemonsets
  result_msg "腾空 当前节点"
  systemctl stop kubelet
  result_msg "停止 kubelet"
  # 删除重装
  remove_apps 'containerd.io'
  cri_install_containerd
  if [ "${criUpgradeReconfig}" -ne 0 ]; then
    cri_config_containerd
  else
    /usr/bin/cp -a ${backup_dir}/* ${config_dir}
    result_msg "还原 config"
  fi
  cri_start_containerd
  # 启动 kubelet
  systemctl start kubelet
  result_msg "启动 kubelet"
  kubectl uncordon ${HOST_NAME}
  result_msg "解除 当前节点的保护"
  kubectl wait --for=condition=Ready nodes/${HOST_NAME} --timeout=50s
  result_msg "等待 节点 Ready"
  if [ -e ${backup_dir} ]; then
    rm -rf ${backup_dir}
    result_msg "删除 备份 config"
  fi
}


cri_install() {
  cri_install_containerd
  cri_config_containerd
  cri_start_containerd
}


cri_upgrade_version() {
  cri_upgarde_containerd
}

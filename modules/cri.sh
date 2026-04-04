# 安装 CRI

cri_config_repos() {
  # debian 设置 docker 源
  local repo='/etc/apt/sources.list.d/docker.list'
  local key="${GPG_DIR}/docker-archive-keyring.gpg"

  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --yes --dearmor -o ${key}
  result_msg "添加 docker gpg"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=${key}] https://download.docker.com/linux/debian $(lsb_release -cs) stable" >${repo}
  result_msg "添加 docker repo"

  if [[ "${localMirror}" == "true" ]]; then
    sed -i 's+download.docker.com+mirrors.tuna.tsinghua.edu.cn/docker-ce+' ${repo}
    result_msg "修改 repo source"
  fi
}

# 安装 containerd
cri_install_containerd() {

  unhold_pkgs 'containerd'

  if [[ "${criVersion}" == "latest" ]]; then
    install_pkgs "containerd.io"
  else
    install_pkgs "containerd.io=${criVersion}"
  fi

  hold_pkgs 'containerd'
}

# 设置 containerd
cri_config_containerd() {
  local file='/etc/containerd/config.toml'
  local path='/etc/containerd/certs.d'
  # 创建默认配置
  if [[ ! -d "${path}" ]]; then
    mkdir -p ${path}
  fi
  containerd config default >${file}
  result_msg "创建 containerd config"

  # 修改默认配置 sandbox_image(2.x modify sandbox, "" modify '')
  if [[ -n "${imageRepository}" ]]; then
    sed -i "s#\(sandbox.* = [\'\"]\).*\(/pause:.*[\'\"]\)#\1${imageRepository}\2#" ${file}
    result_msg "修改 sandbox image"
  fi

  # 修改默认配置 SystemdCgroup
  if grep -q 'SystemdCgroup = false' ${file}; then
    sed -i '/runtimes\.runc\.options/,/SystemdCgroup =/ s/SystemdCgroup = false/SystemdCgroup = true/' ${file}
    result_msg "修改 containerd Cgroup"
  fi

  # 修改配置 registry config_path
  if [[ -n "${privateRepository}" ]]; then
    # 修改 config_path 值
    sed -i "/registry/,/config_path/ s#\(config_path = [\'\"]\).*\([\'\"]\)#\1${path}\2#" ${file}
    result_msg "修改 registry config_path"

    local uri=${privateRepository#*://}
    mkdir -p ${path}/${uri}
    # 增加私库配置
    cat >${path}/${uri}/hosts.toml <<EOF
server = "${uri}"

[host."${privateRepository}"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
    result_msg "增加 containerd private registry"
  fi
}

cri_delete_config() {
  rm -rf /etc/containerd/config.toml \
    && rm -rf /etc/containerd/certs.d
  result_msg "删除 containerd config"
}

# 重启 containerd
cri_restart_containerd() {
  systemctl daemon-reload \
    && systemctl restart containerd &>/dev/null
  result_msg "重启 containerd"
}

cri_backup_config() {
  local dir='containerd'
  local name="${dir}-$(date +"%Y%m%d").tar.gz"

  tar -zcf ${KUBE_BACKUP}/${name} -C /etc ${dir} \
    && chmod 644 ${KUBE_BACKUP}/${name} \
    && chown ${script_own}:${script_own} ${KUBE_BACKUP}/${name} \
    && set_record ".backup.${dir}" "${name}"
  result_msg "备份 ${dir}"
}

install_cri() {
  cri_config_repos
  update_pkgs
  cri_install_containerd
  cri_config_containerd
  cri_restart_containerd
}

upgrade_cri() {
  cri_backup_config
  update_pkgs
  cri_install_containerd
  if [[ "${criUpgradeReconfig}" == "true" ]]; then
    cri_delete_config
    cri_config_containerd
  fi
  cri_restart_containerd
}

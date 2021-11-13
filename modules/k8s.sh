# 安装 k8s 组件 kubeadm 等，提供以下函数：
# install_k8s


# 添加 k8s repo（centos）
k8s_repo_centos() {
  if [ ! -f /etc/yum.repos.d/kubernetes.repo ];then
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
    result_msg "添加 k8s repo" || return 1
  fi
}


# 添加 k8s repo（debian）
k8s_repo_debian() {
  if [ ! -f /etc/apt/sources.list.d/kubernetes.list ];then
    curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg
    result_msg "添加 k8s pgp" || return 1
    echo \
    "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | \
    tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    result_msg "添加 k8s repo" || return 1
    ${sys_pkg} update > /dev/null
    result_msg "更新 apt" || return 1
  fi
}


k8s_centos() {
  k8s_repo_centos || return 1

  local apps="kubectl-${K8S_VERSION} kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION}"
  install_apps "${apps}" || return 1
  
  systemctl enable --now kubelet &> /dev/null
  result_msg '启动 kubelet' || return 1
}


k8s_debian() {
  k8s_repo_debian || return 1

  local apps="kubectl=${K8S_VERSION}-00 kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00"
  install_apps "${apps}" || return 1

  systemctl restart kubelet &> /dev/null
  result_msg '重启 kubelet' || return 1
}


k8s_config() {
  if ${IS_MASTER}; then
    export HOST_IP HOST_NAME CLUSTER_VIP CLUSTER_PORT K8S_VERSION POD_NETWORK SVC_NETWORK IMAGE_REPOSITORY
    envsubst < ${script_dir}/templates/kubeadm-config.yaml > ${script_dir}/kubeadm-config.yaml
    result_msg "生成 kubeadm-config.yaml"
  fi
}


crictl_config() {
  cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
  result_msg '配置 crictl' || return 1
}


# k8s 各个环境补丁
k8s_patch() {
  # 使用 containerd，需要配置 crictl
  if [ ${K8S_CRI} = 'containerd' ];then
    crictl_config || return 1
  fi

  # 使用 containterd，需要调整 kubeadm-config 配置
  if ${IS_MASTER} && [ ${K8S_CRI} = 'containerd' ]; then
    sed -i '/criSocket/s#/var/run/dockershim.sock#unix:///run/containerd/containerd.sock#' ${script_dir}/kubeadm-config.yaml && \
    result_msg "修改 kubeadm-config containerd" || return 1
  fi

  # k8s 1.22 以上版本需要调整 kubeadm-config 配置
  local ver="${K8S_VERSION}"
  if ${IS_MASTER} && [ $(echo "${ver%.*} >= 1.22" | bc) -eq 1 ]; then
    sed -e '/type: CoreDNS/d' \
      -e '/dns:/s/dns:/dns: {}/' \
      -e 's#kubeadm\.k8s\.io/v1beta2#kubeadm\.k8s\.io/v1beta3#' \
      -i ${script_dir}/kubeadm-config.yaml
    result_msg "修改 kubeadm-config v>=1.22" || return 1
  fi
}


install_k8s() {
  k8s_${sys_release} || exit 1
  k8s_config || exit 1
  k8s_patch || exit 1
}
# 安装 k8s 组件 kubeadm 等，提供以下函数：
# install_k8s


# 添加 k8s repo（centos）
k8s_repo_centos() {
  if [ ! -f /etc/yum.repos.d/kubernetes.repo ];then
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.tuna.tsinghua.edu.cn/kubernetes/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
    result_msg "添加 k8s repo"
    ${sys_pkg} makecache > /dev/null
    result_msg "运行 ${sys_pkg} makecache"
  fi
}


# 添加 k8s repo（debian）
k8s_repo_debian() {
  if [ ! -f /etc/apt/sources.list.d/kubernetes.list ];then
    rm -f /usr/share/keyrings/kubernetes-archive-keyring.gpg
    curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg
    result_msg "添加 k8s pgp"
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/kubernetes/apt/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
    result_msg "添加 k8s repo"
    ${sys_pkg} update > /dev/null
    result_msg "更新 apt"
  fi
}


k8s_centos() {
  local apps="kubectl kubelet kubeadm"

  k8s_repo_centos

  if [ ${K8S_VERSION} ]; then
    apps="kubectl-${K8S_VERSION} kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION}"
  fi
  
  install_apps "${apps}"
  
  systemctl enable --now kubelet &> /dev/null
  result_msg '启动 kubelet'
}


k8s_debian() {
  local apps="kubectl kubelet kubeadm"

  k8s_repo_debian

  if [ ${K8S_VERSION} ]; then
    apps="kubectl=${K8S_VERSION}-00 kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00"
  fi

  install_apps "${apps}"

  systemctl restart kubelet &> /dev/null
  result_msg '重启 kubelet'
}


k8s_config() {
  if ${IS_MASTER}; then
    K8S_VERSION_V=$(kubeadm version -o short)
    export HOST_IP HOST_NAME CLUSTER_VIP CLUSTER_PORT K8S_VERSION_V POD_NETWORK SVC_NETWORK IMAGE_REPOSITORY
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
  result_msg '配置 crictl'
}


k8s_patch() {
  # 使用 containerd，需要配置 crictl
  if [ ${K8S_CRI} = 'containerd' ];then
    crictl_config
  fi

  # k8s 1.22 以上版本需要调整 kubeadm-config 配置
  if ${IS_MASTER}; then
    local tmp=$(kubeadm version -o short)
    local ver="${tmp##*v}"
    if [ $(echo "${ver%.*} >= 1.22" | bc) -eq 1 ]; then
      sed -e '/type: CoreDNS/d' \
        -e '/dns:/s/dns:/dns: {}/' \
        -e 's#kubeadm\.k8s\.io/v1beta2#kubeadm\.k8s\.io/v1beta3#' \
        -e '/criSocket/a \  imagePullPolicy: IfNotPresent' \
        -i ${script_dir}/kubeadm-config.yaml
      result_msg "修改 kubeadm-config v>=1.22"
    fi
  fi
}


install_k8s() {
  k8s_${sys_release}
  k8s_config
  k8s_patch
}
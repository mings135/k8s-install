# 安装 k8s 组件 kubeadm 等


# 安装 k8s
kubernetes_install_apps() {
  # 如果设置 crictl version, 安装指定版本, 否则将在 kubeadm 安装时同步安装
  if [ ${crictlVersion} != 'latest' ]; then
    if [ ${SYSTEM_RELEASE} = 'centos' ]; then
      # CentOS 查看更多版本：yum list cri-tools --showduplicates | sort -r
      install_apps "cri-tools-${crictlVersion}" '--disableexcludes=kubernetes'
    elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
      # Debian 查看更多版本：apt-cache madison cri-tools
      install_apps "cri-tools=${crictlVersion}"
    fi
  fi
  # 安装 kubeadm 等应用
  if [ ${SYSTEM_RELEASE} = 'centos' ]; then
    # CentOS 查看更多版本：yum list kubeadm --showduplicates --disableexcludes=kubernetes | sort -r
    install_apps "kubectl-${kubernetesVersion} kubelet-${kubernetesVersion} kubeadm-${kubernetesVersion}" '--disableexcludes=kubernetes'
  elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
    # 如果被锁, 解锁
    local mark_apps=''
    for i in kubeadm kubelet kubectl
    do
      if apt-mark showhold | grep -Eqi "$i"; then
        mark_apps="${mark_apps} $i"
      fi
    done
    if [ "${mark_apps}" ]; then
      apt-mark unhold ${mark_apps} > /dev/null
      result_msg "解锁 ${mark_apps}"
    fi
    # Debian 查看更多版本：apt-cache madison kubeadm
    install_apps "kubectl=${kubernetesVersion} kubelet=${kubernetesVersion} kubeadm=${kubernetesVersion}"
    # 锁住版本
    apt-mark hold kubectl kubelet kubeadm > /dev/null
    result_msg "锁住 kubectl kubelet kubeadm"
  fi
}


# 设置 k8s
kubernetes_kubeadm_config() {
  cd ${script_dir}/config
  kubeadm config print init-defaults | yq -M 'select(document_index == 0)' > initConfiguration.yaml
  kubeadm config print init-defaults | yq -M 'select(document_index == 1)' > clusterConfiguration.yaml
  cat > otherConfiguration.yaml << EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
ipvs:
  scheduler: "wrr"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
containerLogMaxSize: "30Mi"
containerLogMaxFiles: 5
EOF
  tmp_var=${HOST_IP} yq -i '.localAPIEndpoint.advertiseAddress = strenv(tmp_var)' initConfiguration.yaml
  tmp_var=${criSocket} yq -i '.nodeRegistration.criSocket = strenv(tmp_var)' initConfiguration.yaml
  tmp_var=${HOST_NAME} yq -i '.nodeRegistration.name = strenv(tmp_var)' initConfiguration.yaml
  if [ "${controlPlaneEndpoint}" ]; then
    tmp_var=${controlPlaneEndpoint} yq -i '.controlPlaneEndpoint = strenv(tmp_var)' clusterConfiguration.yaml
  fi
  if [ "${imageRepository}" ]; then
    tmp_var=${imageRepository} yq -i '.imageRepository = strenv(tmp_var)' clusterConfiguration.yaml
  fi
  if [ "${caCertificateValidityPeriod}" ] && compare_version_ge "${kubernetesMajorMinor}" "1.31"; then
    tmp_var=${caCertificateValidityPeriod} yq -i '.caCertificateValidityPeriod = strenv(tmp_var)' clusterConfiguration.yaml
  fi
  if [ "${certificateValidityPeriod}" ] && compare_version_ge "${kubernetesMajorMinor}" "1.31"; then
    tmp_var=${certificateValidityPeriod} yq -i '.certificateValidityPeriod = strenv(tmp_var)' clusterConfiguration.yaml
  fi

  tmp_var=${kubernetesVersion} yq -i '.kubernetesVersion = strenv(tmp_var)' clusterConfiguration.yaml
  tmp_var=${serviceSubnet} yq -i '.networking.serviceSubnet = strenv(tmp_var)' clusterConfiguration.yaml
  tmp_var=${podSubnet} yq -i '.networking.podSubnet = strenv(tmp_var)' clusterConfiguration.yaml
  yq -M initConfiguration.yaml clusterConfiguration.yaml otherConfiguration.yaml > kubeadm-config.yaml
  rm -f initConfiguration.yaml clusterConfiguration.yaml otherConfiguration.yaml
}


# 设置 crictl
kubernetes_crictl_config() {
  cat > /etc/crictl.yaml << EOF
runtime-endpoint: ${criSocket}
image-endpoint: ${criSocket}
timeout: 10
debug: false
EOF
  result_msg '配置 crictl'
}


# 启动 kubelet
kubernetes_start_kubelet() {
  if [ ${SYSTEM_RELEASE} = 'centos' ]; then
    systemctl enable kubelet &> /dev/null \
      && systemctl restart kubelet
    result_msg '启动 kubelet'
  elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
    systemctl restart kubelet &> /dev/null
    result_msg '重启 kubelet'
  fi
}


kubernetes_install() {
  kubernetes_install_apps
  kubernetes_crictl_config
  kubernetes_start_kubelet
  if echo "${HOST_ROLE}" | grep -Eqi 'master'; then
    kubernetes_kubeadm_config
  fi
}

# 安装 k8s 组件 kubeadm 等


# 安装 k8s
kubernetes_install_apps() {
  if [ ${SYSTEM_RELEASE} = 'debian' ]; then
    # 解锁版本
    apt-mark unhold kubectl kubelet kubeadm &> /dev/null
    result_msg "解锁 kubectl kubelet kubeadm"
  fi

  if [ ${crictlVersion} = 'latest' ]; then
    install_apps "cri-tools"
  elif [ ${SYSTEM_RELEASE} = 'centos' ]; then
    # CentOS 查看更多版本：yum list cri-tools --showduplicates | sort -r
    install_apps "cri-tools-${crictlVersion}"
  elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
    # Debian 查看更多版本：apt-cache madison cri-tools
    install_apps "cri-tools=${crictlVersion}-00"
  fi
  
  if [ ${kubernetesVersion} = 'latest' ]; then
    local apps="kubectl kubelet kubeadm"
  elif [ ${SYSTEM_RELEASE} = 'centos' ]; then
    # CentOS 查看更多版本：yum list kubeadm --showduplicates | sort -r
    local apps="kubectl-${kubernetesVersion} kubelet-${kubernetesVersion} kubeadm-${kubernetesVersion}"
  elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
    # Debian 查看更多版本：apt-cache madison kubeadm
    local apps="kubectl=${kubernetesVersion}-00 kubelet=${kubernetesVersion}-00 kubeadm=${kubernetesVersion}-00"
  fi
  install_apps "${apps}"

  if [ ${SYSTEM_RELEASE} = 'debian' ]; then
    # 锁住版本
    apt-mark hold kubectl kubelet kubeadm &> /dev/null
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
  if [ ${controlPlaneEndpoint} ]; then
    tmp_var=${controlPlaneEndpoint} yq -i '.controlPlaneEndpoint = strenv(tmp_var)' clusterConfiguration.yaml
  fi
  if [ ${imageRepository} ]; then
    tmp_var=${imageRepository} yq -i '.imageRepository = strenv(tmp_var)' clusterConfiguration.yaml
  fi
  if [ ${kubernetesVersion} != 'latest' ]; then
    tmp_var=${kubernetesVersion} yq -i '.kubernetesVersion = strenv(tmp_var)' clusterConfiguration.yaml
  fi
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

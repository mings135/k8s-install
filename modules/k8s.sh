# 安装 k8s 组件 kubeadm 等

kubernetes_config_repos() {
  # debian 所需变量(/etc/apt/keyrings 在 sys_install_dependencies 中创建)
  local repo='/etc/apt/sources.list.d/kubernetes.list'
  local key="${GPG_DIR}/kubernetes-archive-keyring.gpg"
  local ver=$(echo "${kubernetesVersion}" | cut -d'.' -f1,2)

  # debian 设置 kubernetes 源
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${ver}/deb/Release.key | gpg --yes --dearmor -o ${key}
  result_msg "[Install] k8s pgp"
  echo "deb [signed-by=${key}] https://pkgs.k8s.io/core:/stable:/v${ver}/deb/ /" >${repo}
  result_msg "[Install] k8s repo"

  if [[ "${localMirror}" == "true" ]]; then
    sed -i 's+pkgs.k8s.io+mirrors.tuna.tsinghua.edu.cn/kubernetes+' ${repo}
    result_msg "[Modify] k8s repo"
  fi
}

kubernetes_install_kubeadm() {
  local app="kubeadm"
  unhold_pkgs "${app}"
  install_pkgs "${app}=${kubernetesVersion} cri-tools"
  hold_pkgs "${app}"
}

kubernetes_install_kubelet() {
  local app="kubectl"
  unhold_pkgs "${app}"
  install_pkgs "${app}=${kubernetesVersion}"
  hold_pkgs "${app}"

  app="kubelet"
  unhold_pkgs "${app}"
  install_pkgs "${app}=${kubernetesVersion} kubernetes-cni"
  hold_pkgs "${app}"
}

# 设置 k8s
kubernetes_kubeadm_config() {
  local total_mem=$(free -m | awk '/^Mem:/{print $2}')
  local sys_mem kube_mem

  if [[ "${total_mem}" -le 2048 ]]; then
    sys_mem="256Mi"
    kube_mem="128Mi"
  else
    sys_mem="512Mi"
    kube_mem="256Mi"
  fi

  # otherConfiguration.yaml
  cat >${KUBE_CONF}/otherConfiguration.yaml <<EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
ipvs:
  scheduler: "wrr"
  # [必须] 优化超时时间, 防止内核连接跟踪表(conntrack)堆积
  tcpTimeout: 300s
  tcpFinTimeout: 60s
  udpTimeout: 30s
  # [必须] 开启严格 ARP, 防止 LoadBalancer 流量在多网卡环境下冲突
  strictARP: true
# [推荐] 根据节点配置调整内核连接数限额
conntrack:
  maxPerCore: 32768
  min: 131072
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd

# [必须]日志滚动策略
containerLogMaxSize: "30Mi"
containerLogMaxFiles: 5

# [必须]资源预留: 系统进程和 K8s 组件, 防止系统 OOM 杀掉核心进程
systemReserved:
  cpu: "100m"
  memory: "${sys_mem}"
kubeReserved:
  cpu: "100m"
  memory: "${kube_mem}"

# [推荐]性能优化, 允许并行拉取镜像, 提高冷启动速度
serializeImagePulls: false

# [推荐]安全性加固
authentication:
  anonymous:
    enabled: false    # 禁止匿名访问 kubelet API
  webhook:
    enabled: true
authorization:
  mode: Webhook       # 使用 Webhook 校验权限
readOnlyPort: 0       # 关闭只读端口 (10255)
EOF

  kubeadm config print init-defaults | yq -M 'select(document_index == 0)' >${KUBE_CONF}/initConfiguration.yaml
  kubeadm config print init-defaults | yq -M 'select(document_index == 1)' >${KUBE_CONF}/clusterConfiguration.yaml

  # initConfiguration.yaml
  val1=${HOST_IP} val2=${criSocket} val3=${HOST_NAME} yq -i '
    .localAPIEndpoint.advertiseAddress = strenv(val1) |
    .nodeRegistration.criSocket = strenv(val2) |
    .nodeRegistration.name = strenv(val3)
  ' ${KUBE_CONF}/initConfiguration.yaml

  # clusterConfiguration.yaml
  if [[ -n "${imageRepository}" ]]; then
    val1=${imageRepository} yq -i '.imageRepository = strenv(val1)' ${KUBE_CONF}/clusterConfiguration.yaml
  fi

  # clusterConfiguration.yaml
  val1=${kubernetesVersion} \
    val2=${controlPlaneEndpoint} \
    val3=${caCertificateValidityPeriod} \
    val4=${certificateValidityPeriod} \
    val5=${serviceSubnet} \
    val6=${podSubnet} \
    yq -i '
      .kubernetesVersion = strenv(val1) |
      .controlPlaneEndpoint = strenv(val2) |
      .caCertificateValidityPeriod = strenv(val3) |
      .certificateValidityPeriod = strenv(val4) |
      .networking.serviceSubnet = strenv(val5) |
      .networking.podSubnet = strenv(val6)
    ' ${KUBE_CONF}/clusterConfiguration.yaml

  # clusterConfiguration.yaml
  val="${KUBE_FILE}" yq -i '
    (load(strenv(val)).cluster.certSANs) as $src | 
    with(select($src | length > 0); .apiServer.certSANs = $src)
  ' ${KUBE_CONF}/clusterConfiguration.yaml

  # 写入同步
  sync

  # kubeadm-config.yaml
  yq -M eval-all 'select(fileIndex == 0), select(fileIndex == 1), select(fileIndex == 2)' \
    ${KUBE_CONF}/initConfiguration.yaml \
    ${KUBE_CONF}/clusterConfiguration.yaml \
    ${KUBE_CONF}/otherConfiguration.yaml >${KUBE_KUBEADM} \
    && rm -f ${KUBE_CONF}/initConfiguration.yaml ${KUBE_CONF}/clusterConfiguration.yaml ${KUBE_CONF}/otherConfiguration.yaml
  result_msg '[Create] kubeadm-config.yaml'
}

# 设置 crictl
kubernetes_crictl_config() {
  cat >/etc/crictl.yaml <<EOF
runtime-endpoint: ${criSocket}
image-endpoint: ${criSocket}
timeout: 10
debug: false
EOF
  result_msg '[Config] crictl'
}

stop_kubelet() {
  systemctl stop kubelet &>/dev/null
  result_msg "[Stop] kubelet"
}

start_kubelet() {
  systemctl daemon-reload \
    && systemctl start kubelet &>/dev/null
  result_msg "[Start] kubelet"
}

backup_kubernetes() {
  local dir='kubernetes'
  local name="${dir}-$(date +"%Y%m%d-%H%M").tar.gz"

  local value=$(get_record ".backup.${dir}")
  RES_LEVEL=1 && [[ "${value}" != "${name}" ]]
  result_msg "[Backup] ${dir}, Only one backup per minute is allowed"
  RES_LEVEL=0

  tar -zcf ${KUBE_BACKUP}/${name} -C /etc ${dir} \
    && chmod 644 ${KUBE_BACKUP}/${name} \
    && chown ${script_own}:${script_own} ${KUBE_BACKUP}/${name} \
    && set_record ".backup.${dir}" "${name}"
  result_msg "[Backup] ${dir}"
}

install_kubernetes() {
  kubernetes_config_repos
  update_pkgs
  kubernetes_install_kubeadm
  kubernetes_install_kubelet
  kubernetes_crictl_config
  if [[ "${HOST_ROLE}" == "master"* ]]; then
    kubernetes_kubeadm_config
  fi
}

upgrade_kubeadm() {
  kubernetes_config_repos
  update_pkgs
  kubernetes_install_kubeadm
}

upgrade_kubelet() {
  kubernetes_install_kubelet
  stop_kubelet
  start_kubelet
}

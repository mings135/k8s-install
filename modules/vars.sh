# 变量

vars_by_master1() {
  # 配置文件中获取 master1 变量
  MASTER1_IP="$(get_config ".nodes.master1.address")"
  MASTER1_NAME="$(get_config ".nodes.master1.domain")"
}

vars_by_nodes() {
  # 从配置文件中获取 nodes 信息，并分类
  NODES_MASTER="$(yq -M '[.nodes.master[].address] | join(" ")' ${KUBE_FILE})"
  NODES_WORK="$(yq -M '[.nodes.work[].address] | join(" ")' ${KUBE_FILE})"
  NODES_ALL="${MASTER1_IP} ${NODES_MASTER} ${NODES_WORK}"
  NODES_NOT_MASTER1="${NODES_MASTER} ${NODES_WORK}"
  NODES_MASTER1_MASTER="${MASTER1_IP} ${NODES_MASTER}"
}

vars_by_localhost() {
  # 从本机 ip 和配置文件中，获取 name 和 role 信息
  if [[ ${HOST_IP} == ${MASTER1_IP} ]]; then
    HOST_ROLE='master1'
    HOST_NAME=${MASTER1_NAME}
    return 0
  fi

  local info=$(val1="${HOST_IP}" yq -M '
    .nodes | with_entries(select(.key == "master" or .key == "work")) | 
    to_entries | .[] | .key as $role | .value[] | 
    select(.address == strenv(val1)) | 
    ($role + " " + .domain)
  ' "${KUBE_FILE}")

  if [[ -n "$info" ]]; then
    read -r HOST_ROLE HOST_NAME <<<"$info"
  fi
}

vars_by_config() {
  # 从配置文件中获取 config 信息
  etcdctlVersion="$(get_config ".etcdctlVersion")"
  localMirror="$(get_config ".localMirror")"
  nodeUser="$(get_config ".nodeUser")"
  nodePassword="$(get_config ".nodePassword")"
  remoteScriptDir="$(get_config ".remoteScriptDir")"

  # cluster
  kubernetesVersion="$(get_config ".cluster.kubernetesVersion")"
  controlPlaneEndpoint="$(get_config ".cluster.controlPlaneEndpoint")"
  controlPlaneTarget="$(get_config ".cluster.controlPlaneTarget")"
  imageRepository="$(get_config ".cluster.imageRepository")"
  caCertificateValidityPeriod="$(get_config ".cluster.caCertificateValidityPeriod")"
  certificateValidityPeriod="$(get_config ".cluster.certificateValidityPeriod")"
  serviceSubnet="$(get_config ".cluster.serviceSubnet")"
  podSubnet="$(get_config ".cluster.podSubnet")"
  # container
  criVersion="$(get_config ".container.criVersion")"
  criUpgradeReconfig="$(get_config ".container.criUpgradeReconfig")"
  privateRepository="$(get_config ".container.privateRepository")"
}

vars_by_default() {
  # 节点安装 etcdctl 的 version
  etcdctlVersion=${etcdctlVersion:-"3.6.6"}
  # 是否使用国内 apt 镜像源
  localMirror=${localMirror:-"false"}
  # 节点密码, 默认为空(也就是手动输入)
  nodeUser=${nodeUser:-"root"}
  nodePassword=${nodePassword:-""}

  # 远程集群主机存放 k8s 安装脚本的目录, 必须有上层目录 (目录会在复制之前清空，请注意!!!)
  if [[ "${nodeUser}" != "root" ]]; then
    remoteScriptDir=${remoteScriptDir:-"/home/${nodeUser}/k8sRemoteScript"}
  else
    remoteScriptDir=${remoteScriptDir:-"/opt/k8sRemoteScript"}
  fi

  # k8s version(支持 1.31+, 不支持 latest)
  kubernetesVersion=${kubernetesVersion:-"1.33.10"}
  kubernetesVersion="${kubernetesVersion#v}"

  # k8s controlPlaneEndpoint, 重要参数, 就是 LB IP or Domain
  if [[ -n "${controlPlaneEndpoint}" ]]; then
    controlPlaneTarget=${controlPlaneTarget:-""}
  else
    controlPlaneEndpoint="master.k8s:6443"
    controlPlaneTarget=${controlPlaneTarget:-"${MASTER1_IP}"}
  fi

  # k8s 镜像仓库, include containerd, Recommend: registry.cn-hangzhou.aliyuncs.com/google_containers
  imageRepository=${imageRepository:-""}

  # kubeadm 证书期限, 仅 kubernetes >= 1.31 可用(格式：8760h0m0s)
  caCertificateValidityPeriod=${caCertificateValidityPeriod:-"262800h0m0s"}
  certificateValidityPeriod=${certificateValidityPeriod:-"26280h0m0s"}

  # Services 子网和 API Server 集群内部地址 (即 Service 网络的第一个 IP)
  serviceSubnet=${serviceSubnet:-"10.96.0.0/16"}
  # Pod 网络, flannel 默认使用 10.244.0.0/16, 除非想修改 flannel 配置, 否则不要修改
  podSubnet=${podSubnet:-"10.244.0.0/16"}

  # 容器运行时: containerd(最新版本: latest, 具体版本: 1.6.9)
  criVersion=${criVersion:-"latest"}
  criVersion="${criVersion#v}"

  criUpgradeReconfig=${criUpgradeReconfig:-"false"}
  # 容器运行时: 配置 harbor 私库地址(http://192.168.13.13)
  privateRepository=${privateRepository:-""}

  criSocket='unix:///run/containerd/containerd.sock'
}

# 安装必要的前置工具(2)
vars_install_dependencies() {
  if [[ ! -f ${KUBE_BIN}/etcdctl ]] || [[ "$(etcdctl version | awk '/etcdctl version/{print $3}')" != "${etcdctlVersion}" ]]; then
    blue_font "[Download] etcdctl to ${KUBE_BIN}"
    curl -fsSL -o /tmp/etcd-linux-amd64.tar.gz https://github.com/etcd-io/etcd/releases/download/v${etcdctlVersion}/etcd-v${etcdctlVersion}-linux-amd64.tar.gz \
      && rm -rf /tmp/etcd-download-test && mkdir -p /tmp/etcd-download-test \
      && tar xzf /tmp/etcd-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1 \
      && rm -f /tmp/etcd-linux-amd64.tar.gz \
      && mv /tmp/etcd-download-test/etcdctl ${KUBE_BIN}/etcdctl
    if [[ -f /tmp/etcd-download-test/etcdutl ]]; then
      mv /tmp/etcd-download-test/etcdutl ${KUBE_BIN}/etcdutl
    fi
  fi
}

# 查看所有变量
display_vars() {
  # const
  echo "OS_NAME=${OS_NAME}"
  echo "OS_VERSION=${OS_VERSION}"
  echo "script_dir=${script_dir}"
  echo "script_own=${script_own}"
  echo "clusterName=${clusterName}"
  # master1
  echo "MASTER1_IP=${MASTER1_IP}"
  echo "MASTER1_NAME=${MASTER1_NAME}"
  # localhost
  echo "HOST_IP=${HOST_IP}"
  echo "HOST_NAME=${HOST_NAME}"
  echo "HOST_ROLE=${HOST_ROLE}"
  # config .
  echo "etcdctlVersion=${etcdctlVersion}"
  echo "localMirror=${localMirror}"
  echo "nodeUser=${nodeUser}"
  echo "nodePassword=${nodePassword}"
  echo "remoteScriptDir=${remoteScriptDir}"
  # config .cluster
  echo "kubernetesVersion=${kubernetesVersion}"
  echo "controlPlaneEndpoint=${controlPlaneEndpoint}"
  echo "controlPlaneTarget=${controlPlaneTarget}"
  echo "imageRepository=${imageRepository}"
  echo "caCertificateValidityPeriod=${caCertificateValidityPeriod}"
  echo "certificateValidityPeriod=${certificateValidityPeriod}"
  echo "serviceSubnet=${serviceSubnet}"
  echo "podSubnet=${podSubnet}"
  # config .container
  echo "criVersion=${criVersion}"
  echo "criUpgradeReconfig=${criUpgradeReconfig}"
  echo "privateRepository=${privateRepository}"
  echo "criSocket=${criSocket}"
  # nodes
  echo "NODES_ALL=${NODES_ALL}"
  echo "NODES_NOT_MASTER1=${NODES_NOT_MASTER1}"
  echo "NODES_MASTER1_MASTER=${NODES_MASTER1_MASTER}"
  echo "NODES_MASTER=${NODES_MASTER}"
  echo "NODES_WORK=${NODES_WORK}"

  # record.yaml
  echo ''
  if [[ -f "${KUBE_RECORD}" ]]; then
    echo "${KUBE_RECORD}"
    yq ${KUBE_RECORD}
  fi

  # kubeadm-config.yaml
  echo ''
  if [[ "${HOST_ROLE}" == "master1" ]] && [[ -f "${KUBE_KUBEADM}" ]]; then
    echo "${KUBE_KUBEADM}"
    yq ${KUBE_KUBEADM}
  fi

  # etc hosts
  echo ''
  local file='/etc/hosts'
  if [[ "${HOST_ROLE}" == "master1" ]] && [[ -f "${file}" ]]; then
    echo "${file}"
    cat ${file}
  fi

  # containerd
  echo ''
  file='/etc/containerd/config.toml'
  if [[ "${HOST_ROLE}" == "master1" ]] && [[ -f "${file}" ]]; then
    echo "${file}"
    sed -n '/sandbox.*pause/p' ${file}
    sed -n '/runtimes\.runc\.options/,/SystemdCgroup =/p' ${file}
  fi

  # crictl.yaml
  echo ''
  file='/etc/crictl.yaml'
  if [[ "${HOST_ROLE}" == "master1" ]] && [[ -f "${file}" ]]; then
    echo "${file}"
    yq ${file}
  fi
}

# 设置所有变量(local.sh)
vars_local() {
  vars_by_master1
  vars_by_localhost
  vars_by_config
  vars_by_default
}

# 设置所有变量(remote.sh)
vars_remote() {
  vars_by_master1
  vars_by_nodes
  vars_by_config
  vars_by_default
  vars_install_dependencies
}

case "${script_type}" in
  "local") vars_local ;;
  "remote") vars_remote ;;
esac

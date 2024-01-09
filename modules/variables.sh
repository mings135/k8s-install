# 设置所有变量


# 提供安装 app 函数
install_apps() {
  local ver_val name_val ver_long
  # 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
  if [ ${SYSTEM_RELEASE} = 'debian' ]; then
    export DEBIAN_FRONTEND=noninteractive
  fi
  # 安装 app, $1 需要安装的软件, space 分隔, $2 额外的参数
  for i in $1
  do
    # debian 获取完整的版本信息
    if [ ${SYSTEM_RELEASE} = 'debian' ] && echo $i | grep -Eqi '='; then
      name_val=$(echo $i | awk -F '=' '{print$1}')
      ver_val=$(echo $i | awk -F '=' '{print$2}')
      ver_long=$(apt-cache madison ${name_val} | grep "${ver_val}" | awk '{print $3}' | head -n 1)
      if [ "${ver_long}" ]; then
        i="${name_val}=${ver_long}"
      fi
    fi
    # 执行安装
    if [ "$2" ]; then
      ${SYSTEM_PACKAGE} install -y ${i} $2 &> /dev/null
      result_msg "安装 $i"
    else
      ${SYSTEM_PACKAGE} install -y ${i} &> /dev/null
      result_msg "安装 $i"
    fi
  done
}


# 更新镜像源缓存
update_mirror_source_cache() {
  # centos
  if [ ${SYSTEM_RELEASE} = 'centos' ]; then
    ${SYSTEM_PACKAGE} makecache > /dev/null
    result_msg "重新 yum makecache"
  # debian
  elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
    ${SYSTEM_PACKAGE} update > /dev/null
    result_msg "重新 apt update"
  fi
}


# 提供删除 app 函数
remove_apps() {
  # 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
  if [ ${SYSTEM_RELEASE} = 'debian' ]; then
    export DEBIAN_FRONTEND=noninteractive
  fi
  # 移除 app
  for i in $1
  do
    ${SYSTEM_PACKAGE} remove -y ${i} &> /dev/null
    result_msg "移除 $i"
  done
}


# 检查是否存在配置文件
variables_check_config() {
  RES_LEVEL=1 && test -e ${script_dir}/config/kube.yaml
  result_msg "检查存在 kube.yaml" && RES_LEVEL=0
}


# 设置系统信息变量
variables_set_system() {
  if [ -f /etc/redhat-release ]; then
    SYSTEM_RELEASE="centos"
    SYSTEM_PACKAGE="dnf"
    # 判断版本
    if cat /etc/redhat-release | grep -Eqi 'release 7'; then
      SYSTEM_PACKAGE="yum"
      SYSTEM_VERSION=7
    elif cat /etc/redhat-release | grep -Eqi 'release 8'; then
      SYSTEM_VERSION=8
    elif cat /etc/redhat-release | grep -Eqi 'release 9'; then
      SYSTEM_VERSION=9
    fi
  elif cat /etc/issue | grep -Eqi "debian"; then
    SYSTEM_RELEASE="debian"
    SYSTEM_PACKAGE="apt-get"
    # 判断版本
    if cat /etc/issue | grep -Eqi 'linux 10'; then
      SYSTEM_VERSION=10
    elif cat /etc/issue | grep -Eqi 'linux 11'; then
      SYSTEM_VERSION=11
    elif cat /etc/issue | grep -Eqi 'linux 12'; then
      SYSTEM_VERSION=12
    fi
  fi
  # 检查变量，异常显示
  RES_LEVEL=1 && test ${SYSTEM_RELEASE} && test ${SYSTEM_PACKAGE} && test ${SYSTEM_VERSION}
  result_msg "设置 system variables" && RES_LEVEL=0
}


# 安装必要的工具(1), 脚本所需的前置工具
variables_install_dependencies() {
  local apps=''
  for i in bc curl tar
  do
    if ! which $i &> /dev/null; then
      apps="${apps} $i"
    fi
  done
  if [ "$apps" ]; then
    update_mirror_source_cache
    install_apps "${apps}"
  fi

  if ! which yq &> /dev/null; then
    curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
      && chmod +x /usr/local/bin/yq
    result_msg "安装 yq"
  fi
}


# 设置 master1 节点变量
variables_set_master1() {
  local kube_conf=${script_dir}/config/kube.yaml
  # 获取 master1 变量
  MASTER1_IP="$(yq -M '.nodes.master1.address' ${kube_conf} | grep -v '^null$')"
  MASTER1_NAME="$(yq -M '.nodes.master1.domain' ${kube_conf} | grep -v '^null$')"
  # 检查变量，异常显示
  RES_LEVEL=1 && test ${MASTER1_IP} && test ${MASTER1_NAME}
  result_msg "设置 master1 variables" && RES_LEVEL=0
}


# 节点分类变量
variables_nodes_class() {
  local kube_conf=${script_dir}/config/kube.yaml
  NODES_MASTER="$(yq -M '.nodes.master[].address' ${kube_conf} | tr '\n' ' ' | sed 's/ *$//')"
  NODES_WORK="$(yq -M '.nodes.work[].address' ${kube_conf} | tr '\n' ' ' | sed 's/ *$//')"
  NODES_ALL="${MASTER1_IP} ${NODES_MASTER} ${NODES_WORK}"
  NODES_NOT_MASTER1="${NODES_MASTER} ${NODES_WORK}"
  NODES_MASTER1_MASTER="${MASTER1_IP} ${NODES_MASTER}"
}


# 设置当前节点变量
variables_set_host() {
  local kube_conf=${script_dir}/config/kube.yaml
  local host_ip=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')
  local index
  # 检查变量，异常显示
  RES_LEVEL=1 && echo "${host_ip}" | grep -Eqi '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  result_msg "获取 host ip" && RES_LEVEL=0
  # 根据 role 信息, 设置 host 变量
  if [ ${host_ip} = ${MASTER1_IP} ]; then
    HOST_IP=${MASTER1_IP}
    HOST_NAME=${MASTER1_NAME}
    HOST_ROLE='master1'
  elif tmp_var=${host_ip} yq -M '.nodes.master[].address == strenv(tmp_var)' ${kube_conf} | grep -Eqi 'true'; then
    index=$(tmp_var=${host_ip} yq -M '.nodes.master[].address | select(. == strenv(tmp_var)) | path | .[-2]' ${kube_conf})
    HOST_IP=${host_ip}
    HOST_NAME=$(tmp_var=${index} yq -M '.nodes.master[env(tmp_var)].domain' ${kube_conf})
    HOST_ROLE='master'
  elif tmp_var=${host_ip} yq -M '.nodes.work[].address == strenv(tmp_var)' ${kube_conf} | grep -Eqi 'true'; then
    index=$(tmp_var=${host_ip} yq -M '.nodes.work[].address | select(. == strenv(tmp_var)) | path | .[-2]' ${kube_conf})
    HOST_IP=${host_ip}
    HOST_NAME=$(tmp_var=${index} yq -M '.nodes.work[env(tmp_var)].domain' ${kube_conf})
    HOST_ROLE='work'
  fi
  # 检查变量，异常显示
  RES_LEVEL=1 && test ${HOST_IP} && test ${HOST_NAME} && test ${HOST_ROLE}
  result_msg "设置 host variables" && RES_LEVEL=0
}


# 读取配置文件变量
variables_read_config() {
  local kube_conf=${script_dir}/config/kube.yaml
  remoteScriptDir="$(yq -M '.remoteScriptDir' ${kube_conf} | grep -v '^null$')"
  localMirror="$(yq -M '.localMirror' ${kube_conf} | grep -v '^null$')"
  kubernetesVersion="$(yq -M '.cluster.kubernetesVersion' ${kube_conf} | grep -v '^null$')"
  crictlVersion="$(yq -M '.cluster.crictlVersion' ${kube_conf} | grep -v '^null$')"
  controlPlaneAddress="$(yq -M '.cluster.controlPlaneAddress' ${kube_conf} | grep -v '^null$')"
  controlPlanePort="$(yq -M '.cluster.controlPlanePort' ${kube_conf} | grep -v '^null$')"
  imageRepository="$(yq -M '.cluster.imageRepository' ${kube_conf} | grep -v '^null$')"
  criName="$(yq -M '.container.criName' ${kube_conf} | grep -v '^null$')"
  criVersion="$(yq -M '.container.criVersion' ${kube_conf} | grep -v '^null$')"
  criUpgradeReconfig="$(yq -M '.container.criUpgradeReconfig' ${kube_conf} | grep -v '^null$')"
  privateRepository="$(yq -M '.container.privateRepository' ${kube_conf} | grep -v '^null$')"
  certificatesVaild="$(yq -M '.cluster.certificatesVaild' ${kube_conf} | grep -v '^null$')"
  certificatesSize="$(yq -M '.cluster.certificatesSize' ${kube_conf} | grep -v '^null$')"
  serviceSubnet="$(yq -M '.cluster.serviceSubnet' ${kube_conf} | grep -v '^null$')"
  apiServerClusterIP="$(yq -M '.cluster.apiServerClusterIP' ${kube_conf} | grep -v '^null$')"
  podSubnet="$(yq -M '.cluster.podSubnet' ${kube_conf} | grep -v '^null$')"
  nodePassword="$(yq -M '.nodes.nodePassword' ${kube_conf} | grep -v '^null$')"
  etcdctlVersion="$(yq -M '.nodes.etcdctlVersion' ${kube_conf} | grep -v '^null$')"
  certificateRenewal="$(yq -M '.cluster.certificateRenewal' ${kube_conf} | grep -v '^null$')"
}


# 设置默认值(未配置的)
variables_default_config() {
  # 远程集群主机存放 k8s 安装脚本的目录 (目录会在复制之前清空，请注意!!!)
  remoteScriptDir=${remoteScriptDir:-'/opt/k8sRemoteScript'}
  # kubernetes >= 1.28 时, 该配置对 kubernetes source 无效
  localMirror=${localMirror:-'0'}
  # k8s version(支持 1.20+, 不支持 latest)
  kubernetesVersion=${kubernetesVersion:-'1.28.0'}
  crictlVersion=${crictlVersion:-'latest'} # 1.26.0 开始 containerd 必须大于 1.26
  # k8s controlPlaneEndpoint 地址和端口, 没有该参数无法添加 master 节点
  controlPlaneAddress=${controlPlaneAddress:-"${MASTER1_IP}"}
  controlPlanePort=${controlPlanePort:-'6443'}
  # k8s 各个组件的镜像仓库地址: pause(Include containerd)、etcd、api-server 等
  imageRepository=${imageRepository:-''}  # 国内 registry.cn-hangzhou.aliyuncs.com/google_containers
  # 容器运行时: containerd(最新版本: latest, 具体版本: 1.6.9)
  criName=${criName:-'containerd'}
  criVersion=${criVersion:-'latest'}
  criUpgradeReconfig=${criUpgradeReconfig:-'0'}
  # 容器运行时: 配置 harbor 私库地址(http://192.168.13.13)
  privateRepository=${privateRepository:-''}
  # 证书有效期和密钥大小(50年)
  certificatesVaild=${certificatesVaild:-'18250'}
  certificatesSize=${certificatesSize:-'2048'}
  # Services 子网和 API Server 集群内部地址 (即 Service 网络的第一个 IP)
  serviceSubnet=${serviceSubnet:-'10.96.0.0/16'}
  apiServerClusterIP=${apiServerClusterIP:-'10.96.0.1'}
  # Pod 网络, flannel 默认使用 10.244.0.0/16, 除非想修改 flannel 配置, 否则不要修改
  podSubnet=${podSubnet:-'10.244.0.0/16'}
  # 节点密码, 默认为空(也就是手动输入)
  nodePassword=${nodePassword:-''}
  # 节点安装 etcdctl 的 version
  etcdctlVersion=${etcdctlVersion:-'3.5.10'}
  # upgrade 时, 是否更新证书
  certificateRenewal=${certificateRenewal:-'false'}
  

  # 设置常量
  KUBEADM_PKI='/etc/kubernetes/pki'
  KUBEADM_CONFIG='/etc/kubernetes'
  KUBELET_PKI='/var/lib/kubelet/pki'
  JOIN_TOKEN_INTERVAL=7200
  etcdDataDir="/var/lib/etcd" # 目前仅用于 etcd 备份恢复
  upgradeVersion="${kubernetesVersion}"
  kubernetesMajorMinor=${kubernetesVersion%.*}

  # 生成变量
  if [ "${controlPlaneAddress}" ] && [ "${controlPlanePort}" ]; then
    controlPlaneEndpoint="${controlPlaneAddress}:${controlPlanePort}"
  fi
  if [ ${criName} = 'containerd' ]; then
    criSocket='unix:///run/containerd/containerd.sock'
  fi

  # 检查 k8s
  RES_LEVEL=1 && test $(echo "${kubernetesVersion}" | awk -F '.' '{print NF}') -eq 3 \
    && echo "${kubernetesVersion}" | awk -F '.' '{print $1$2$3}' | grep -Eqi '^[[:digit:]]*$'
  result_msg "检查 kubernetesVersion 格式" && RES_LEVEL=0
  RES_LEVEL=1 && test $(echo "${kubernetesMajorMinor} >= 1.22" | bc) -eq 1
  result_msg "检查 kubernetesVersion >= 1.22" && RES_LEVEL=0

  # 检查 cri
  RES_LEVEL=1 && test ${criSocket}
  result_msg "检查 criSocket variable" && RES_LEVEL=0
  if [ ${criVersion} != 'latest' ]; then
    if [ ${criName} = 'containerd' ]; then
      RES_LEVEL=1 && test $(echo "${criVersion%.*} >= 1.5" | bc) -eq 1
      result_msg "检查 criVersion >= 1.5" && RES_LEVEL=0
    fi
  fi
}


# 查看所有变量
variables_display_test() {
  # system variables
  echo "SYSTEM_RELEASE=${SYSTEM_RELEASE}"
  echo "SYSTEM_PACKAGE=${SYSTEM_PACKAGE}"
  echo "SYSTEM_VERSION=${SYSTEM_VERSION}"
  # master1 variables
  echo "MASTER1_IP=${MASTER1_IP}"
  echo "MASTER1_NAME=${MASTER1_NAME}"
  # host variables
  echo "HOST_IP=${HOST_IP}"
  echo "HOST_NAME=${HOST_NAME}"
  echo "HOST_ROLE=${HOST_ROLE}"
  # kubernetes variables
  echo "remoteScriptDir=${remoteScriptDir}"
  echo "localMirror=${localMirror}"
  echo "kubernetesVersion=${kubernetesVersion}"
  echo "crictlVersion=${crictlVersion}"
  echo "controlPlaneAddress=${controlPlaneAddress}"
  echo "controlPlanePort=${controlPlanePort}"
  echo "imageRepository=${imageRepository}"
  echo "criName=${criName}"
  echo "criVersion=${criVersion}"
  echo "privateRepository=${privateRepository}"
  echo "certificatesVaild=${certificatesVaild}"
  echo "certificatesSize=${certificatesSize}"
  echo "serviceSubnet=${serviceSubnet}"
  echo "apiServerClusterIP=${apiServerClusterIP}"
  echo "podSubnet=${podSubnet}"
  echo "nodePassword=${nodePassword}"
  # auto make
  echo "controlPlaneEndpoint=${controlPlaneEndpoint}"
  echo "criSocket=${criSocket}"
  # nodes class
  echo "NODES_ALL=${NODES_ALL}"
  echo "NODES_NOT_MASTER1=${NODES_NOT_MASTER1}"
  echo "NODES_MASTER1_MASTER=${NODES_MASTER1_MASTER}"
  echo "NODES_MASTER=${NODES_MASTER}"
  echo "NODES_WORK=${NODES_WORK}"
  # upgrade cluster
  echo "upgradeVersion=${upgradeVersion}"
  echo "certificateRenewal=${certificateRenewal}"
}


# 设置所有变量
variables_settings() {
  variables_check_config
  variables_set_system
  variables_install_dependencies
  variables_set_master1
  variables_set_host
  variables_read_config
  variables_default_config
}


# 设置所有变量(remote.sh)
variables_settings_remote() {
  variables_check_config
  variables_set_system
  variables_install_dependencies
  variables_set_master1
  variables_nodes_class
  variables_read_config
  variables_default_config
}

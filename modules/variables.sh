# 变量

variables_by_master1() {
    # 配置文件中获取 master1 变量
    MASTER1_IP="$(yq -M '.nodes.master1.address' ${KUBE_CONF} | grep -v '^null$')"
    MASTER1_NAME="$(yq -M '.nodes.master1.domain' ${KUBE_CONF} | grep -v '^null$')"
}

variables_by_nodes() {
    # 从配置文件中获取 nodes 信息，并分类
    NODES_MASTER="$(yq -M '.nodes.master[].address' ${KUBE_CONF} | tr '\n' ' ' | sed 's/ *$//')"
    NODES_WORK="$(yq -M '.nodes.work[].address' ${KUBE_CONF} | tr '\n' ' ' | sed 's/ *$//')"
    NODES_ALL="${MASTER1_IP} ${NODES_MASTER} ${NODES_WORK}"
    NODES_NOT_MASTER1="${NODES_MASTER} ${NODES_WORK}"
    NODES_MASTER1_MASTER="${MASTER1_IP} ${NODES_MASTER}"
}

variables_by_localhost() {
    local index
    # 从本机 ip 和配置文件中，获取 name 和 role 信息
    if [ ${HOST_IP} = ${MASTER1_IP} ]; then
        HOST_NAME=${MASTER1_NAME}
        HOST_ROLE='master1'
    elif tmp_var=${HOST_IP} yq -M '.nodes.master[].address == strenv(tmp_var)' ${KUBE_CONF} | grep -Eqi 'true'; then
        index=$(tmp_var=${HOST_IP} yq -M '.nodes.master[].address | select(. == strenv(tmp_var)) | path | .[-2]' ${KUBE_CONF})
        HOST_NAME=$(tmp_var=${index} yq -M '.nodes.master[env(tmp_var)].domain' ${KUBE_CONF})
        HOST_ROLE='master'
    elif tmp_var=${HOST_IP} yq -M '.nodes.work[].address == strenv(tmp_var)' ${KUBE_CONF} | grep -Eqi 'true'; then
        index=$(tmp_var=${HOST_IP} yq -M '.nodes.work[].address | select(. == strenv(tmp_var)) | path | .[-2]' ${KUBE_CONF})
        HOST_NAME=$(tmp_var=${index} yq -M '.nodes.work[env(tmp_var)].domain' ${KUBE_CONF})
        HOST_ROLE='work'
    fi
}

variables_by_config() {
    # 从配置文件中获取 config 信息
    remoteScriptDir="$(yq -M '.remoteScriptDir' ${KUBE_CONF} | grep -v '^null$')"
    localMirror="$(yq -M '.localMirror' ${KUBE_CONF} | grep -v '^null$')"
    nodeUser="$(yq -M '.nodeUser' ${KUBE_CONF} | grep -v '^null$')"
    nodePassword="$(yq -M '.nodePassword' ${KUBE_CONF} | grep -v '^null$')"
    etcdctlVersion="$(yq -M '.etcdctlVersion' ${KUBE_CONF} | grep -v '^null$')"
    # cluster
    kubernetesVersion="$(yq -M '.cluster.kubernetesVersion' ${KUBE_CONF} | grep -v '^null$')"
    crictlVersion="$(yq -M '.cluster.crictlVersion' ${KUBE_CONF} | grep -v '^null$')"
    controlPlaneAddress="$(yq -M '.cluster.controlPlaneAddress' ${KUBE_CONF} | grep -v '^null$')"
    controlPlanePort="$(yq -M '.cluster.controlPlanePort' ${KUBE_CONF} | grep -v '^null$')"
    imageRepository="$(yq -M '.cluster.imageRepository' ${KUBE_CONF} | grep -v '^null$')"
    kubeadmSignCertificate="$(yq -M '.cluster.kubeadmSignCertificate' ${KUBE_CONF} | grep -v '^null$')"
    certificatesVaild="$(yq -M '.cluster.certificatesVaild' ${KUBE_CONF} | grep -v '^null$')"
    certificatesSize="$(yq -M '.cluster.certificatesSize' ${KUBE_CONF} | grep -v '^null$')"
    caCertificateValidityPeriod="$(yq -M '.cluster.caCertificateValidityPeriod' ${KUBE_CONF} | grep -v '^null$')"
    certificateValidityPeriod="$(yq -M '.cluster.certificateValidityPeriod' ${KUBE_CONF} | grep -v '^null$')"
    serviceSubnet="$(yq -M '.cluster.serviceSubnet' ${KUBE_CONF} | grep -v '^null$')"
    apiServerClusterIP="$(yq -M '.cluster.apiServerClusterIP' ${KUBE_CONF} | grep -v '^null$')"
    podSubnet="$(yq -M '.cluster.podSubnet' ${KUBE_CONF} | grep -v '^null$')"
    # container
    criName="$(yq -M '.container.criName' ${KUBE_CONF} | grep -v '^null$')"
    criVersion="$(yq -M '.container.criVersion' ${KUBE_CONF} | grep -v '^null$')"
    criUpgradeReconfig="$(yq -M '.container.criUpgradeReconfig' ${KUBE_CONF} | grep -v '^null$')"
    privateRepository="$(yq -M '.container.privateRepository' ${KUBE_CONF} | grep -v '^null$')"
}

variables_by_default() {
    # 是否使用国内 yum/apt 镜像源
    localMirror=${localMirror:-'false'}
    # 节点密码, 默认为空(也就是手动输入)
    nodeUser=${nodeUser:-'root'}
    nodePassword=${nodePassword:-''}
    # 节点安装 etcdctl 的 version
    etcdctlVersion=${etcdctlVersion:-'3.5.10'}
    # 远程集群主机存放 k8s 安装脚本的目录 (目录会在复制之前清空，请注意!!!)
    if [ ${nodeUser} ] && [ ${nodeUser} != "root" ]; then
        remoteScriptDir=${remoteScriptDir:-"/home/${nodeUser}/k8sRemoteScript"}
    else
        remoteScriptDir=${remoteScriptDir:-'/opt/k8sRemoteScript'}
    fi

    # k8s version(支持 1.24+, 不支持 latest)
    kubernetesVersion=${kubernetesVersion:-'1.32.0'}
    crictlVersion=${crictlVersion:-'latest'}
    # k8s controlPlaneEndpoint 地址和端口, 没有该参数无法添加 master 节点
    controlPlaneAddress=${controlPlaneAddress:-"${MASTER1_IP}"}
    controlPlanePort=${controlPlanePort:-'6443'}
    # k8s 各个组件的镜像仓库地址: pause(Include containerd)、etcd、api-server 等
    imageRepository=${imageRepository:-''} # 国内 registry.cn-hangzhou.aliyuncs.com/google_containers
    # k8s 集群安装或升级时, 是否使用 kubeadm 签发证书
    kubeadmSignCertificate=${kubeadmSignCertificate:-'true'}
    # 自签证书有效期和密钥大小(单位：天, 默认：50年)
    certificatesVaild=${certificatesVaild:-'18250'}
    certificatesSize=${certificatesSize:-'2048'}
    # kubeadm 新增证书期限配置, 仅 kubernetes >= 1.31 时生效(格式：8760h0m0s)
    caCertificateValidityPeriod=${caCertificateValidityPeriod:-''}
    certificateValidityPeriod=${certificateValidityPeriod:-''}
    # Services 子网和 API Server 集群内部地址 (即 Service 网络的第一个 IP)
    serviceSubnet=${serviceSubnet:-'10.96.0.0/16'}
    apiServerClusterIP=${apiServerClusterIP:-'10.96.0.1'}
    # Pod 网络, flannel 默认使用 10.244.0.0/16, 除非想修改 flannel 配置, 否则不要修改
    podSubnet=${podSubnet:-'10.244.0.0/16'}

    # 容器运行时: containerd(最新版本: latest, 具体版本: 1.6.9)
    criName=${criName:-'containerd'}
    criVersion=${criVersion:-'latest'}
    criUpgradeReconfig=${criUpgradeReconfig:-'false'}
    # 容器运行时: 配置 harbor 私库地址(http://192.168.13.13)
    privateRepository=${privateRepository:-''}
}

varialbes_by_auto() {
    # 自动生成的变量
    upgradeVersion=${kubernetesVersion}
    kubernetesMajorMinor=$(echo ${kubernetesVersion} | awk -F '.' '{print $1"."$2}')

    if [ "${controlPlaneAddress}" ] && [ "${controlPlanePort}" ]; then
        controlPlaneEndpoint="${controlPlaneAddress}:${controlPlanePort}"
    fi
    if [ ${criName} = 'containerd' ]; then
        criSocket='unix:///run/containerd/containerd.sock'
    fi
}

varialbes_install_dependencies() {
    if [ ! -e ${KUBE_BIN}/etcdctl ] || [ $(etcdctl version | grep 'etcdctl version' | awk '{print $3}') != "${etcdctlVersion}" ]; then
        curl -fsSL -o /tmp/etcd-linux-amd64.tar.gz https://github.com/etcd-io/etcd/releases/download/v${etcdctlVersion}/etcd-v${etcdctlVersion}-linux-amd64.tar.gz &&
            rm -rf /tmp/etcd-download-test && mkdir -p /tmp/etcd-download-test &&
            tar xzf /tmp/etcd-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1 &&
            rm -f /tmp/etcd-linux-amd64.tar.gz &&
            mv /tmp/etcd-download-test/etcdctl ${KUBE_BIN}/etcdctl
        result_msg "安装 etcdctl"
        if [ -e /tmp/etcd-download-test/etcdutl ]; then
            mv /tmp/etcd-download-test/etcdutl ${KUBE_BIN}/etcdutl
            result_msg "安装 etcdutl"
        fi
    fi
}

# 查看所有变量
variables_display() {
    # const
    echo "KUBE_CONF=${KUBE_CONF}"
    echo "KUBE_BIN=${KUBE_BIN}"
    echo "HOST_IP=${HOST_IP}"
    echo "SYSTEM_RELEASE=${SYSTEM_RELEASE}"
    echo "SYSTEM_PACKAGE=${SYSTEM_PACKAGE}"
    echo "SYSTEM_VERSION=${SYSTEM_VERSION}"
    # master1
    echo "MASTER1_IP=${MASTER1_IP}"
    echo "MASTER1_NAME=${MASTER1_NAME}"
    # localhost
    echo "HOST_NAME=${HOST_NAME}"
    echo "HOST_ROLE=${HOST_ROLE}"
    # config .
    echo "remoteScriptDir=${remoteScriptDir}"
    echo "localMirror=${localMirror}"
    echo "nodeUser=${nodeUser}"
    echo "nodePassword=${nodePassword}"
    echo "etcdctlVersion=${etcdctlVersion}"
    # config .cluster
    echo "kubernetesVersion=${kubernetesVersion}"
    echo "crictlVersion=${crictlVersion}"
    echo "controlPlaneAddress=${controlPlaneAddress}"
    echo "controlPlanePort=${controlPlanePort}"
    echo "imageRepository=${imageRepository}"
    echo "kubeadmSignCertificate=${kubeadmSignCertificate}"
    echo "certificatesVaild=${certificatesVaild}"
    echo "certificatesSize=${certificatesSize}"
    echo "serviceSubnet=${serviceSubnet}"
    echo "apiServerClusterIP=${apiServerClusterIP}"
    echo "podSubnet=${podSubnet}"
    # config .container
    echo "criName=${criName}"
    echo "criVersion=${criVersion}"
    echo "privateRepository=${privateRepository}"
    # auto
    echo "upgradeVersion=${upgradeVersion}"
    echo "kubernetesMajorMinor=${kubernetesMajorMinor}"
    echo "controlPlaneEndpoint=${controlPlaneEndpoint}"
    echo "criSocket=${criSocket}"
    # nodes
    echo "NODES_ALL=${NODES_ALL}"
    echo "NODES_NOT_MASTER1=${NODES_NOT_MASTER1}"
    echo "NODES_MASTER1_MASTER=${NODES_MASTER1_MASTER}"
    echo "NODES_MASTER=${NODES_MASTER}"
    echo "NODES_WORK=${NODES_WORK}"
}

# 设置所有变量(local.sh)
variables_local() {
    SERVER_TYPE="node"
    variables_by_master1
    variables_by_localhost
    variables_by_config
    variables_by_default
    varialbes_by_auto
}

# 设置所有变量(remote.sh)
variables_remote() {
    SERVER_TYPE="devops"
    variables_by_master1
    variables_by_nodes
    variables_by_config
    variables_by_default
    varialbes_by_auto
    varialbes_install_dependencies
}

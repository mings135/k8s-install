# 常量

KUBEADM_CONFIG='/etc/kubernetes'
KUBEADM_PKI="${KUBEADM_CONFIG}/pki"
KUBEADM_MANIFESTS="${KUBEADM_CONFIG}/manifests"
KUBELET_PKI='/var/lib/kubelet/pki'
JOIN_TOKEN_INTERVAL=7200
ETCD_DATA_DIR="/var/lib/etcd" # 目前仅用于 etcd 备份恢复
RES_LEVEL=0
RES_COLUM=60
KUBE_CONF="${script_dir}/config/kube.yaml"
KUBE_RECORD="${script_dir}/config/record.txt"
KUBE_BIN="${script_dir}/bin"
HOST_IP=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')

if [ ! -e ${KUBE_BIN} ]; then
    mkdir ${KUBE_BIN}
fi

export PATH=${KUBE_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ -f /etc/redhat-release ]; then
    SYSTEM_RELEASE="centos"
    SYSTEM_PACKAGE="dnf"
    if cat /etc/redhat-release | grep -Eqi 'release 8'; then
        SYSTEM_VERSION=8
    elif cat /etc/redhat-release | grep -Eqi 'release 9'; then
        SYSTEM_VERSION=9
    fi
elif cat /etc/issue | grep -Eqi "debian"; then
    SYSTEM_RELEASE="debian"
    SYSTEM_PACKAGE="apt-get"
    if cat /etc/issue | grep -Eqi 'linux 11'; then
        SYSTEM_VERSION=11
    elif cat /etc/issue | grep -Eqi 'linux 12'; then
        SYSTEM_VERSION=12
    fi
fi

# --- 函数常量 ---
install_apps() {
    local ver_val name_val ver_long
    # 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
    if [ ${SYSTEM_RELEASE} = 'debian' ]; then
        export DEBIAN_FRONTEND=noninteractive
    fi
    # 安装 app, $1 需要安装的软件, space 分隔, $2 额外的参数
    for i in $1; do
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
            ${SYSTEM_PACKAGE} install -y ${i} $2 &>/dev/null
            result_msg "安装 $i"
        else
            ${SYSTEM_PACKAGE} install -y ${i} &>/dev/null
            result_msg "安装 $i"
        fi
    done
}

remove_apps() {
    # 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
    if [ ${SYSTEM_RELEASE} = 'debian' ]; then
        export DEBIAN_FRONTEND=noninteractive
    fi
    for i in $1; do
        ${SYSTEM_PACKAGE} remove -y ${i} &>/dev/null
        result_msg "移除 $i"
    done
}

update_mirror_source_cache() {
    # centos
    if [ ${SYSTEM_RELEASE} = 'centos' ]; then
        ${SYSTEM_PACKAGE} makecache >/dev/null
        result_msg "重新 yum makecache"
    # debian
    elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
        ${SYSTEM_PACKAGE} update >/dev/null
        result_msg "重新 apt update"
    fi
}

compare_version_ge() {
    local ver1_major=$(echo $1 | awk -F '.' '{print $1}')
    local ver1_minor=$(echo $1 | awk -F '.' '{print $2}')
    local ver2_major=$(echo $2 | awk -F '.' '{print $1}')
    local ver2_minor=$(echo $2 | awk -F '.' '{print $2}')
    if [ ${ver1_major} -gt ${ver2_major} ]; then
        return 0
    elif [ ${ver1_major} -eq ${ver2_major} ]; then
        if [ ${ver1_minor} -ge ${ver2_minor} ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

blue_font() {
    echo -e "\033[34m\033[01m$1\033[0m"
}

const_auto_font() {
    # $1 range 0 ~ 7
    echo -e "\033[3$1m\033[01m$2\033[0m"
}

const_action() {
    local tmp_result tmp_rc tmp_color
    local tmp_msg=$1
    echo -n "$tmp_msg "
    shift
    if "$@"; then
        tmp_result="success"
        tmp_rc=0
        tmp_color=32
    else
        tmp_result="failure"
        tmp_rc=1
        tmp_color=31
    fi
    echo -ne "\033[${RES_COLUM}G[ \033[${tmp_color}m\033[01m${tmp_result}\033[0m ]"
    echo -ne "\r"
    echo
    return $tmp_rc
}

result_msg() {
    local tmp_rc=$?
    local tmp_num tmp_color
    if [ ${tmp_rc} -eq 0 ]; then
        if [ ${RES_LEVEL} -eq 0 ]; then
            tmp_num="$(echo ${HOST_IP} | awk -F '.' '{print $NF}')"
            tmp_color=$((${tmp_num} % 7))
            const_action "$(const_auto_font ${tmp_color} ${HOST_IP}): $*" "/bin/true"
        fi
    else
        tmp_num="$(echo ${HOST_IP} | awk -F '.' '{print $NF}')"
        tmp_color=$((${tmp_num} % 7))
        const_action "$(const_auto_font ${tmp_color} ${HOST_IP}): $*" "/bin/false"
        exit 1
    fi
}

# 安装必要的前置工具(1)
const_install_dependencies() {
    local apps=''
    for i in curl tar; do
        if ! which $i &>/dev/null; then
            apps="${apps} $i"
        fi
    done
    if [ "$apps" ]; then
        update_mirror_source_cache
        install_apps "${apps}"
    fi

    if [ ! -e ${KUBE_BIN}/yq ]; then
        curl -fsSL -o ${KUBE_BIN}/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 &&
            chmod +x ${KUBE_BIN}/yq
        result_msg "安装 yq"
    fi
}

# 生成极简配置 kube.yaml
const_kube_conf() {
    if [ ! -e ${KUBE_CONF} ]; then
        touch ${KUBE_CONF}
        yq -i '.nodeUser = ""' ${KUBE_CONF}
        yq -i '.nodes.master1.domain = "m1.k8s"' ${KUBE_CONF}
        tmp_var=${HOST_IP} yq -i '.nodes.master1.address = strenv(tmp_var)' ${KUBE_CONF}
        yq -i '. head_comment="集群初始化后请勿随意修改配置, 否则可能导致无法正常运行!!!"' ${KUBE_CONF}
        blue_font "已生成极简配置, 修改请 vi ${KUBE_CONF}, 继续请重新运行"
        yq ${KUBE_CONF}
        exit 1
    fi
}

# 预处理
const_init() {
    const_install_dependencies
    const_kube_conf
}

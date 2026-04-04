# 常量模块

GPG_DIR='/etc/apt/keyrings'
KUBEADM_CONFIG='/etc/kubernetes'
KUBEADM_PKI="${KUBEADM_CONFIG}/pki"
KUBEADM_MANIFESTS="${KUBEADM_CONFIG}/manifests"
KUBELET_PKI='/var/lib/kubelet/pki'
ETCD_DATA="/var/lib/etcd"
KUBE_BIN="${script_dir}/bin"
KUBE_CONF="${script_dir}/config"
KUBE_BACKUP="${script_dir}/backup"
KUBE_KUBEADM="${KUBE_CONF}/kubeadm-config.yaml"
KUBE_FILE="${KUBE_CONF}/kube.yaml"
KUBE_RECORD="${KUBE_CONF}/record.yaml"
RES_LEVEL=0
RES_COLUM=50

script_own=$(stat -c %U ${script_dir})
HOST_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')

if [[ ! -d "${GPG_DIR}" ]]; then
  mkdir -p ${GPG_DIR}
fi

if [[ ! -d "${KUBE_BIN}" ]]; then
  mkdir -p ${KUBE_BIN}
fi

if [[ ! -d "${KUBE_CONF}" ]]; then
  mkdir -p ${KUBE_CONF}
fi

if [[ ! -d "${KUBE_BACKUP}" ]]; then
  mkdir -p ${KUBE_BACKUP}
fi

export PATH=${KUBE_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [[ -f /etc/debian_version ]]; then
  OS_NAME="debian"
  OS_VERSION=$(cat /etc/debian_version | cut -d'.' -f1)
  # 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
  export DEBIAN_FRONTEND=noninteractive
fi

const_action() {
  local result rc color
  local msg=$1

  shift
  if "$@"; then
    result="success"
    rc=0
    color=32
  else
    result="failure"
    rc=1
    color=31
  fi
  printf "%-${RES_COLUM}s [ \033[%sm\033[01m%s\033[0m ]\n" "$msg" "$color" "$result"
  return $rc
}

# 执行结果捕获
result_msg() {
  local rc=$?
  if [[ ${rc} -eq 0 ]]; then
    if [[ ${RES_LEVEL} -eq 0 ]]; then
      const_action "$*" "/bin/true"
    fi
  else
    const_action "$*" "/bin/false"
    exit 1
  fi
}

const_normalize_version() {
  # 统一处理：去v、去后缀、补齐三位纯数字
  echo "${1#v}" | awk -F. '{ printf("%d.%d.%d\n", $1, $2, $3) }'
}

# 版本号比对 (v1 >= v2)
version_ge() {
  local v1=$(const_normalize_version "$1")
  local v2=$(const_normalize_version "$2")

  if [[ "$v1" == "$v2" ]]; then
    return 0
  fi

  local min_ver=$(printf '%s\n%s' "$v1" "$v2" | LC_ALL=C sort -V | head -n1)

  if [[ "$min_ver" == "$v2" ]]; then
    return 0
  else
    return 1
  fi
}

# 版本号比对 (v1 > v2)
version_gt() {
  local v1="$1" v2="$2"

  if [[ "$v1" == "$v2" ]]; then
    return 1
  fi

  version_ge "$v1" "$v2"
}

blue_font() {
  echo -e "\033[34m\033[01m$1\033[0m"
}

get_config() {
  yq -M "$1 // \"\"" "${KUBE_FILE}"
}

set_config() {
  val="$2" yq -i "$1 = strenv(val)" "${KUBE_FILE}"
}

get_record() {
  yq -M "$1 // \"\"" "${KUBE_RECORD}"
}

set_record() {
  val="$2" yq -i "$1 = strenv(val)" "${KUBE_RECORD}"
}

# 软件包安装逻辑 (支持 Debian 版本自动补全)
install_pkgs() {
  local name ver full
  local list="$1"
  local args="$2"

  # 遍历安装列表
  for i in ${list}; do
    # Debian 系统包含 = 时进行版本补全
    if [[ "$i" == *"="* ]]; then
      name=$(echo "$i" | cut -d'=' -f1)
      ver=$(echo "$i" | cut -d'=' -f2)
      full=$(apt-cache madison "${name}" 2>/dev/null | awk '{print $3}' | grep -w "^${ver}" | head -n 1)
      if [[ -n "${full}" ]]; then
        i="${name}=${full}"
      fi
    fi

    apt install -y ${i} ${args} &>/dev/null
    result_msg "安装 $i"
  done
}

remove_pkgs() {
  local list="$1"
  local args="$2"

  for i in ${list}; do
    if dpkg -l | grep -q "^ii[[:space:]]\+${i}[[:space:]]"; then
      apt remove -y ${i} ${args} &>/dev/null
      result_msg "移除 $i"
    fi
  done
}

update_pkgs() {
  apt update >/dev/null
  result_msg "重新 apt update"
}

hold_pkgs() {
  local list="$1"

  for i in ${list}; do
    apt-mark hold ${i} >/dev/null
    result_msg "锁住 $i"
  done
}

unhold_pkgs() {
  local list="$1"

  for i in ${list}; do
    if apt-mark showhold | grep -q "^${i}$"; then
      apt-mark unhold ${i} >/dev/null
      result_msg "解锁 $i"
    fi
  done
}

# 安装必要的前置工具(1)
const_install_dependencies() {
  if [[ ! -f "${KUBE_BIN}/yq" ]]; then
    blue_font "下载安装 yq 到 ${KUBE_BIN} 目录"
    curl -fsSL -o ${KUBE_BIN}/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
      && chmod +x ${KUBE_BIN}/yq
  fi

  if [[ ! -f "${KUBE_BIN}/rrcmd" ]]; then
    blue_font "下载安装 rrcmd 到 ${KUBE_BIN} 目录"
    curl -fsSL -o ${KUBE_BIN}/rrcmd https://github.com/mings135/rrcmd/releases/latest/download/rrcmd_linux_amd64 \
      && chmod +x ${KUBE_BIN}/rrcmd
  fi
}

# 生成极简配置 kube.yaml
const_create_base_config() {
  if [[ ! -f "${KUBE_FILE}" ]]; then
    val1="${HOST_IP}" yq -n '
      .nodeUser = "" |
      .cluster.kubernetesVersion = "" |
      .container = {} |
      .nodes.master1.domain = "m1.k8s" |
      .nodes.master1.address = strenv(val1) |
      .join = {} |
      .kubeconfig = {} |
      (.join | key) head_comment = "以下内容自动生成, 请勿修改!!!" |
      . head_comment = "请勿随意修改配置, 否则可能导致无法正常运行!!!"
    ' >${KUBE_FILE}

    blue_font "已自动生成极简配置, 修改请 vi ${KUBE_FILE}, 继续请重新运行"
    yq ${KUBE_FILE}
    exit 0
  fi
}

# 生成记录文件 record.yaml
const_create_record_file() {
  if [[ ! -f "${KUBE_RECORD}" ]]; then
    yq -n '
      .sys = {} |
      .cri = {} |
      .k8s = {} |
      .cluster = {} |
      .backup = {} |
      . head_comment = "集群记录文件, 非常重要, 自动生成, 请勿修改!!!"
    ' >${KUBE_RECORD}

    blue_font "已自动生成记录文件 ${KUBE_RECORD}, 请勿修改!!!"
  fi
}

if [[ "${script_type}" == "local" ]]; then
  const_create_record_file
fi

if [[ "${script_type}" == "remote" ]]; then
  const_install_dependencies
  const_create_base_config
fi

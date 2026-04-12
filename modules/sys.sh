# 系统基础设置

# 设置 chrony 配置
sys_chrony_config() {
  cat >$1 <<EOF
# 阿里官方配置
server ntp.aliyun.com iburst
stratumweight 0
driftfile /var/lib/chrony/drift
rtcsync
makestep 10 3
bindcmdaddress 127.0.0.1
bindcmdaddress ::1
keyfile /etc/chrony.keys
commandkey 1
generatecommandkey
logchange 0.5
logdir /var/log/chrony
EOF
  result_msg "[Config] chrony"
}

# 安装必要的工具(3)
sys_install_dependencies() {
  # 基础工具
  install_pkgs 'chrony ca-certificates curl gnupg lsb-release tar'
  # k8s 需要的工具
  install_pkgs 'socat conntrack ipvsadm nfs-common'

  # 优化 chrony 配置
  if systemctl list-unit-files chrony.service &>/dev/null; then
    sys_chrony_config '/etc/chrony/chrony.conf'
    systemctl restart chrony &>/dev/null
    result_msg '[Restart] chrony'
  fi
}

# 优化系统设置
sys_init_base() {
  # 设置 hostname (必须)
  if [[ "${HOST_NAME}" != "$(hostname)" ]]; then
    hostnamectl set-hostname "${HOST_NAME}"
    result_msg "[Modify] name:${HOST_NAME}"
  fi

  # 关闭 swap (必须)
  local f="/etc/fstab"
  if grep -qE '^[^#].*swap' "$f"; then
    sed -i '/swap/ s/^[^#]/#&/' "$f" && swapoff -a
    result_msg '[Disable] swap'
  fi

  # 停用 ufw(必须)
  if systemctl list-unit-files ufw.service &>/dev/null; then
    systemctl disable --now ufw &>/dev/null
    result_msg "[Disable] ufw"
  fi

  # 关闭 selinux (必须)
  f="/etc/selinux/config"
  if [[ -f "$f" ]] && grep -qE '^SELINUX=(enforcing|permissive)' "$f"; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$f" && setenforce 0
    result_msg "[Disable] selinux"
  fi

  # 设置系统 limits
  local lim="65535"
  f="/etc/security/limits.d/90-k8s.conf"
  if [[ ! -f "$f" ]]; then
    cat >"$f" <<EOF
root - nofile ${lim}
root - nproc ${lim}
* - nofile ${lim}
* - nproc ${lim}
EOF
    result_msg '[Modify] limits'
  fi
}

# 加载 ipvs 模块
sys_load_modules() {
  local f="/etc/modules-load.d/ipvs.conf"
  local rc=0
  # 开机自加载 ipvs 模块
  cat >"$f" <<EOF
ip_vs
ip_vs_rr
ip_vs_lc
nf_conntrack
overlay
br_netfilter
EOF
  # 即刻加载 ipvs 模块
  while read -r line; do
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      continue
    fi
    modprobe $line
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      break
    fi
  done <"$f"
  [[ "$rc" -eq 0 ]]
  result_msg '[Loading] ip_vs nf_conntrack overlay br_netfilter'
}

# 优化内核参数
sys_optimize_kernel() {
  local f="/etc/sysctl.d/90-k8s.conf"
  cat >"$f" <<EOF
# [必须] 基础网络转发与桥接, 保证 Pod 网络互通
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1

# [必须] 禁用 Swap, 保证 Kubelet 正常运行
vm.swappiness = 0

# [必须] 中间件运行必须(ES/Redis等)
vm.max_map_count = 262144

# [优化] 关闭 IPv6, 防止不熟悉环境下的网络异常
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# [建议] 开启 BPF 即时编译, 显著提升转发性能
net.core.bpf_jit_enable = 1
net.core.bpf_jit_kallsyms = 1

# [提升] 提高连接追踪上限, 防止高并发丢包
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_buckets = 262144

# [提升] 解决端口回收慢, 防止端口耗尽
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1

# [提升] 提高系统句柄上限, 防止文件过多报错
fs.file-max = 2097152
fs.nr_open = 1048576
net.core.somaxconn = 32768

# [提升] 提高监控事件上限, 防止日志/Ingress组件异常
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# [稳定] 发生严重错误时自动重启, 不卡死
kernel.panic = 10
kernel.panic_on_oops = 1
EOF
  # 即刻加载优化的参数
  sysctl -p "$f" >/dev/null
  result_msg '[Optimize] kernel parameters'
}

# 基础设置
init_system() {
  update_pkgs
  sys_install_dependencies
  sys_init_base
  sys_load_modules
  sys_optimize_kernel
}

# 配置 /etc/hosts
init_etc_hosts() {
  local start="# KUBE-HOSTS-START"
  local end="# KUBE-HOSTS-END"

  sed -i "/${start}/,/${end}/d" /etc/hosts

  local dns="${MASTER1_IP} ${MASTER1_NAME}"
  local data="$(yq -M '.nodes.master + .nodes.work | .[] | .address + " " + .domain' "${KUBE_FILE}")"

  if [[ -n "${data}" ]]; then
    dns=$(printf '%s\n%s' "${dns}" "${data}")
  fi

  local domain="${controlPlaneEndpoint%:*}"
  local pattern="^([a-z0-9][-a-z0-9]*\.)+[a-z0-9]+[a-z]$"
  if [[ -n "${controlPlaneTarget}" ]] && [[ "${domain}" =~ ${pattern} ]]; then
    dns=$(printf '%s\n%s' "${dns}" "${controlPlaneTarget} ${domain}")
  fi

  echo "${start}" >>/etc/hosts \
    && echo "${dns}" >>/etc/hosts \
    && echo "${end}" >>/etc/hosts
  result_msg '[Modify] /etc/hosts'
}

# 初始化和优化系统，安装必要的软件，提供以下函数：
# init_system

# 必须先执行 base.sh


# 基础优化
optimization_basic() {
  local limit_file=65536

  sed -i 's/.*swap.*/#&/' /etc/fstab && swapoff -a
  result_msg "关闭 swap" || return 1

  if ! cat /etc/security/limits.conf |  grep -Eqi 'root - nofile'; then
    cat >> /etc/security/limits.conf << EOF
root - nofile ${limit_file}
root - nproc ${limit_file}
* - nofile ${limit_file}
* - nproc ${limit_file}
EOF
    result_msg '修改 ulimit' || return 1
  fi
}


# 加载 ipvs 模块
load_modules() {
  local nf_conn
  local ver=$(uname -r | awk -F '-' '{print $1}')
  [ $(echo "${ver%.*} >= 4.0" | bc) -eq 1 ] && nf_conn='nf_conntrack' || nf_conn='nf_conntrack_ipv4'
  # 开机自加载模块
  cat > /etc/modules-load.d/ipvs.conf << EOF
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
ip_vs_lc
${nf_conn}
overlay
br_netfilter
EOF
  cat /etc/modules-load.d/ipvs.conf | while read line
  do
    modinfo -F filename $line > /dev/null && modprobe $line
    result_msg "加载 module $line" || return 1
  done
}


# 优化内核参数
optimization_kernel() {
  cat > /etc/sysctl.d/k8s.conf << EOF
# 必要参数
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 =1
vm.swappiness = 0
net.ipv4.tcp_tw_recycle=0
net.ipv4.tcp_tw_reuse = 0
net.ipv4.tcp_timestamps = 1

# 优化参数
net.ipv4.ip_local_port_range = 10000    65000
net.ipv4.neigh.default.gc_thresh1 = 2048
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192
net.ipv4.tcp_keepalive_time = 900
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_wmem = 4096        12582912        16777216
net.ipv4.tcp_rmem = 4096        12582912        16777216

net.core.somaxconn=32768
net.core.wmem_max=16777216
net.core.rmem_max=16777216
net.core.rps_sock_flow_entries=8192
net.core.bpf_jit_enable=1
net.core.bpf_jit_harden=1
net.core.bpf_jit_kallsyms=1
net.core.dev_weight_tx_bias=1
vm.max_map_count=262144
fs.file-max=2097152
fs.nr_open=1048576
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
kernel.core_pattern=core
kernel.pid_max=65536
kernel.threads-max=65536

net.netfilter.nf_conntrack_buckets = 262144 # centos 7 not support
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_established = 900
EOF

  # buckets 无法在 CentOS7 中直接 sysctl，必须配置模块加载 options
  if [ "${sys_release}${sys_version}" = 'centos7' ]; then
    echo 262144 > /sys/module/nf_conntrack/parameters/hashsize
    result_msg "优化 ${sys_release}${sys_version} buckets" || return 1
    sed -i '/net.netfilter.nf_conntrack_buckets/d' /etc/sysctl.d/k8s.conf
    cat > /etc/modprobe.d/buckets.conf << EOF
options nf_conntrack hashsize=262144
EOF
    result_msg "添加 buckets 开机加载" || return 1
  fi

  sysctl --system > /dev/null
  result_msg '优化 kernel parameters' || return 1
}


# 优化系统
optimization_system() {
  optimization_basic || return 1
  load_modules || return 1
  optimization_kernel || return 1 
}


# 配置 chrony
chrony_config() {
  cat > $1 << EOF
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
  result_msg "配置 chronyd" || return 1
}


# 初始化配置
initial_config() {
  if [ ${HOST_NAME} != $(hostname) ]; then
    hostnamectl set-hostname "${HOST_NAME}"
    result_msg "设置 name:${HOST_NAME}" || return 1
  fi
    
  if cat /etc/ssh/sshd_config | grep -Eqi 'GSSAPIAuthentication yes|UseDNS yes'; then
    sed -e '/GSSAPIAuthentication yes/c GSSAPIAuthentication no' \
      -e '/UseDNS yes/c UseDNS no' \
      -i /etc/ssh/sshd_config
    result_msg "优化 sshd" || return 1
    systemctl restart sshd &> /dev/null
    result_msg "重启 sshd" || return 1
  fi

  if [ -f /etc/selinux/config ] && cat /etc/selinux/config | grep -Eqi 'SELINUX=enforcing'; then
    sed -i '/SELINUX=enforcing/s/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config && setenforce 0
    result_msg "关闭 selinux" || return 1
  fi

  if systemctl list-unit-files | grep -Eqi 'firewalld'; then
    systemctl disable --now firewalld &> /dev/null
    result_msg "停止 firewalld" || return 1
  fi
}


# 初始化系统（centos）
initial_centos() {
  # 安装必要的软件 docker 可能需要: device-mapper-persistent-data lvm2
  local apps='rsync ipvsadm chrony bc nfs-utils yum-utils'
  install_apps "${apps}" || return 1

  # 优化初始配置，然后 start
  initial_config || return 1
  # 优化 chrony 配置，然后 start
  if systemctl list-unit-files | grep -Eqi 'chronyd'; then
    chrony_config '/etc/chrony.conf'
    systemctl enable --now chronyd &> /dev/null
    result_msg '启动 chronyd' || return 1
  fi
}


# 初始化系统（debian）
initial_debian() {
  # 安装必要的软件
  local apps='rsync ipvsadm chrony bc nfs-common apt-transport-https ca-certificates curl gnupg lsb-release'
  install_apps "${apps}" || return 1

  # 优化初始配置，然后 start
  initial_config || return 1
  # 优化 chrony 配置，然后 start
  if systemctl list-unit-files | grep -Eqi 'chronyd'; then
    chrony_config '/etc/chrony/chrony.conf'
    systemctl restart chronyd &> /dev/null
    result_msg '重启 chronyd' || return 1
  fi
}


# 初始化系统（centos7）
initial_centos_7() {
  if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    # 设置 yum
    curl -fsSL https://mirrors.aliyun.com/repo/Centos-7.repo -o /etc/yum.repos.d/CentOS-Base.repo
    result_msg "更换 ${sys_pkg} repo" || return 1

    # 设置 epel
    curl -fsSL http://mirrors.aliyun.com/repo/epel-7.repo -o /etc/yum.repos.d/epel.repo
    result_msg "添加 epel repo" || return 1

    ${sys_pkg} makecache > /dev/null
    result_msg "重置 ${sys_pkg} cache" || return 1
  fi
     
  initial_centos || return 1
}


# 初始化系统（centos8）
initial_centos_8() {
  if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    # 设置 dnf
    if [ -f /etc/yum.repos.d/Rocky-BaseOS.repo ]; then
      sed -e 's|^mirrorlist=|#mirrorlist=|g' \
        -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' \
        -i.bak /etc/yum.repos.d/Rocky-*.repo
      result_msg "更换 ${sys_pkg} link" || return 1
    elif [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
      curl -fsSL https://mirrors.aliyun.com/repo/Centos-8.repo -o /etc/yum.repos.d/CentOS-Base.repo
      result_msg "更换 ${sys_pkg} repo" || return 1
    fi

    # 设置 epel
    install_apps "epel-release"
    sed -e 's|^#baseurl=https://download.example/pub|baseurl=https://mirrors.aliyun.com|' \
      -e 's|^metalink|#metalink|' \
      -i /etc/yum.repos.d/epel*
    result_msg "更换 epel link" || return 1

    ${sys_pkg} makecache > /dev/null
    result_msg "重置 ${sys_pkg} cache" || return 1
  fi

  # CentOS 8 额外需要的工具
  install_apps "iproute-tc"

  initial_centos || return 1
}


# 初始化系统（debian10）
initial_debian_10() {
  initial_debian || return 1
}


initial_debian_11() {
  initial_debian || return 1
}


init_system() {
  initial_${sys_release}_${sys_version} || exit 1
  optimization_system || exit 1
}
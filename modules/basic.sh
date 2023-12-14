# 系统基础设置


# 设置 cri yum 源
basic_set_repos_cri() {
  # centos 设置 docker 源
  if [ ${criName} = 'containerd' ] && [ ${SYSTEM_RELEASE} = 'centos' ]; then
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null
    result_msg "添加 docker repo"
    if [ ${localMirror} -ne 0 ]; then
      sed -e 's+download.docker.com+mirrors.tuna.tsinghua.edu.cn/docker-ce+' \
        -e '/^gpgcheck=1/s/gpgcheck=1/gpgcheck=0/' \
        -i /etc/yum.repos.d/docker-ce.repo
      result_msg "修改 docker repo"
    fi
  fi

  # debian 设置 docker 源
  if [ ${criName} = 'containerd' ] && [ ${SYSTEM_RELEASE} = 'debian' ]; then
    local list_file='/etc/apt/sources.list.d/docker.list'
    local gpg_file='/etc/apt/keyrings/docker-archive-keyring.gpg'
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --yes --dearmor -o ${gpg_file}
    result_msg "添加 docker gpg"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${gpg_file}] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > ${list_file}
    result_msg "添加 docker repo"
    if [ ${localMirror} -ne 0 ];then
      sed -i 's+download.docker.com+mirrors.tuna.tsinghua.edu.cn/docker-ce+' ${list_file}
      result_msg "修改 repo source"
    fi
  fi
}


# 设置 kubernetes 源
basic_set_repos_kubernetes() {
  # centos 设置 kubernetes 源(>= 1.28)
  if [ $(echo "${kubernetesMajorMinor} >= 1.28" | bc) -eq 1 ] && [ ${SYSTEM_RELEASE} = 'centos' ]; then
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${kubernetesMajorMinor}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${kubernetesMajorMinor}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
    result_msg "添加 k8s repo"
  fi

  # centos 设置 kubernetes 源(< 1.28)
  if [ $(echo "${kubernetesMajorMinor} < 1.28" | bc) -eq 1 ] && [ ${SYSTEM_RELEASE} = 'centos' ]; then
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
    result_msg "添加 k8s repo"
    if [ ${localMirror} -ne 0 ];then
      sed -e 's+packages.cloud.google.com+mirrors.tuna.tsinghua.edu.cn/kubernetes+' \
        -e '/^gpgcheck=1/s/gpgcheck=1/gpgcheck=0/' \
        -i /etc/yum.repos.d/kubernetes.repo
      result_msg "修改 k8s repo"
    fi
  fi
  
  # debian 所需变量(/etc/apt/keyrings 在 request 中创建)
  local list_file='/etc/apt/sources.list.d/kubernetes.list'
  local gpg_file='/etc/apt/keyrings/kubernetes-archive-keyring.gpg'
  
  # debian 设置 kubernetes 源(>= 1.28)
  if [ $(echo "${kubernetesMajorMinor} >= 1.28" | bc) -eq 1 ] && [ ${SYSTEM_RELEASE} = 'debian' ]; then
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --yes --dearmor -o ${gpg_file}
    result_msg "添加 k8s pgp"
    echo "deb [signed-by=${gpg_file}] https://pkgs.k8s.io/core:/stable:/v${kubernetesMajorMinor}/deb/ /" > ${list_file}
    result_msg "添加 k8s repo"
  fi

  # debian 设置 kubernetes 源(< 1.28)
  if [ $(echo "${kubernetesMajorMinor} < 1.28" | bc) -eq 1 ] && [ ${SYSTEM_RELEASE} = 'debian' ]; then
    if [ ${localMirror} -ne 0 ];then
      # open local mirror
      curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | gpg --yes --dearmor -o ${gpg_file}
      result_msg "添加 k8s pgp"
      echo "deb [signed-by=${gpg_file}] https://mirrors.tuna.tsinghua.edu.cn/kubernetes/apt/ kubernetes-xenial main" > ${list_file}
      result_msg "添加 k8s repo"
    else
      # official mirror
      curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | gpg --yes --dearmor -o ${gpg_file}
      result_msg "添加 k8s pgp"
      echo "deb [signed-by=${gpg_file}] https://apt.kubernetes.io/ kubernetes-xenial main" > ${list_file}
      result_msg "添加 k8s repo"
    fi
  fi
}


# 重置软件源缓存
basic_reset_repos_cache() {
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


# 设置 chrony 配置
basic_set_chrony_config() {
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
  result_msg "配置 chronyd"
}


# 安装必要的工具 (centos)
basic_install_request_centos() {
  # 安装 EPEL 源
  if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    install_apps "epel-release"
    if [ ${localMirror} -ne 0 ]; then
      sed -e 's!^metalink=!#metalink=!g' \
        -e 's!^#baseurl=!baseurl=!g' \
        -e 's!//download\.fedoraproject\.org/pub!//mirrors.tuna.tsinghua.edu.cn!g' \
        -e 's!//download\.example/pub!//mirrors.tuna.tsinghua.edu.cn!g' \
        -e 's!http://mirrors!https://mirrors!g' \
        -i /etc/yum.repos.d/epel*.repo
      result_msg "修改 epel repo"
    fi
  fi
  # install tools
  install_apps 'ipvsadm chrony iproute-tc nfs-utils yum-utils'
  # 优化 chrony 配置
  if systemctl list-unit-files | grep -Eqi 'chronyd'; then
    basic_set_chrony_config '/etc/chrony.conf'
    systemctl enable chronyd &> /dev/null \
      && systemctl restart chronyd
    result_msg '启动 chronyd'
  fi
}


# 安装必要的工具 (debian)
basic_install_request_debian() {
  # install tools
  install_apps 'ipvsadm chrony nfs-common ca-certificates curl gnupg lsb-release'
  # 创建必要目录
  if [ ! -e /etc/apt/keyrings ]; then
    mkdir -p /etc/apt/keyrings
  fi
  # 优化 chrony 配置
  if systemctl list-unit-files | grep -Eqi 'chronyd'; then
    basic_set_chrony_config '/etc/chrony/chrony.conf'
    systemctl restart chronyd &> /dev/null
    result_msg '重启 chronyd'
  fi
}


# 优化系统设置
basic_optimization_system() {
  local limits_val=65536
  # 设置 hostname (必须)
  if [ ${HOST_NAME} != $(hostname) ]; then
    hostnamectl set-hostname "${HOST_NAME}"
    result_msg "设置 name:${HOST_NAME}"
  fi
  # 关闭 swap (必须)
  if grep -Eqi '^[^#].*swap.*' /etc/fstab; then
    sed -i 's/.*swap.*/#&/' /etc/fstab && swapoff -a
    result_msg "关闭 swap"
  fi
  # 停用 firewalld(必须)
  if systemctl list-unit-files | grep -Eqi 'firewalld'; then
    systemctl disable --now firewalld &> /dev/null
    result_msg "停止 firewalld"
  fi
  # 关闭 selinux (必须)
  if [ -f /etc/selinux/config ] && cat /etc/selinux/config | grep -Eqi 'SELINUX=enforcing'; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config && setenforce 0
    result_msg "关闭 selinux"
  fi
  # 设置系统 limits
  if ! cat /etc/security/limits.conf |  grep -Eqi '^root|^\*'; then
    cat >> /etc/security/limits.conf << EOF
root - nofile ${limits_val}
root - nproc ${limits_val}
* - nofile ${limits_val}
* - nproc ${limits_val}
EOF
    result_msg '修改 limits'
  fi
}


# 加载 ipvs 模块
basic_load_ipvs_modules() {
  local ver=$(uname -r | awk -F '-' '{print $1}')
  # 内核版本 >=4.0, 模块名称: nf_conntrack
  if [ $(echo "${ver%.*} >= 4.0" | bc) -eq 1 ]; then
    local nf_conn='nf_conntrack'
  else
    local nf_conn='nf_conntrack_ipv4'
  fi
  # 开机自加载 ipvs 模块
  cat > /etc/modules-load.d/ipvs.conf << EOF
ip_vs
ip_vs_rr
ip_vs_wrr
${nf_conn}
overlay
br_netfilter
EOF
  # 即刻加载 ipvs 模块
  while read line
  do
    modinfo -F filename $line > /dev/null && modprobe $line
    result_msg "加载 module $line"
  done < /etc/modules-load.d/ipvs.conf
}


# 优化内核参数
basic_optimization_kernel_parameters() {
  cat > /etc/sysctl.d/k8s.conf << EOF
# 必要参数
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 =1
vm.swappiness = 0
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
fs.file-max=419430
fs.nr_open=1048576
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
kernel.pid_max=4194304
kernel.threads-max=32768

net.netfilter.nf_conntrack_buckets = 262144
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_established = 900
EOF
  # nf_conntrack_buckets 无法在 CentOS7 中直接 sysctl，必须配置模块加载 options
  if [ "${SYSTEM_RELEASE}${SYSTEM_PACKAGE}" = 'centosyum' ]; then
    echo 262144 > /sys/module/nf_conntrack/parameters/hashsize
    result_msg "优化 nf_conntrack_buckets"
    sed -i '/net.netfilter.nf_conntrack_buckets/d' /etc/sysctl.d/k8s.conf
    cat > /etc/modprobe.d/buckets.conf << EOF
options nf_conntrack hashsize=262144
EOF
    result_msg "添加 buckets 开机加载"
  fi
  # 即刻加载优化的参数
  sysctl -p /etc/sysctl.d/k8s.conf > /dev/null
  result_msg '优化 kernel parameters'
}


# 基础设置
basic_system_configs() {
  basic_install_request_${SYSTEM_RELEASE}
  basic_set_repos_cri
  basic_set_repos_kubernetes
  basic_reset_repos_cache
  basic_optimization_system
  basic_load_ipvs_modules
  basic_optimization_kernel_parameters
}


# 配置 /etc/hosts
basic_etc_hosts() {
  local kube_conf=${script_dir}/config/kube.yaml
  local node_name node_ip node_length
  # 删除自定义内容
  sed -i '/^\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\} [^ ].*/d' /etc/hosts
  # 添加 master1 hosts 配置
  echo "${MASTER1_IP} ${MASTER1_NAME}" >> /etc/hosts
  result_msg "添加 hosts: ${MASTER1_IP}"
  # 添加 master hosts 配置
  node_length=$(yq -M '.nodes.master | length' ${kube_conf})
  for i in $(seq 0 $((node_length - 1)))
  do
    node_name=$(tmp_var=${i} yq -M '.nodes.master[env(tmp_var)].domain' ${kube_conf})
    node_ip=$(tmp_var=${i} yq -M '.nodes.master[env(tmp_var)].address' ${kube_conf})
    echo "${node_ip} ${node_name}" >> /etc/hosts
    result_msg "添加 hosts: ${node_ip}"
  done
  # 添加 work hosts 配置
  node_length=$(yq -M '.nodes.work | length' ${kube_conf})
  for i in $(seq 0 $((node_length - 1)))
  do
    node_name=$(tmp_var=${i} yq -M '.nodes.work[env(tmp_var)].domain' ${kube_conf})
    node_ip=$(tmp_var=${i} yq -M '.nodes.work[env(tmp_var)].address' ${kube_conf})
    echo "${node_ip} ${node_name}" >> /etc/hosts
    result_msg "添加 hosts: ${node_ip}"
  done
}

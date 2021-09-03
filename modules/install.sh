# 安装 k8s 所需应用

# install_docker：安装 docker（支持 centos 7，私有仓库必须 http）
#DOCKER_VERSION='19.03.9'
#PRIVATE_REPOSITORY='192.168.10.38'

# install_containerd：安装 containerd（支持 centos 7 和 8，私有仓库必须 http）
#PRIVATE_REPOSITORY='192.168.10.38'
#IMAGE_REPOSITORY='mings135'

# install_kubeadm：安装 k8s 部署工具和环境（支持 centos 7 和 8，私有仓库必须 http）
#K8S_CRI='containerd'
#K8S_VERSION='1.20.7'


install_docker() {
  # yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo &> /dev/null
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null
  result_msg "添加 docker-ce.repo" || exit 1

  sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
  result_msg "修改 repo 至国内源" || exit 1

  yum install -y docker-ce-${DOCKER_VERSION} docker-ce-cli-${DOCKER_VERSION} containerd.io &> /dev/null
  result_msg "安装 docker ${DOCKER_VERSION}" || exit 1

  mkdir -p /etc/docker
      
  cat > /etc/docker/daemon.json << EOF
{
  "data-root": "/var/lib/docker",
  "storage-driver": "overlay2",
  "insecure-registries": ["${PRIVATE_REPOSITORY}"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m" }
}
EOF

  systemctl enable --now docker &> /dev/null
  result_msg "启动 docker" || exit 1
}


install_containerd() {
  # yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo &> /dev/null
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null
  result_msg "添加 docker-ce.repo" || exit 1

  sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
  result_msg "修改 docker-ce.repo 国内连接" || exit 1

  yum install -y containerd.io &> /dev/null
  result_msg "安装 containerd.io" || exit 1

  mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml
  result_msg "生成 containerd 默认配置" || exit 1

  sed -i "/sandbox_image/s#k8s.gcr.io#${IMAGE_REPOSITORY}#" /etc/containerd/config.toml && \
  sed -i '/endpoint/a \        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor_ip_or_hostname"]\n          endpoint = ["http://harbor_ip_or_hostname"]' /etc/containerd/config.toml && \
  sed -i "/harbor_ip_or_hostname/s#harbor_ip_or_hostname#${PRIVATE_REPOSITORY}#" /etc/containerd/config.toml
  # sed -i '/registry-1.docker.io/s#"https://registry-1.docker.io"#"https://qc20rc43.mirror.aliyuncs.com", "https://registry-1.docker.io"#' /etc/containerd/config.toml
  result_msg "修改 containerd 仓库配置" || exit 1

  sed -i '/runc.options/a \            SystemdCgroup = true' /etc/containerd/config.toml
  result_msg "修改 containerd SystemdCgroup" || exit 1

  systemctl enable --now containerd &> /dev/null
  result_msg "启动 containerd" || exit 1
}


install_kubeadm() {
  sed -i 's/.*swap.*/#&/' /etc/fstab
  swapoff -a
  result_msg "close swap"
  ver=$(uname -r)
  [ $(echo "${ver:0:4} >= 4.0" | bc) -eq 1 ] && nf_conn='nf_conntrack' || nf_conn='nf_conntrack_ipv4'

  # 开机自加载模块
  cat > /etc/modules-load.d/ipvs.conf << EOF
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
ip_vs_nq
${nf_conn}
overlay
br_netfilter
EOF
  for i in `cat /etc/modules-load.d/ipvs.conf`
  do
    modinfo -F filename $i &>/dev/null && modprobe $i
    result_msg "加载模块 $i" || exit 1
  done

  # 设置内核参数，该参数需要在内核模块 options 中指定
  echo 262144 > /sys/module/nf_conntrack/parameters/hashsize
  cat > /etc/modprobe.d/ipvs.conf << EOF
options nf_conntrack hashsize=262144
EOF

  cat > /etc/sysctl.d/kubernetes.conf << EOF
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

net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_established = 900
EOF
  sysctl --system &> /dev/null
  result_msg '优化内核参数' || exit 1

  cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
  yum install -y kubeadm-${K8S_VERSION} kubelet-${K8S_VERSION} kubectl-${K8S_VERSION} &> /dev/null
  result_msg '安装 kubeadm kubelet kubectl' || exit 1

  if [ ${K8S_CRI} == 'containerd' ];then
    cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
    result_msg '配置 crictl' || exit 1
  fi

  systemctl enable --now kubelet &> /dev/null
  result_msg '启动 kubelet' || exit 1
}
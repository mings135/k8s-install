centos_kubeadm() {
  cat > /etc/yum.repos.d/k8s.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
  yum install -y kubeadm-${K8S_VERSION} kubelet-${K8S_VERSION} kubectl-${K8S_VERSION} &> /dev/null
  result_msg '安装 kubeadm kubelet kubectl' || return 1

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
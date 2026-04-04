# --- install cluster ---

# 显示所需 images
images_list() {
  kubeadm config --config ${KUBE_KUBEADM} images list
  result_msg "查看 images list"
}

# 拉取所需 images
images_pull() {
  kubeadm config --config ${KUBE_KUBEADM} images pull
  result_msg "拉取 images"
}

# 初始化集群
master1_init() {
  kubeadm init --config ${KUBE_KUBEADM} --upload-certs
  result_msg "创建 cluster"
  cluster_config_kubectl

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: temp-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: temp-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: temp-admin
  namespace: kube-system
EOF
}

# 生成加入集群的命令
create_join_command() {
  local expireTime="$(get_config ".join.expireTime")"
  local now="$(date '+%s')"
  expireTime=${expireTime:-0}
  if [[ "${now}" -le "${expireTime}" ]]; then
    return 0
  fi

  local expire="$(date -d "+2 hours" +%s)"
  local cmd="$(kubeadm token create --ttl 2h --print-join-command)"
  local key="$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | awk 'END{print}')"
  val1="${expire}" val2="${cmd}" val3="${key}" yq -i '
    .join.expireTime = strenv(val1) |
    .join.command = strenv(val2) |
    .join.certificateKey = strenv(val3)
  ' ${KUBE_FILE}
  result_msg "创建 join command"
}

# 加入集群
join_cluster() {
  local cmd="$(get_config ".join.command")"

  if [[ "${HOST_ROLE}" == "master" ]]; then
    local key="$(get_config ".join.certificateKey")"
    local mgr_cmd="${cmd} --control-plane --certificate-key ${key}"
    blue_font "${mgr_cmd}"
    ${mgr_cmd}
    result_msg "加入 cluster 成为 master"
    cluster_config_kubectl
  elif [[ "${HOST_ROLE}" == "work" ]]; then
    blue_font "${cmd}"
    ${cmd}
    result_msg "加入 cluster 成为 work"
  fi
}

# 同步更新 .kube/config, 并安装命令自动补全
cluster_config_kubectl() {
  mkdir -p $HOME/.kube \
    && /bin/cp ${KUBEADM_CONFIG}/admin.conf $HOME/.kube/config \
    && chmod 700 $HOME/.kube/config
  result_msg "配置 kubectl config"

  install_pkgs "bash-completion"
  mkdir -p /etc/bash_completion.d \
    && kubectl completion bash >/etc/bash_completion.d/kubectl
  result_msg "添加 completion bash"
}

# --- upgrade cluster ---

upgrade_cluster() {
  if [[ "${HOST_ROLE}" == "master1" ]]; then
    kubeadm upgrade plan v${kubernetesVersion}
    result_msg "升级 plan"
    kubeadm upgrade apply v${kubernetesVersion} -y
    result_msg "升级 ${HOST_NAME}(${HOST_ROLE})"
  else
    kubeadm upgrade node
    result_msg "升级 ${HOST_NAME}(${HOST_ROLE})"
  fi
}

drian_node() {
  kubectl drain ${HOST_NAME} --ignore-daemonsets --delete-emptydir-data
  result_msg "腾空 current node"
}

uncordon_node() {
  kubectl uncordon ${HOST_NAME}
  result_msg "解除 protect current node(uncordon)"

  kubectl wait --for=condition=Ready nodes/${HOST_NAME} --timeout=50s
  result_msg "等待 节点 Ready"
}

# 备份 etcd 数据库
backup_etcd() {
  local app="etcd"
  local name="${app}-$(date +"%Y%m%d").db"

  if [[ "${HOST_ROLE}" == "work" ]]; then
    return 0
  fi

  ETCDCTL_API=3 etcdctl snapshot save ${KUBE_BACKUP}/${name} \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=${KUBEADM_PKI}/etcd/ca.crt \
    --cert=${KUBEADM_PKI}/etcd/server.crt \
    --key=${KUBEADM_PKI}/etcd/server.key \
    && chmod 644 ${KUBE_BACKUP}/${name} \
    && chown ${script_own}:${script_own} ${KUBE_BACKUP}/${name} \
    && set_record ".backup.${app}" "${name}"
  result_msg "备份 ${app}"
}

# 创建 kubeconfig token, 有效期 6h
create_kubeconfig_token() {
  local expireTime="$(get_config ".kubeconfig.expireTime")"
  local now="$(date '+%s')"
  expireTime=${expireTime:-0}
  if [[ "${now}" -le "${expireTime}" ]]; then
    return 0
  fi

  local expire="$(date -d "+6 hours" +%s)"
  local token="$(kubectl create token temp-admin -n kube-system --duration=6h)"
  val1="${expire}" val2="${token}" yq -i '
    .kubeconfig.expireTime = strenv(val1) |
    .kubeconfig.token = strenv(val2)
  ' ${KUBE_FILE}
  result_msg "创建 kubeconfig token(temp-admin 6h)"
}

# 配置临时的 .kube/config
config_user_context() {
  local token=$(get_config ".kubeconfig.token")
  kubectl config set-cluster kubernetes --server=https://192.168.11.50:6443 --insecure-skip-tls-verify \
    && kubectl config set-credentials temp-admin --token="${token}" \
    && kubectl config set-context temp-admin@kubernetes --cluster=kubernetes --user=temp-admin \
    && kubectl config use-context temp-admin@kubernetes
  result_msg "配置 kubeconfig(temp-admin)"
}

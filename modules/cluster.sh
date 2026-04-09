# --- install cluster ---

# 显示所需 images
images_list() {
  kubeadm config --config ${KUBE_KUBEADM} images list
  result_msg "[Display] images list"
}

# 拉取所需 images
images_pull() {
  kubeadm config --config ${KUBE_KUBEADM} images pull
  result_msg "[Pull] images"
}

# 初始化集群
master1_init() {
  if [[ "${HOST_ROLE}" != "master1" ]]; then
    return 0
  fi

  kubeadm init --config ${KUBE_KUBEADM} --upload-certs
  result_msg "[Init] cluster"
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
  result_msg "[Create] temp-admin sa"
}

# 生成加入集群的命令
create_join_command() {
  local expireTime="$(get_config ".join.expireTime")"
  local now="$(date '+%s')"
  expireTime=${expireTime:-0}
  if [[ "${now}" -le "${expireTime}" ]] || [[ "${HOST_ROLE}" != "master1" ]]; then
    return 0
  fi

  local expire="$(date -d "+2 hours" +%s)"
  local cmd="$(kubeadm token create --ttl 2h --print-join-command)"
  local key="$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | awk 'END{print}')"
  val1="${expire}" val2="${cmd}" val3="${key}" yq -i '
    .join.expireTime = strenv(val1) |
    .join.command = strenv(val2) |
    .join.certificateKey = strenv(val3)
  ' ${KUBE_FILE} && sync
  result_msg "[Create] join command"
}

# 加入集群
join_cluster() {
  local cmd="$(get_config ".join.command")"

  if [[ "${HOST_ROLE}" == "master" ]]; then
    local key="$(get_config ".join.certificateKey")"
    local mgr_cmd="${cmd} --control-plane --certificate-key ${key}"
    ${mgr_cmd}
    result_msg "[Join] cluster as master"
    cluster_config_kubectl
  elif [[ "${HOST_ROLE}" == "work" ]]; then
    ${cmd}
    result_msg "[Join] cluster as work"

    # 该目录删除后, work 节点可能无法再次创建, 导致疯狂报错
    if [[ ! -d ${KUBEADM_MANIFESTS} ]]; then
      mkdir -p ${KUBEADM_MANIFESTS}
      result_msg "[Create] manifests dir"
    fi
  fi
}

# 同步更新 .kube/config, 并安装命令自动补全
cluster_config_kubectl() {
  mkdir -p $HOME/.kube \
    && /bin/cp ${KUBEADM_CONFIG}/admin.conf $HOME/.kube/config \
    && chmod 700 $HOME/.kube/config
  result_msg "[Copy] kubectl config"

  install_pkgs "bash-completion"
  mkdir -p /etc/bash_completion.d \
    && kubectl completion bash >/etc/bash_completion.d/kubectl
  result_msg "[Install] completion bash"
}

# --- upgrade cluster ---

upgrade_cluster() {
  if [[ "${HOST_ROLE}" == "master1" ]]; then
    kubeadm upgrade plan v${kubernetesVersion}
    result_msg "[Upgrade] plan"
    kubeadm upgrade apply v${kubernetesVersion} -y
    result_msg "[Upgrade] ${HOST_NAME}(${HOST_ROLE})"
  else
    kubeadm upgrade node
    result_msg "[Upgrade] ${HOST_NAME}(${HOST_ROLE})"
  fi
}

drian_node() {
  kubectl drain ${HOST_NAME} --ignore-daemonsets --delete-emptydir-data
  result_msg "[Drain] current node"
}

uncordon_node() {
  kubectl uncordon ${HOST_NAME}
  result_msg "[Uncordon] current node"

  kubectl wait --for=condition=Ready nodes/${HOST_NAME} --timeout=50s
  result_msg "[Wait] node Ready"
}

# 备份 etcd 数据库
backup_etcd() {
  local app="etcd"
  local name="${app}-$(date +"%Y%m%d-%H%M").db"

  local value=$(get_record ".backup.${app}")
  RES_LEVEL=1 && [[ "${value}" != "${name}" ]]
  result_msg "[Backup] ${app}, Max 1 backup/min"
  RES_LEVEL=0

  etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=${KUBEADM_PKI}/etcd/ca.crt \
    --cert=${KUBEADM_PKI}/etcd/server.crt \
    --key=${KUBEADM_PKI}/etcd/server.key \
    snapshot save ${KUBE_BACKUP}/${name} \
    && chmod 644 ${KUBE_BACKUP}/${name} \
    && chown ${script_own}:${script_own} ${KUBE_BACKUP}/${name} \
    && set_record ".backup.${app}" "${name}"
  result_msg "[Backup] ${app}"
}

# 创建 kubeconfig token, 有效期 12h
create_kubeconfig_token() {
  local expireTime="$(get_config ".kubeconfig.expireTime")"
  local now="$(date '+%s')"
  expireTime=${expireTime:-0}
  if [[ "${now}" -le "${expireTime}" ]] || [[ "${HOST_ROLE}" != "master1" ]]; then
    return 0
  fi

  local expire="$(date -d "+12 hours" +%s)"
  local token="$(kubectl create token temp-admin -n kube-system --duration=12h)"
  val1="${expire}" val2="${token}" yq -i '
    .kubeconfig.expireTime = strenv(val1) |
    .kubeconfig.token = strenv(val2)
  ' ${KUBE_FILE} && sync
  result_msg "[Create] kubeconfig token(temp-admin 12h)"
}

# 配置临时的 .kube/config
config_user_context() {
  local token=$(get_config ".kubeconfig.token")

  if [[ "${HOST_ROLE}" != "work" ]] || [[ -z "${token}" ]]; then
    return 0
  fi

  kubectl config set-cluster ${clusterName} --server=https://192.168.11.50:6443 --insecure-skip-tls-verify \
    && kubectl config set-credentials temp-admin --token="${token}" \
    && kubectl config set-context temp-admin@${clusterName} --cluster=${clusterName} --user=temp-admin \
    && kubectl config use-context temp-admin@${clusterName}
  result_msg "[Config] kubeconfig(temp-admin)"
}

cluster_delete_works() {
  if [[ "${HOST_ROLE}" != "master1" ]] || [[ -z "${DELETE_WORKS}" ]]; then
    return 0
  fi

  local domain addr
  for i in ${DELETE_WORKS}; do
    addr="${i#*=}"
    domain="${i%=*}"
    if kubectl get node ${domain} &>/dev/null; then
      # Drain and delete node
      kubectl drain ${domain} --ignore-daemonsets --delete-emptydir-data
      result_msg "[Drain] node ${domain}"
      kubectl delete node ${domain}
      result_msg "[Delete] node ${domain}"
    fi
    # Delete config with address
    val1="${addr}" yq -i 'del(.nodes.work[] | select(.address == strenv(val1))' ${KUBE_FILE}
    result_msg "[Delete] config with ${addr}"
  done
  sync
}

delete_nodes() {
  cluster_delete_works
}

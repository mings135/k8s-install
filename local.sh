#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "Please use bash $0 to run the script!"
  exit 1
fi

set -e
script_type="local"
script_dir=$(dirname "$(readlink -f "$0")")

source ${script_dir}/modules/const.sh
source ${script_dir}/modules/vars.sh
source ${script_dir}/modules/check.sh

source ${script_dir}/modules/sys.sh
source ${script_dir}/modules/cri.sh
source ${script_dir}/modules/k8s.sh

source ${script_dir}/modules/cluster.sh
set +e

# 安装和配置所需的基础
local_base_install() {

  init_etc_hosts

  local value="$(get_record ".sys.init")"
  if [[ "${value}" != "true" ]]; then
    init_system
    set_record ".sys.init" "true"
  fi

  value="$(get_record ".cri.install")"
  if [[ "${value}" != "true" ]]; then
    install_cri
    set_record ".cri.install" "true"

    local ver=$(containerd --v | awk '{print $3}')
    set_record ".cri.version" "${ver#v}"
  fi

  value="$(get_record ".k8s.install")"
  if [[ "${value}" != "true" ]]; then
    install_kubernetes

    val1='true' val2="${kubernetesVersion}" yq -i '
      .k8s.install = strenv(val1) |
      .k8s.kubeadmVersion = strenv(val2) |
      .k8s.kubeletVersion = strenv(val2)
    ' ${KUBE_RECORD}
  fi
}

# 拉取所需 images
local_images_pull() {

  local value="$(get_record ".cluster.imagesPull")"
  if [[ "${value}" != "true" ]]; then
    images_pull
    set_record ".cluster.imagesPull" "true"
  fi
}

# 初始化集群
local_init_cluster() {

  local value="$(get_record ".cluster.join")"
  if [[ "${value}" != "true" ]]; then
    master1_init

    val1='true' val2="${HOST_ROLE}" val3="${kubernetesVersion}" yq -i '
      .cluster.join = strenv(val1) |
      .cluster.role = strenv(val2) |
      .cluster.version = strenv(val3)
    ' ${KUBE_RECORD}
  fi

  create_join_command
}

# 加入集群
local_join_cluster() {

  local value="$(get_record ".cluster.join")"
  if [[ "${value}" != "true" ]]; then
    join_cluster

    val1='true' val2="${HOST_ROLE}" val3="${kubernetesVersion}" yq -i '
      .cluster.join = strenv(val1) |
      .cluster.role = strenv(val2) |
      .cluster.version = strenv(val3)
    ' ${KUBE_RECORD}
  fi
}

# 部署 flannel
local_deploy_flannel() {

  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
}

# 更新容器运行时
local_upgrade_cri() {

  upgrade_cri_check

  local value="$(get_record ".cri.version")"
  if [[ "${criVersion}" == "latest" ]] || version_gt "${criVersion}" "${value}"; then
    drian_node
    stop_kubelet
    upgrade_cri
    start_kubelet
    uncordon_node
    local ver=$(containerd --v | awk '{print $3}')
    set_record ".cri.version" "${ver#v}"
  fi
}

# 更新集群版本 up kubeadm --> up cluster --> drian --> up kubelet --> uncordon
local_upgrade_cluster() {

  upgrade_cluster_check

  local value="$(get_record ".k8s.kubeadmVersion")"
  if version_gt "${kubernetesVersion}" "${value}"; then
    upgrade_kubeadm
    upgrade_cluster
    set_record ".k8s.kubeadmVersion" "${kubernetesVersion}"
  fi

  value="$(get_record ".k8s.kubeletVersion")"
  if version_gt "${kubernetesVersion}" "${value}"; then
    drian_node
    upgrade_kubelet
    uncordon_node

    val1="${kubernetesVersion}" yq -i '
      .k8s.kubeletVersion = strenv(val1) |
      .cluster.version = strenv(val1)
    ' ${KUBE_RECORD}
  fi
}

# 清理集群节点
local_clean_node() {
  # 集群清理
  if command -v kubeadm &>/dev/null; then
    kubeadm reset -f
  fi
  if command -v ipvsadm &>/dev/null; then
    ipvsadm --clear
  fi

  # 删除 k8s 组件
  unhold_pkgs 'kubeadm kubelet kubectl containerd'
  remove_pkgs 'kubeadm kubelet kubectl cri-tools kubernetes-cni containerd.io' '--purge'

  # 删除相关目录、文件
  rm -rf /etc/cni/net.d /root/.kube/config
  result_msg "删除 /etc/cni/net.d"

  find ${script_dir} -mindepth 1 -maxdepth 1 | xargs rm -rf
  result_msg "删除 ${script_dir}/*"
}

main() {
  case $1 in
    "vars") display_vars ;;
    "imglist") images_list ;;
    "hosts") init_etc_hosts ;;

    "install") local_base_install ;;
    "imgpull") local_images_pull ;;
    "init") local_init_cluster ;;
    "join") local_join_cluster ;;
    "flannel") local_deploy_flannel ;;

    "cri") local_upgrade_cri ;;
    "token") create_kubeconfig_token ;;
    "context") config_user_context ;;

    "upgrade") local_upgrade_cluster ;;

    "backup")
      backup_cri
      backup_kubernetes
      backup_etcd
      ;;

    "clean") local_clean_node ;;
    *)
      printf "Usage: bash $0 [ ? ] \n"
      printf "%-16s %-s\n" 'vars' 'display vars'
      printf "%-16s %-s\n" 'imglist' 'display images'
      printf "%-16s %-s\n" 'hosts' 'update hosts'

      printf "%-16s %-s\n" 'install' 'update hosts, system init, install pkgs'
      printf "%-16s %-s\n" 'imgpull' 'pull images'
      printf "%-16s %-s\n" 'init' 'init cluster, create join command'
      printf "%-16s %-s\n" 'join' 'join cluster'
      printf "%-16s %-s\n" 'flannel' 'deploy flannel'

      printf "%-16s %-s\n" 'cri' 'upgrade cri'
      printf "%-16s %-s\n" 'token' 'create kubeconfig.token'
      printf "%-16s %-s\n" 'context' 'config kubeconfig context'

      printf "%-16s %-s\n" 'upgrade' 'upgrade cluster'

      printf "%-16s %-s\n" 'backup' 'backup containerd kubernetes and etcd'

      printf "%-16s %-s\n" 'clean' 'clean cluster node'
      exit 1
      ;;
  esac
}

if [ $# -eq 0 ]; then
  main $1
fi

while [ $# -gt 0 ]; do
  main $1
  shift
done

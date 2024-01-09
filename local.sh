#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "请使用 bash $0 运行脚本!"
  exit 1
fi

set -e
script_dir=$(dirname $(readlink -f $0))

source ${script_dir}/modules/result.sh
source ${script_dir}/modules/variables.sh

source ${script_dir}/modules/basic.sh
source ${script_dir}/modules/cri.sh
source ${script_dir}/modules/k8s.sh

source ${script_dir}/modules/certs.sh
source ${script_dir}/modules/cluster.sh
set +e


# 检查并创建 record.txt
local_check_record() {
  if [ ! -e ${script_dir}/config/record.txt ]; then
    mkdir -p ${script_dir}/config \
      && touch ${script_dir}/config/record.txt
    result_msg "创建 record.txt"
  fi
}


# 安装和配置所需的基础
local_install_basic() {
  basic_etc_hosts
  if ! grep -Eqi '^basic_system_configs$' ${script_dir}/config/record.txt; then
    basic_system_configs
    echo "basic_system_configs" >> ${script_dir}/config/record.txt
  fi
  if ! grep -Eqi '^cri_install$' ${script_dir}/config/record.txt; then
    cri_install
    echo "cri_install" >> ${script_dir}/config/record.txt
  fi
  if ! grep -Eqi '^kubernetes_install$' ${script_dir}/config/record.txt; then
    kubernetes_install
    echo "kubernetes_install" >> ${script_dir}/config/record.txt
  fi
}


# 签发证书
local_issue_certs() {
  set -e
  if ! grep -Eqi '^certs_all_exclude_kubelet$' ${script_dir}/config/record.txt; then
    result_blue_font "签发证书: ${HOST_IP}"
    mkdir -p ${KUBEADM_PKI} && rm -rf ${KUBEADM_PKI}
    /usr/bin/cp -a ${script_dir}/pki ${KUBEADM_PKI}
    certs_etcd
    certs_apiserver
    certs_front-proxy
    certs_admin_conf
    certs_controller-manager_conf
    certs_scheduler_conf
    echo "certs_all_exclude_kubelet" >> ${script_dir}/config/record.txt
  fi
  set +e
}


# 拉取所需 images
local_images_pull() {
  if ! grep -Eqi '^cluster_images_pull$' ${script_dir}/config/record.txt; then
    cluster_images_pull
    echo "cluster_images_pull" >> ${script_dir}/config/record.txt
  fi
}


# 初始化集群
local_init_cluster() {
  if ! grep -Eqi '^cluster_join_cluster$' ${script_dir}/config/record.txt; then
    cluster_master1_init
    echo "cluster_join_cluster" >> ${script_dir}/config/record.txt
  fi
  cluster_generate_join_command
}


# 加入集群
local_join_cluster() {
  if ! grep -Eqi '^cluster_join_cluster$' ${script_dir}/config/record.txt; then
    cluster_join_cluster
    echo "cluster_join_cluster" >> ${script_dir}/config/record.txt
  fi
}


# 签发 kubelet 证书
local_kubelet_certs() {
  set -e
  if ! grep -Eqi '^certs_kubelet_pem$' ${script_dir}/config/record.txt; then
    result_blue_font "签发 kubelet 证书: ${HOST_IP}"
    certs_kubelet_pem
    sleep 1
    systemctl restart kubelet
    echo "certs_kubelet_pem" >> ${script_dir}/config/record.txt
  fi
  set +e
}


# 部署 flannel
local_deploy_flannel() {
  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
}


# 更新集群版本
local_upgrade_version() {
  if ! grep -Eqi "cluster_upgrade_version_kubeadm-${upgradeVersion}" ${script_dir}/config/record.txt; then
    basic_set_repos_kubernetes
    update_mirror_source_cache
    cluster_upgrade_version_kubeadm
    echo "cluster_upgrade_version_kubeadm-${upgradeVersion}" >> ${script_dir}/config/record.txt
  fi

  if ! grep -Eqi "cluster_upgrade_version_kubelet-${upgradeVersion}" ${script_dir}/config/record.txt; then
    cluster_upgrade_version_kubelet
    echo "cluster_upgrade_version_kubelet-${upgradeVersion}" >> ${script_dir}/config/record.txt
  fi
}


# 更新容器运行时版本
local_cri_upgrade_version() {
  if ! grep -Eqi "cri_upgrade_version-${criVersion}" ${script_dir}/config/record.txt; then
    basic_set_repos_cri
    update_mirror_source_cache
    cri_upgrade_version
    echo "cri_upgrade_version-${criVersion}" >> ${script_dir}/config/record.txt
  fi
}


# 更新容器运行时版本时, 优化 latest, 支持每次使用
local_cri_upgrade_optimize_latest() {
  if grep -Eqi "cri_upgrade_version-latest" ${script_dir}/config/record.txt; then
    sed -i '/cri_upgrade_version-latest/d' ${script_dir}/config/record.txt
  fi
}


# 删除集群
local_clean_cluster() {
  # 集群清理
  if which kubeadm &> /dev/null; then
    kubeadm reset -f
  fi
  if which ipvsadm &> /dev/null; then
    ipvsadm --clear
  fi
  # debian 中, 如果被锁, 执行解锁
  if [ ${SYSTEM_RELEASE} = 'debian' ]; then 
    local mark_apps=''
    for i in kubeadm kubelet kubectl
    do
      if apt-mark showhold | grep -Eqi "$i"; then
        mark_apps="${mark_apps} $i"
      fi
    done
    if [ "${mark_apps}" ]; then
      apt-mark unhold ${mark_apps} > /dev/null
      result_msg "解锁 ${mark_apps}"
    fi
  fi
  # 移除 kubeadm kubelet kubectl cri-tools
  local remove_apps=''
  for i in kubeadm kubelet kubectl cri-tools
  do
    if which $i &> /dev/null; then
      remove_apps="${remove_apps} $i"
    fi
  done
  if [ "$remove_apps" ]; then
    remove_apps "${remove_apps}"
  fi
  # 移除 containerd.io
  if which containerd &> /dev/null; then
    remove_apps 'containerd.io'
  fi
  # 删除相关目录、文件
  rm -rf /etc/cni/net.d /root/.kube/config
  result_msg "移除 目录和文件"
}


main() {
  local_check_record
  variables_settings

  case $1 in
    "install") local_install_basic;;
    "imglist") cluster_images_list;;
    "imgpull") local_images_pull;;
    "initcluster") local_init_cluster;;
    "joincluster") local_join_cluster;;
    "certs") local_issue_certs;;
    "kubelet") local_kubelet_certs;;
    "flannel") local_deploy_flannel;;
    "upgrade") local_upgrade_version;;
    "criupgrade") local_cri_upgrade_version;;
    "criupgradeopt") local_cri_upgrade_optimize_latest;;
    "tmpkubeconfig") cluster_generate_kubeconfig_tmp;;
    "tmpkubectl") cluster_config_kubectl_tmp;;
    "backup") cluster_backup_etcd;;
    "restore") cluster_restore_etcd;;
    "startetcd") cluster_start_etcd;;
    "clean") local_clean_cluster;;
    "test") variables_display_test;;
    *)
    printf "Usage: bash $0 [ ? ] \n"
    printf "%-16s %-s\n" 'install' '更新 hosts 文件, 优化系统, 安装 cri 和 kubeadm 等'
    printf "%-16s %-s\n" 'imglist' '查看 images'
    printf "%-16s %-s\n" 'imgpull' '拉取 images'
    printf "%-16s %-s\n" 'initcluster' '初始化 k8s 集群, 同时生成 join 信息'
    printf "%-16s %-s\n" 'joincluster' '根据自身 Role 信息加入集群'
    printf "%-16s %-s\n" 'certs' '签发 k8s 证书, 此操作会清空 ${KUBEADM_PKI}!!!'
    printf "%-16s %-s\n" 'kubelet' '签发 kubelet 证书，此操作会覆盖原有证书!!!'
    exit 1
    ;;
  esac
}


if [ $# -eq 0 ]; then
  main $1
fi

while [ $# -gt 0 ]
do
  main $1
  shift
done

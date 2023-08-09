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

#!/usr/bin/env bash

script_dir=$(dirname $(readlink -f $0)) || exit 1

source ${script_dir}/modules/result.sh || exit 1
source ${script_dir}/config/kube.conf
source ${script_dir}/modules/check.sh
source ${script_dir}/modules/base.sh


local_init() {
  check_record_exist
  source ${script_dir}/modules/init.sh

  if ! grep -Eqi 'init_system' ${script_dir}/config/record.txt; then
    init_system
    echo "init_system" >> ${script_dir}/config/record.txt
  fi
}


local_cri() {
  check_record_exist
  source ${script_dir}/modules/cri.sh

  if ! grep -Eqi 'install_cri' ${script_dir}/config/record.txt && \
  grep -Eqi 'init_system' ${script_dir}/config/record.txt; then
    install_cri
    echo "install_cri" >> ${script_dir}/config/record.txt
  fi 
}


local_k8s() {
  check_record_exist
  source ${script_dir}/modules/k8s.sh

  if ! grep -Eqi 'install_k8s' ${script_dir}/config/record.txt && \
  grep -Eqi 'init_system' ${script_dir}/config/record.txt; then
    install_k8s
    echo "install_k8s" >> ${script_dir}/config/record.txt
  fi
}


local_hosts() {
  source ${script_dir}/modules/cluster.sh
  cluster_hosts
}


local_imglist() {
  source ${script_dir}/modules/cluster.sh
  images_list
}


local_imgpull() {
  check_record_exist
  source ${script_dir}/modules/cluster.sh

  if ! grep -Eqi 'images_pull' ${script_dir}/config/record.txt; then
    images_pull
    echo "images_pull" >> ${script_dir}/config/record.txt
  fi
}


local_initcluster() {
  check_record_exist
  source ${script_dir}/modules/cluster.sh

  if ! grep -Eqi 'cluster_init_or_join_m' ${script_dir}/config/record.txt; then
    cluster_init
    echo "cluster_init_or_join_m" >> ${script_dir}/config/record.txt
  fi
}


local_joincmd() {
  check_record_exist
  source ${script_dir}/modules/cluster.sh

  if grep -Eqi 'cluster_init_or_join_m' ${script_dir}/config/record.txt; then
    kubectl_config
    cluster_joincmd
  fi
}


local_joincluster() {
  check_record_exist
  source ${script_dir}/modules/cluster.sh

  if ${IS_MASTER}; then
    if ! grep -Eqi 'cluster_init_or_join_m' ${script_dir}/config/record.txt; then
      cluster_join
      echo "cluster_init_or_join_m" >> ${script_dir}/config/record.txt
    fi
  else
    if ! grep -Eqi 'cluster_init_or_join_w' ${script_dir}/config/record.txt; then
      cluster_join
      echo "cluster_init_or_join_w" >> ${script_dir}/config/record.txt
    fi
  fi
}


local_ca() {
  source ${script_dir}/modules/ca.sh

  if [ -d ${script_dir}/pki ]; then
    blue_font '已创建过 CA，跳过（如需更新 CA，手动删除 pki 目录）'
  else
    set -e
    mkdir ${script_dir}/pki
    cd ${script_dir}/pki
    ca_crt
    set +e
  fi
}


local_certs() {
  check_record_exist
  source ${script_dir}/modules/certs.sh

  if ! grep -Eqi 'k8s_certs' ${script_dir}/config/record.txt && \
  ${IS_MASTER}; then
    set -e
    mkdir -p ${K8S_PKI}
    rm -rf ${K8S_PKI}
    /usr/bin/cp -a ${script_dir}/pki ${K8S_PKI}
    etcd_crt
    apiserver_crt
    front_crt
    admin_conf
    manager_conf
    scheduler_conf
    set +e
    echo "k8s_certs" >> ${script_dir}/config/record.txt
  fi
}


local_kubelet() {
  check_record_exist
  source ${script_dir}/modules/certs.sh

  if ! grep -Eqi 'kubelet_cert' ${script_dir}/config/record.txt; then
    set -e
    /usr/bin/cp -a ${script_dir}/pki/ca.{crt,key} ${KUBELET_PKI}
    kubelet_conf_crt
    rm -f ${KUBELET_PKI}/ca.{crt,key}
    systemctl restart kubelet
    set +e
    echo "kubelet_cert" >> ${script_dir}/config/record.txt
  fi
}


# 删除 scp 过来不必要的文件
local_needless() {
  local needless_fd='remote.sh'
  for i in ${needless_fd}
  do
    if [ -e ${i} ]; then
      rm -rf ${script_dir}/${i}
      result_msg "删除 ${i}" || exit 1
    fi
  done
}


# 创建记录
local_record() {
  if [ ! -f ${script_dir}/config/record.txt ]; then
    touch ${script_dir}/config/record.txt
    result_msg "创建 record.txt" || exit 1
  fi
}


# 删除记录
local_delrecord() {
  if [ -f ${script_dir}/config/record.txt ]; then
    rm -f ${script_dir}/config/record.txt
    result_msg "删除 record.txt" || exit 1
  fi
}


# 删除非 master 节点上的 pki 目录
local_delpki() {
  if ! ${IS_MASTER} && [ -d ${script_dir}/pki ]; then
    rm -rf ${script_dir}/pki
    result_msg "删除 pki dir(not master)" || exit 1
  fi
}


main() {
  base_info

  case $1 in
    "record") local_record;;
    "delrecord") local_delrecord;;
    "needless") local_needless;; 
    "hosts") local_hosts;;
    "init") local_init;;
    "cri") local_cri;;
    "k8s") local_k8s;;
    "all")
      local_hosts
      local_init
      local_cri
      local_k8s
      ;;
    "imglist") local_imglist;;
    "imgpull") local_imgpull;;
    "initcluster") local_initcluster;;
    "joincmd") local_joincmd;;
    "joincluster") local_joincluster;;
    "ca") local_ca;;
    "certs") local_certs;;
    "kubelet") local_kubelet;;
    "delpki") local_delpki;;
    *)
    printf "Usage: bash $0 [ ? ] \n"
    printf "%-16s %-s\n" 'record' '创建 config/record.txt；用于记录步骤'
    printf "%-16s %-s\n" 'delrecord' '删除 config/record.txt；被记录的步骤不能重复执行'
    printf "%-16s %-s\n" 'needless' '删除本地不需要的文件'
    printf "%-16s %-s\n" 'hosts' '更新 config/nodes.conf；然后更新 /etc/hosts'
    printf "%-16s %-s\n" 'init' '初始化、优化系统'
    printf "%-16s %-s\n" 'cri' '安装容器运行时'
    printf "%-16s %-s\n" 'k8s' '安装 kubeadm kubelet kubectl'
    printf "%-16s %-s\n" 'all' '顺序执行：hosts -> init -> cri --> k8s'
    printf "%-16s %-s\n" 'imglist' '查看 kubeadm init images'
    printf "%-16s %-s\n" 'imgpull' '拉取 kubeadm init images'
    printf "%-16s %-s\n" 'initcluster' 'm1 node 上 kubeadm init cluster'
    printf "%-16s %-s\n" 'joincmd' '生成 kubeadm-init.log 的节点上获取 join 命令，并写入 config/join.conf'
    printf "%-16s %-s\n" 'joincluster' 'join 命令生效期间，使用 kubeadm join cluster'
    printf "%-16s %-s\n" 'ca' '创建 ca 证书（pki 目录，不会覆盖）'
    printf "%-16s %-s\n" 'certs' "如果是 master，签发 k8s 证书，此操作会清空 ${K8S_PKI}！"
    printf "%-16s %-s\n" 'kubelet' '签发 kubelet 证书，此操作会覆盖原有证书！'
    printf "%-16s %-s\n" 'delpki' '如果非 master，删除 pki 目录，集群安装完成后可以删除'
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

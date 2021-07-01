#!/usr/bin/env bash

script_dir=$(dirname $(readlink -f $0))

source ${script_dir}/config/kube.conf
source ${script_dir}/script/calculation.sh
source ${script_dir}/modules/result.sh
source ${script_dir}/script/ca.sh


# 运维节点：创建 3 张 CA 证书，请谨慎操作，以免覆盖需要的 ca（如需自定义证书，必须最先执行）
create_ca_certs() {
  [ -d ${script_dir}/pki ] || mkdir ${script_dir}/pki
  cd ${script_dir}/pki
  ca_crt
}


# 所有节点：分发项目文件
distribute_project_files() {
  for i in "${ALL_NODES[@]}"
  do
    ssh root@${i} test -f ${INSTALL_SCRIPT}/config/record.txt
    if [ $? -ne 0 ];then
      #  分发目录文件
      ssh root@${i} rm -rf ${INSTALL_SCRIPT}
      scp -r ${script_dir} root@${i}:${INSTALL_SCRIPT} || exit 1
      # 判断是否要删除 pki
      ssh root@${i} sh ${INSTALL_SCRIPT}/local.sh scp_check || exit 1
      # 记录
      ssh root@${i} touch ${INSTALL_SCRIPT}/config/record.txt
    fi
  done
}


# 所有节点：创建关于该节点的配置文件
make_config_files() {
  for i in "${ALL_NODES[@]}"
  do
    ssh root@${i} sh ${INSTALL_SCRIPT}/local.sh make_config || exit 1
  done
}


# k8s 节点：安装、配置、初始化所有相关软件和系统
install_initial_k8s() {
  python3 ${script_dir}/modules/concurrent_cmd.py "sh ${INSTALL_SCRIPT}/local.sh initial_node" ${ALL_NODES[*]}
#  for i in "${ALL_NODES[@]}"
#  do
#    ssh root@${i} sh ${INSTALL_SCRIPT}/local.sh initial_node || exit 1
#  done
}


# master 节点：签发 k8s 集群证书
k8s_issue_certs() {
  for i in "${MASTER_NODES[@]}"
  do
    # 各个节点签发证书
    ssh root@${i} sh ${INSTALL_SCRIPT}/local.sh issue_certs || exit 1
  done
}


# k8s 节点：签发 kubelet 证书
kubelet_issue_certs() {
  for i in "${ALL_NODES[@]}"
  do
    scp ${script_dir}/pki/ca.{crt,key} root@${i}:${KUBELET_PKI} || exit 1
    # 签发证书
    ssh root@${i} sh ${INSTALL_SCRIPT}/local.sh issue_kubelet || {
      ssh root@${i} rm -f ${KUBELET_PKI}/ca.{crt,key}
      exit 1
    }
    ssh root@${i} rm -f ${KUBELET_PKI}/ca.{crt,key}
  done
}


# 更新所有节点 kube.conf，然后根据 kube.conf 更新 /etc/hosts
update_etc_hosts() {
  for i in "${ALL_NODES[@]}"
  do
    scp ${script_dir}/config/kube.conf root@${i}:${INSTALL_SCRIPT}/config || exit 1
    ssh root@${i} sh ${INSTALL_SCRIPT}/local.sh update_hosts || exit 1
  done
}


# 删除安装记录
delete_record() {
  for i in "${ALL_NODES[@]}"
  do
    ssh root@${i} test -f ${INSTALL_SCRIPT}/config/record.txt
    if [ $? -eq 0 ];then
      ssh root@${i} rm -f ${INSTALL_SCRIPT}/config/record.txt
    fi
  done
}


main() {
  case $1 in
    "ca" ) create_ca_certs;;
    "distribute" ) distribute_project_files;;
    "make" ) make_config_files;;
    "initial" ) install_initial_k8s;;
    "certs" ) k8s_issue_certs;;
    "kubelet" ) kubelet_issue_certs;;
    "update_hosts" ) update_etc_hosts;;
    "delete_record" ) delete_record;;
    "all" )
      distribute_project_files
      make_config_files
      install_initial_k8s
      ;;
    * )
    printf "Usage: sh $0 [ ? ] \n"
    printf "%-16s %-s\n" 'ca' '在本地创建 CA 证书（重复执行会覆盖！）'
    printf "%-16s %-s\n" 'distribute' '分发项目（cluster 目录）到各个节点'
    printf "%-16s %-s\n" 'make' '各个节点自动创建配置文件'
    printf "%-16s %-s\n" 'initial' '各个节点初始化、安装、配置 k8s 相关应用'
    printf "%-16s %-s\n" 'certs' 'master 节点签发相关证书，此操作会清空 /etc/kubernetes/pki 目录！'
    printf "%-16s %-s\n" 'kubelet' '所有节点签发 kubelet 相关证书，此操作会覆盖原有证书！'
    printf "%-16s %-s\n" 'update_hosts' '更新所有节点 kube.conf，然后根据 kube.conf 更新 /etc/hosts'
    printf "%-16s %-s\n" 'delete_record' '删除所有节点的操作记录，默认：有相关操作记录不会重复执行'
    printf "%-16s %-s\n" 'all' 'distribute->make->initial'
    exit 1
    ;;
  esac
}


main $1
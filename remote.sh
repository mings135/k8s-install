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


# 免密登录节点
remote_free_login() {
  # 密码为空时，继续手动输入
  while [ ! ${nodePassword} ]
  do
    result_blue_font "请输入所有节点的统一密码 (root):"
    read -s nodePassword
  done

  # 创建 ssh 密钥
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
  fi

  # copy public key 到各个节点
  for i in ${NODES_ALL}
  do
    sshpass -p "${nodePassword}" ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub root@${i}
  done
}


# 前置操作, 安装 rsync
remote_front_operator() {
  for i in ${NODES_ALL}
  do
    scp -r ${script_dir}/front.sh root@${i}:/tmp/front.sh
  done
  python3 ${script_dir}/concurrent.py "bash /tmp/front.sh" ${NODES_ALL}
}


# 安装和配置所需的基础
remote_install_basic() {
  remote_rsync_script
  python3 ${script_dir}/concurrent.py "bash ${remoteScriptDir}/local.sh install" ${NODES_ALL}
}


# 签发 CA 证书(创建 pki 目录)
remote_issue_ca() {
  source ${script_dir}/modules/certs.sh

  if [ -d ${script_dir}/pki ]; then
    result_blue_font "已创建过 CA, 如需更换 CA, 请先手动删除 ${script_dir}/pki 目录!!!"
  else
    mkdir -p ${script_dir}/pki
    certs_ca_remote
  fi
}


# 签发证书
remote_issue_certs() {
  local rsync_exclude='--include=/pki/ --include=/pki/** --exclude=*'
  remote_rsync_update "同步 CA 证书" "${NODES_MASTER1_MASTER}" "${rsync_exclude}"
  sleep 1
  for i in ${NODES_MASTER1_MASTER}
  do
    ssh root@${i} bash ${remoteScriptDir}/local.sh certs
  done
}


# 查看所需 images
remote_images_list() {
  ssh root@${MASTER1_IP} bash ${remoteScriptDir}/local.sh imglist
}


# 拉取所需 images
remote_images_pull() {
  python3 ${script_dir}/concurrent.py "bash ${remoteScriptDir}/local.sh imgpull" ${NODES_MASTER1_MASTER}
}


# 安装集群
remote_install_cluster() {
  ssh root@${MASTER1_IP} bash ${remoteScriptDir}/local.sh initcluster
  sleep 1
  remote_rsync_join
  sleep 1
  for i in ${NODES_NOT_MASTER1}
  do
    ssh root@${i} bash ${remoteScriptDir}/local.sh joincluster
  done
}


# 签发 kubelet 证书
remote_kubelet_certs() {
  remote_rsync_kubelet_ca
  for i in ${NODES_ALL}
  do
    ssh root@${i} bash ${remoteScriptDir}/local.sh kubelet
    ssh root@${i} rm -f ${KUBELET_PKI}/ca.crt
    ssh root@${i} rm -f ${KUBELET_PKI}/ca.key
  done
}


# 部署 flannel
remote_deploy_flannel() {
  sleep 3
  ssh root@${MASTER1_IP} bash ${remoteScriptDir}/local.sh flannel
}


# 更新集群版本
remote_upgrade_version() {
  remote_rsync_script
  
  ssh root@${MASTER1_IP} bash ${remoteScriptDir}/local.sh upgrade

  for i in ${NODES_MASTER}
  do
    ssh root@${i} bash ${remoteScriptDir}/local.sh upgrade
  done

  ssh root@${MASTER1_IP} bash ${remoteScriptDir}/local.sh tmpkubeconfig
  remote_rsync_kubeconfig_tmp
  for i in ${NODES_WORK}
  do
    ssh root@${i} bash ${remoteScriptDir}/local.sh tmpkubectl upgrade
  done
}


# 备份 etcd 快照
remote_backup_etcd() {
  remote_rsync_script

  ssh root@${MASTER1_IP} bash ${remoteScriptDir}/local.sh backup
}


# 恢复 etcd
remote_restore_etcd() {
  remote_rsync_script

  ssh root@${MASTER1_IP} bash ${remoteScriptDir}/local.sh restore
  
  remote_rsync_etcd_snap
  for i in ${NODES_MASTER}
  do
    ssh root@${i} bash ${remoteScriptDir}/local.sh restore
  done

  python3 ${script_dir}/concurrent.py "bash ${remoteScriptDir}/local.sh startetcd" ${NODES_MASTER1_MASTER}
}


# 删除整个集群
remote_clean_cluster() {
  remote_rsync_script
  for i in ${NODES_ALL}
  do
    if ssh root@${i} test -e ${remoteScriptDir}/local.sh; then
      result_blue_font "清理节点: ${i}"
      ssh root@${i} bash ${remoteScriptDir}/local.sh clean
      ssh root@${i} rm -rf ${remoteScriptDir}
    fi
  done
}
###

# 同步脚本文件和配置文件
remote_rsync_script() {
  local rsync_exclude='--include=/modules/ --include=/modules/* --include=/config/ --include=/config/kube.yaml --include=/local.sh --exclude=*'
  remote_rsync_update "同步脚本" "${NODES_ALL}" "${rsync_exclude}"
}


# 同步 master1 上的 cluster join 信息到非 master1 节点
remote_rsync_join() {
  local rsync_exclude='--include=/config/ --include=/config/join.sh --exclude=*'
  remote_rsync_passive_update "被同步 join.sh" "${MASTER1_IP}" "${rsync_exclude}"
  remote_rsync_update "同步 join.sh" "${NODES_NOT_MASTER1}" "${rsync_exclude}"
}


# 同步 master1 上的 tmp-admin.conf 到 work 节点
remote_rsync_kubeconfig_tmp() {
  local rsync_exclude='--include=/config/ --include=/config/tmp-admin.conf --exclude=*'
  remote_rsync_passive_update "被同步 tmp-admin.conf" "${MASTER1_IP}" "${rsync_exclude}"
  remote_rsync_update "同步 tmp-admin.conf" "${NODES_WORK}" "${rsync_exclude}"
}


# 同步 master1 上的 etcd-snap.db 到其余 master 节点
remote_rsync_etcd_snap() {
  local rsync_exclude='--include=/config/ --include=/config/etcd-snap.db --exclude=*'
  remote_rsync_passive_update "被同步 etcd-snap.db" "${MASTER1_IP}" "${rsync_exclude}"
  remote_rsync_update "同步 etcd-snap.db" "${NODES_MASTER}" "${rsync_exclude}"
}


# rsync 同步脚本内容到多个节点, 参数 $1=message $2=nodes $3=include and exclude parm
remote_rsync_update() {
  local rsync_destination
  local rsync_parm='-avc --delete'
  local rsync_exclude="$3"
  local rsync_source="${script_dir}/"

  for i in $2
  do
    result_blue_font "$1: ${i}"
    rsync_destination="root@${i}:${remoteScriptDir}/"
    rsync ${rsync_parm} ${rsync_exclude} ${rsync_source} ${rsync_destination}
  done
}


# rsync 被某个节点同步, 参数 $1=message $2=node $3=include and exclude parm
remote_rsync_passive_update() {
  local rsync_destination
  local rsync_parm='-avc'
  local rsync_exclude="$3"
  local rsync_source="${script_dir}/"
  local i="$2"

  result_blue_font "$1: ${i}"
  rsync_destination="root@${i}:${remoteScriptDir}/"
  rsync ${rsync_parm} ${rsync_exclude} ${rsync_destination} ${rsync_source}
}


# rsync 同步 kubelet 所需 ca 到所有节点
remote_rsync_kubelet_ca() {
  local rsync_destination
  local rsync_parm='-avc'
  local rsync_exclude="--include=/ca.crt --include=/ca.key --exclude=*"
  local rsync_source="${script_dir}/pki/"

  for i in ${NODES_ALL}
  do
    result_blue_font "同步 kubelet CA: ${i}"
    rsync_destination="root@${i}:${KUBELET_PKI}/"
    rsync ${rsync_parm} ${rsync_exclude} ${rsync_source} ${rsync_destination}
  done
}


main() {
  set +e
  variables_settings_remote
  set -e

  case $1 in
    "freelogin") remote_free_login;;  # 配置本机免密登录到所有节点
    "front") remote_front_operator;;  # scp front.sh --> install rsync
    "install") remote_install_basic;;  # update script,kube.yaml --> update hosts -> basic -> cri --> k8s
    "imglist") remote_images_list;;  # 查看 images 信息
    "imgpull") remote_images_pull;;  # 并发拉取 images
    "cluster") remote_install_cluster;;  # init first node --> create or update join.sh --> update join.sh --> join cluster
    "ca") remote_issue_ca;;  # 创建 CA 证书(pki 目录，不会覆盖)
    "certs") remote_issue_certs;;  # 分发 CA, 并签发 k8s 证书(master node), 此操作会清空 ${KUBEADM_PKI}
    "kubelet") remote_kubelet_certs;;  # 分发 CA, 签发 kubelet 证书，此操作会覆盖原有证书!!!
    "backup") remote_backup_etcd;;  # update script,kube.yaml --> backup etcd
    "restore") remote_restore_etcd;;  # update script,kube.yaml --> resotre etcd
    "auto")
      remote_free_login
      remote_front_operator
      remote_install_basic
      if [ ${remote_CERTS_SWITCH} -eq 1 ]; then
        remote_issue_ca
        remote_issue_certs
      fi
      remote_images_pull
      remote_install_cluster
      if [ ${remote_CERTS_SWITCH} -eq 1 ]; then
        remote_kubelet_certs
      fi
      if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
        remote_deploy_flannel
      fi
      result_blue_font "集群自动安装已完成!"
      ;;
    "upgrade")
      remote_upgrade_version
      if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
        remote_deploy_flannel
      fi
      result_blue_font "集群升级已完成!"
      ;;
    "clean")
      result_blue_font "请确认是否要清除整个集群(y/n):"
      read confirm_yn
      if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
        remote_clean_cluster
      fi
      ;;
    *)
    echo ''
    printf "Usage: bash $0 [ option ] [ ? ] \n"
    result_blue_font "命令："
    printf "%-16s %-s\n" 'auto' '全自动安装集群'
    printf "%-16s %-s\n" 'upgrade' '升级集群版本'
    printf "%-16s %-s\n" 'backup' '备份 etcd 数据库快照'
    printf "%-16s %-s\n" 'restore' '恢复 etcd 数据库'
    printf "%-16s %-s\n" 'clean' '删除整个集群'
    result_blue_font "选项:"
    printf "%-16s %-s\n" '-c' '全自动安装集群时, 签发自定义 k8s 证书, 默认 50 年'
    printf "%-16s %-s\n" '-f' '安装或升级集群后, 自动部署或更新 flannel 网络'
    exit 1
    ;;
  esac
}


# 默认变量
remote_CERTS_SWITCH=0
remote_FLANNEL_SWITCH=0


# 开头 ':' 表示不打印错误信息, 字符后面 ':' 表示需要参数
while getopts ":a:cf" opt; do
  case $opt in
    a)
      # OPTIND 指的下一个选项的 index
      result_blue_font "test: -a arg:$OPTARG index:$OPTIND"
      ;;
    c)
      remote_CERTS_SWITCH=1
      ;;
    f)
      remote_FLANNEL_SWITCH=1
      ;;
    :)
      result_blue_font "Option -$OPTARG requires an argument."
      exit 1
      ;;
    ?)
      result_blue_font "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done

# shift 后, $1 = opts 后面的第一个参数
shift $(($OPTIND - 1))
main $1
#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "Please use bash $0 to run the script!"
  exit 1
fi

set -e
script_type="remote"
script_dir=$(dirname "$(readlink -f "$0")")

source ${script_dir}/modules/const.sh
source ${script_dir}/modules/vars.sh
source ${script_dir}/modules/check.sh

# remote 变量
remote_FLANNEL_SWITCH=0
remote_LOGIN_SWITCH=0
remote_LOGIN_NODES="${NODES_ALL}"
if [ "${nodeUser}" = "root" ]; then
  remote_BASH='bash'
  remote_RM='rm'
else
  remote_BASH='sudo bash'
  remote_RM='sudo rm'
fi

# 免密登录节点
remote_free_login() {
  # 密码为空时，继续手动输入
  while [ ! ${nodePassword} ]; do
    blue_font "Please enter the unified password for all nodes(${nodeUser}):"
    read -s nodePassword
  done

  # 创建 ssh 密钥
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    if [ ! -f ~/.ssh/id_rsa ]; then
      ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
    else
      ssh-keygen -y -f ~/.ssh/id_rsa >~/.ssh/id_rsa.pub
    fi
  fi

  # copy public key 到各个节点
  for i in ${remote_LOGIN_NODES}; do
    sshpass -p "${nodePassword}" ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub ${nodeUser}@${i}
  done
}

# 前置操作, 安装 rsync
remote_front_operator() {
  for i in ${NODES_ALL}; do
    scp -o StrictHostKeyChecking=no -r ${script_dir}/front.sh ${nodeUser}@${i}:/tmp/front.sh
  done
  rrcmd "${nodeUser}" "${remote_BASH} /tmp/front.sh" ${NODES_ALL}
}

# rsync 同步脚本内容到多个节点, 参数 $1=message $2=nodes $3=include and exclude parm
remote_rsync_nodes() {
  local rsync_destination
  local rsync_parm='-avc --delete'
  local rsync_exclude="$3"
  local rsync_source="${script_dir}/"

  for i in $2; do
    blue_font "$1: ${i}"
    rsync_destination="${nodeUser}@${i}:${remoteScriptDir}/"
    rsync ${rsync_parm} ${rsync_exclude} ${rsync_source} ${rsync_destination}
  done
}

# rsync 被某个节点同步, 参数 $1=message $2=node $3=include and exclude parm
remote_rsync_own() {
  local rsync_destination
  local rsync_parm='-avc'
  local rsync_exclude="$3"
  local rsync_source="${script_dir}/"
  local i="$2"

  blue_font "$1: ${i}"
  rsync_destination="${nodeUser}@${i}:${remoteScriptDir}/"
  rsync ${rsync_parm} ${rsync_exclude} ${rsync_destination} ${rsync_source}
}

# 同步脚本文件和配置文件
remote_rsync_script() {
  local rsync_exclude='--include=/modules/ --include=/modules/* --include=/bin/ --include=/bin/* --include=/config/ --include=/config/kube.yaml --include=/local.sh --exclude=*'
  remote_rsync_nodes "Sync script" "${NODES_ALL}" "${rsync_exclude}"
}

# 同步 master1 上的 cluster join 信息到非 master1 节点
remote_rsync_kube() {
  local rsync_exclude='--include=/config/ --include=/config/kube.yaml --exclude=*'
  remote_rsync_own "kube.yaml sync by master1" "${MASTER1_IP}" "${rsync_exclude}"
  remote_rsync_nodes "Sync kube.yaml" "${NODES_NOT_MASTER1}" "${rsync_exclude}"
}

# 初始化系统
remote_base_install() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh install" ${NODES_ALL}
}

# 拉取所需 images
remote_images_pull() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh imgpull" ${NODES_MASTER1_MASTER}
}

# 安装集群
remote_deploy_cluster() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh init" ${MASTER1_IP}
  sleep 2
  remote_rsync_kube
  sleep 2
  for i in ${NODES_NOT_MASTER1}; do
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh join" ${i}
  done
}

# 部署 flannel
remote_deploy_flannel() {
  sleep 2
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh flannel" ${MASTER1_IP}
}

# 升级 cri
remote_upgrade_cri() {
  for i in ${NODES_MASTER1_MASTER}; do
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh cri" ${i}
  done

  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh token" ${MASTER1_IP}
  remote_rsync_kube

  for i in ${NODES_WORK}; do
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh context cri" ${i}
  done
}

# 升级 cluster
remote_upgrade_cluster() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh backup" ${NODES_MASTER1_MASTER}
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh upgrade" ${MASTER1_IP}

  for i in ${NODES_MASTER}; do
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh upgrade" ${i}
  done

  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh token" ${MASTER1_IP}
  remote_rsync_kube

  for i in ${NODES_WORK}; do
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh context upgrade" ${i}
  done
}

# 备份 etcd
remote_backup_cluster() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh backup" ${NODES_MASTER1_MASTER}
}

# 删除整个集群
remote_clean_cluster() {
  blue_font "Clean nodes: ${i}"
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh clean" ${NODES_ALL}

  yq -i '
    .join = {} |
    .kubeconfig = {}
  ' ${KUBE_FILE}
  yq ${KUBE_FILE}
}

# 查看所有变量
remote_display_vars() {
  blue_font "------ local ------"
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh vars" ${MASTER1_IP}
  blue_font "------ remote ------"
  display_vars
}

# 查看所需 images
remote_images_list() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh imglist" ${MASTER1_IP}
}

remote_etc_hosts() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh hosts" ${NODES_ALL}
}

# 自动部署
remote_auto() {
  if [ ${remote_LOGIN_SWITCH} -eq 1 ]; then
    remote_free_login
  fi
  remote_front_operator # scp front.sh --> install rsync
  remote_base_install   # update hosts -> system base -> cri --> k8s
  remote_images_pull    # pull images
  remote_deploy_cluster # init m1 --> join command --> sync kube.yaml --> join cluster
  if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
    remote_deploy_flannel
  fi
  blue_font "✓ Cluster installation completed!"
}

# 清除整个集群
remote_clean() {
  blue_font "Warning: This will destroy the entire cluster. Proceed?(y/n):"
  read confirm_yn
  if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
    blue_font "Warning: This will destroy the entire cluster. Proceed?(y/n):"
    read confirm_yn
    if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
      remote_clean_cluster
      blue_font "✔ Cluster uninstalled. Please manually reboot all nodes!"
    fi
  fi
}

main() {
  local args="vars imglist hosts auto cri upgrade backup clean"

  if [[ " $args " =~ " $1 " ]]; then
    remote_rsync_script
  fi

  case $1 in
    "vars") remote_display_vars ;;
    "imglist") remote_images_list ;;
    "hosts") remote_etc_hosts ;;

    "auto")
      remote_auto
      ;;

    "cri")
      remote_upgrade_cri
      blue_font "✔ Container runtime upgrade completed!"
      ;;

    "upgrade")
      remote_upgrade_cluster
      if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
        remote_deploy_flannel
      fi
      blue_font "✔ Cluster upgrade completed!"
      ;;

    "backup") remote_backup_cluster ;; # backup /etc/kubernetes and etcd

    "clean") remote_clean ;;
    *)
      echo ''
      printf "Usage: bash $0 [ option ] [ ? ] \n"
      blue_font "Command:"
      printf "%-16s %-s\n" 'vars' 'display all variables'
      printf "%-16s %-s\n" 'imglist' 'display all images'
      printf "%-16s %-s\n" 'hosts' 'update hosts'

      printf "%-16s %-s\n" 'auto' 'Automated K8s Cluster Installer(Incremental Support)'

      printf "%-16s %-s\n" 'cri' 'Automated CRI Upgrade'

      printf "%-16s %-s\n" 'upgrade' 'Automated Cluster Upgrade'

      printf "%-16s %-s\n" 'backup' 'Backup /etc/kubernetes and etcd'

      printf "%-16s %-s\n" 'clean' 'Destroy Entire K8s Cluster'

      blue_font "Option:"
      printf "%-16s %-s\n" '-l string' 'Automatic ssh password-free login (all or ip)'
      printf "%-16s %-s\n" '-f' 'After installing or upgrading k8s cluster, automatically deploy(update) flannel'
      exit 1
      ;;
  esac
}

# 开头 ':' 表示不打印错误信息, 字符后面 ':' 表示需要参数
while getopts ":a:l:f" opt; do
  case $opt in
    a)
      # OPTIND 指的下一个选项的 index
      blue_font "test: -a arg:$OPTARG index:$OPTIND"
      ;;
    l)
      remote_LOGIN_SWITCH=1
      pattern='^(([0-9]{1,3}\.){3}[0-9]{1,3}[[:space:]])*([0-9]{1,3}\.){3}[0-9]{1,3}$'
      if [[ "$OPTARG" =~ ${pattern} ]]; then
        remote_LOGIN_NODES="$OPTARG"
      elif [ "$OPTARG" = "all" ] || [ "$OPTARG" = "a" ]; then
        remote_LOGIN_NODES="${NODES_ALL}"
      else
        blue_font "Invalid argument: $OPTARG"
        exit 1
      fi
      ;;
    f)
      remote_FLANNEL_SWITCH=1
      ;;
    :)
      blue_font "Option -$OPTARG requires an argument."
      exit 1
      ;;
    ?)
      blue_font "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done

# shift 后, $1 = opts 后面的第一个参数
shift $(($OPTIND - 1))
main $1

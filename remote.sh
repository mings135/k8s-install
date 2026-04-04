#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "请使用 bash $0 运行脚本!"
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
    blue_font "请输入所有节点的统一密码 (${nodeUser}):"
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
  remote_rsync_nodes "同步脚本" "${NODES_ALL}" "${rsync_exclude}"
}

# 同步 master1 上的 cluster join 信息到非 master1 节点
remote_rsync_kube() {
  local rsync_exclude='--include=/config/ --include=/config/kube.yaml --exclude=*'
  remote_rsync_own "被同步 kube.yaml" "${MASTER1_IP}" "${rsync_exclude}"
  remote_rsync_nodes "同步 kube.yaml" "${NODES_NOT_MASTER1}" "${rsync_exclude}"
}

# 初始化系统
remote_base_install() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh install" ${NODES_ALL}
}

# 查看所需 images
remote_images_list() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh imglist" ${MASTER1_IP}
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
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh backup" ${NODES_MASTER}
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

# 备份 etcd 快照
remote_backup_cluster() {
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh backup" ${NODES_MASTER}
}

# 删除整个集群
remote_clean_cluster() {
  blue_font "清理节点: ${i}"
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh clean" ${NODES_ALL}
  rrcmd "${nodeUser}" "${remote_RM} -rf ${remoteScriptDir}" ${NODES_ALL}
  yq -i '
    .join = {} |
    .kubeconfig = {}
  ' ${KUBE_FILE}
}

remote_display_vars() {
  blue_font "------ local ------"
  rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh vars" ${MASTER1_IP}
  blue_font "------ remote ------"
  display_vars
}

remote_auto() {
  if [ ${remote_LOGIN_SWITCH} -eq 1 ]; then
    remote_free_login
  fi
  remote_front_operator # scp front.sh --> install rsync
  remote_base_install   # update script, kube.yaml --> update hosts -> base -> cri --> k8s
  remote_images_pull    # 并发拉取 images
  remote_deploy_cluster # init m1 node --> create or update join.sh --> distribution join.sh --> join cluster
  if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
    remote_deploy_flannel
  fi
}

main() {
  local args="vars imglist backup auto cri upgrade clean"

  if [[ " $args " =~ " $1 " ]]; then
    remote_rsync_script
  fi

  case $1 in
    "vars") remote_display_vars ;;
    "imglist") remote_images_list ;;   # 查看 images 信息
    "backup") remote_backup_cluster ;; # update script,kube.yaml --> backup etcd
    "auto")
      remote_auto
      blue_font "集群自动安装已完成!"
      ;;
    "cri")
      remote_upgrade_cri
      blue_font "容器运行时升级已完成!"
      ;;
    "upgrade")
      remote_upgrade_cluster
      if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
        remote_deploy_flannel
      fi
      blue_font "集群升级已完成!"
      ;;
    "clean")
      blue_font "请确认是否要清除整个集群(y/n):"
      read confirm_yn
      if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
        blue_font "请再次确认是否要清除整个集群(y/n):"
        read confirm_yn
        if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
          remote_clean_cluster
          blue_font "集群卸载已完成, 请手动重启所有节点!"
        fi
      fi
      ;;
    *)
      echo ''
      printf "Usage: bash $0 [ option ] [ ? ] \n"
      blue_font "命令："
      printf "%-16s %-s\n" 'vars' '查看变量'
      printf "%-16s %-s\n" 'auto' '自动安装 k8s 集群(支持增量)'
      printf "%-16s %-s\n" 'cri' '自动升级 CRI'
      printf "%-16s %-s\n" 'upgrade' '自动升级 k8s 集群'
      printf "%-16s %-s\n" 'backup' '备份 etcd 数据库'
      printf "%-16s %-s\n" 'clean' '删除整个 k8s 集群'
      blue_font "选项:"
      printf "%-16s %-s\n" '-l string' '自动 ssh 免密登录(all or ip)'
      printf "%-16s %-s\n" '-f' '安装或升 k8s 级集群后, 自动部署(更新) flannel'
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
      tmp_regex='^(([0-9]{1,3}\.){3}[0-9]{1,3}[[:space:]])*([0-9]{1,3}\.){3}[0-9]{1,3}$'
      if [[ "$OPTARG" =~ $tmp_regex ]]; then
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

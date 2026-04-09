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
cni_switch=0

if [[ "${nodeUser}" == "root" ]]; then
  remote_sh='bash'
else
  remote_sh='sudo bash'
fi

remote_cmd="${remote_sh} ${remoteScriptDir}/local.sh"
profile_full=(-u "${nodeUser}" -j "${maxConcurrency}" -p '^·\[.*\]$')
profile_low=(-u "${nodeUser}" -j "${minConcurrency}" -p '^·\[.*\]$')
profile_upgrade=(-u "${nodeUser}" -j "${upgradeConcurrency}" -p '^·\[.*\]$')

# 免密登录节点
remote_free_login() {
  # 密码为空时，继续手动输入
  while [[ -z ${nodePassword} ]]; do
    blue_font "[Input] unified password for all nodes(${nodeUser}):"
    read -s nodePassword
  done

  # 创建 ssh 密钥
  if [[ ! -f ${HOME}/.ssh/id_rsa.pub ]]; then
    if [[ ! -f ${HOME}/.ssh/id_rsa ]]; then
      ssh-keygen -t rsa -b 2048 -f ${HOME}/.ssh/id_rsa -N ''
    else
      ssh-keygen -y -f ${HOME}/.ssh/id_rsa >${HOME}/.ssh/id_rsa.pub
    fi
  fi

  # copy public key 到各个节点
  for i in ${1}; do
    sshpass -p "${nodePassword}" ssh-copy-id -o StrictHostKeyChecking=no -i ${HOME}/.ssh/id_rsa.pub ${nodeUser}@${i}
  done
}

# 前置操作, 安装 rsync
remote_front_operator() {
  for i in ${1}; do
    scp -o StrictHostKeyChecking=no -r ${script_dir}/front.sh ${nodeUser}@${i}:/tmp/front.sh
  done
  echo
  if [[ -n $(echo "${1}" | tr -d '[:space:]') ]]; then
    rrcmd "${profile_full[@]}" -c "${remote_sh} /tmp/front.sh" ${1}
  fi
}

remote_check_login() {
  blue_font "[Check] login and rsync status..."

  local output rc=0
  output=$(rrcmd "${profile_full[@]}" -f -q -c "command -v rsync &>/dev/null" ${NODES_ALL}) || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    local end="$(echo "${output}" | awk 'END{print}')"
    remote_free_login "${end}"
    remote_front_operator "${end}"
  fi
  echo
}

# rsync 同步脚本内容到多个节点, 参数 $1=message $2=nodes $3=include and exclude parm
remote_rsync_nodes() {
  local dest
  local parm='-avc --delete'
  local excl="$3"
  local src="${script_dir}/"

  for i in $2; do
    blue_font "$1" ": ${i}"
    dest="${nodeUser}@${i}:${remoteScriptDir}/"
    rsync ${parm} ${excl} ${src} ${dest}
  done
  echo
}

# rsync 被某个节点同步, 参数 $1=message $2=node $3=include and exclude parm
remote_rsync_own() {
  local dest
  local parm='-avc'
  local excl="$3"
  local src="${script_dir}/"
  local i="$2"

  blue_font "$1" ": ${i}"
  dest="${nodeUser}@${i}:${remoteScriptDir}/"
  rsync ${parm} ${excl} ${dest} ${src}
  echo
}

# 同步脚本文件和配置文件 $1=nodes
remote_rsync_script() {
  local excl='--include=/modules/ --include=/modules/* --include=/bin/ --include=/bin/* --include=/config/ --include=/config/kube.yaml --include=/local.sh --exclude=*'
  remote_rsync_nodes "[Sync] script out to nodes" "${1}" "${excl}"
}

# 同步 master1 上的 join, kubeconfig 到非 master1 节点
remote_rsync_kube() {
  local excl='--include=/config/ --include=/config/kube.yaml --exclude=*'
  remote_rsync_own "[Sync] kube.yaml in from master1" "${MASTER1_IP}" "${excl}"
  remote_rsync_nodes "[Sync] kube.yaml out to nodes" "${NODES_NOT_MASTER1}" "${excl}"
}

remote_rsync_backup_in() {
  local excl='--include=/backup/ --include=/backup/* --exclude=*'
  remote_rsync_own "[Sync] backup in from master1" "${MASTER1_IP}" "${excl}"
}

remote_rsync_backup_out() {
  local excl='--include=/backup/ --include=/backup/* --exclude=*'
  remote_rsync_nodes "[Sync] backup out to master1" "${MASTER1_IP}" "${excl}"
}

# 初始化系统
remote_base_install() {
  rrcmd "${profile_full[@]}" -c "${remote_cmd} install" ${NODES_ALL}
}

# 拉取所需 images
remote_images_pull() {
  rrcmd "${profile_full[@]}" -c "${remote_cmd} imgpull" ${NODES_MASTER1_MASTER}
}

# 安装集群
remote_deploy_cluster() {

  rrcmd "${profile_low[@]}" -c "${remote_cmd} init" ${MASTER1_IP}
  sleep 1
  remote_rsync_kube
  sleep 1

  if [[ -n $(echo "${NODES_MASTER}" | tr -d '[:space:]') ]]; then
    rrcmd "${profile_low[@]}" -c "${remote_cmd} join" ${NODES_MASTER}
  fi

  if [[ -n $(echo "${NODES_WORK}" | tr -d '[:space:]') ]]; then
    rrcmd "${profile_full[@]}" -c "${remote_cmd} join" ${NODES_WORK}
  fi
}

# 部署 flannel
remote_deploy_flannel() {
  sleep 1
  rrcmd "${profile_low[@]}" -c "${remote_cmd} flannel" ${MASTER1_IP}
}

# 升级 cri
remote_upgrade_cri() {

  rrcmd "${profile_low[@]}" -c "${remote_cmd} cri" ${NODES_MASTER1_MASTER}

  rrcmd "${profile_low[@]}" -c "${remote_cmd} token" ${MASTER1_IP}
  sleep 1
  remote_rsync_kube
  sleep 1

  if [[ -n $(echo "${NODES_WORK}" | tr -d '[:space:]') ]]; then
    rrcmd "${profile_upgrade[@]}" -c "${remote_cmd} context cri" ${NODES_WORK}
  fi
}

# 升级 cluster
remote_upgrade_cluster() {
  rrcmd "${profile_low[@]}" -c "${remote_cmd} upgrade" ${MASTER1_IP}

  if [[ -n $(echo "${NODES_MASTER}" | tr -d '[:space:]') ]]; then
    rrcmd "${profile_low[@]}" -c "${remote_cmd} upgrade" ${NODES_MASTER}
  fi

  rrcmd "${profile_low[@]}" -c "${remote_cmd} token" ${MASTER1_IP}
  sleep 1
  remote_rsync_kube
  sleep 1

  if [[ -n $(echo "${NODES_WORK}" | tr -d '[:space:]') ]]; then
    rrcmd "${profile_upgrade[@]}" -c "${remote_cmd} context upgrade" ${NODES_WORK}
  fi
}

# 备份 etcd
remote_backup_cluster() {
  remote_rsync_backup_out
  rrcmd "${profile_low[@]}" -c "${remote_cmd} backup" ${MASTER1_IP}
  sleep 1
  remote_rsync_backup_in
}

# 删除整个集群
remote_clean_cluster() {
  rrcmd "${profile_low[@]}" -c "${remote_cmd} clean" ${NODES_MASTER1_MASTER}

  if [[ -n $(echo "${NODES_WORK}" | tr -d '[:space:]') ]]; then
    rrcmd "${profile_full[@]}" -c "${remote_cmd} clean" ${NODES_WORK}
  fi

  yq -i '
    .join = {} |
    .kubeconfig = {}
  ' ${KUBE_FILE}
  blue_font "[Display] current config" ": ${KUBE_FILE}"
  yq ${KUBE_FILE}
}

# 查看所有变量
remote_display_vars() {
  blue_font "------ [Display] master1 vars ------"
  rrcmd "${profile_low[@]}" -c "${remote_cmd} vars" ${MASTER1_IP}

  for i in ${NODES_MASTER}; do
    blue_font "------ [Display] master vars ------"
    rrcmd "${profile_low[@]}" -c "${remote_cmd} vars" ${i}
    break
  done

  for i in ${NODES_WORK}; do
    blue_font "------ [Display] work vars ------"
    rrcmd "${profile_low[@]}" -c "${remote_cmd} vars" ${i}
    break
  done

  blue_font "------ [Display] remote vars ------"
  display_vars
}

# 查看所需 images
remote_images_list() {
  rrcmd "${profile_low[@]}" -c "${remote_cmd} imglist" ${MASTER1_IP}
}

remote_etc_hosts() {
  rrcmd "${profile_full[@]}" -c "${remote_cmd} hosts" ${NODES_ALL}
}

# 自动部署
remote_auto() {
  remote_base_install   # update hosts -> system base -> cri --> k8s
  remote_images_pull    # pull images
  remote_deploy_cluster # init m1 --> join command --> sync kube.yaml --> join cluster
  if [ ${cni_switch} -eq 1 ]; then
    remote_deploy_flannel
  fi
  blue_font "✔ Cluster installation completed!"
}

# 清除整个集群
remote_clean() {
  yellow_font "[Warning]: This will destroy the entire cluster. Proceed?(y/n):"
  read confirm_yn
  if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
    yellow_font "[Warning]: This will destroy the entire cluster. Proceed?(y/n):"
    read confirm_yn
    if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
      remote_clean_cluster
      blue_font "✔ Cluster cleanup completed!"
    fi
  fi
}

main() {

  local args_all="vars hosts auto cri upgrade clean"
  local args_m1="imglist backup"

  if [[ " $args_all " =~ " $1 " ]]; then
    remote_check_login
    remote_rsync_script "${NODES_ALL}"
  elif [[ " $args_m1 " =~ " $1 " ]]; then
    remote_check_login
    remote_rsync_script "${MASTER1_IP}"
  fi

  case $1 in
    "vars") remote_display_vars ;;
    "imglist") remote_images_list ;;
    "hosts")
      remote_etc_hosts
      blue_font "✔ hosts update completed!"
      ;;

    "auto")
      remote_auto
      ;;

    "cri")
      remote_upgrade_cri
      blue_font "✔ CRI upgrade completed!"
      ;;

    "upgrade")
      remote_upgrade_cluster
      if [ ${cni_switch} -eq 1 ]; then
        remote_deploy_flannel
      fi
      blue_font "✔ Cluster upgrade completed!"
      ;;

    "backup")
      remote_backup_cluster # backup /etc/kubernetes and etcd
      blue_font "✔ Cluster backup completed!"
      ;;

    "clean") remote_clean ;;
    *)
      echo ''
      printf "Usage: bash $0 [ option ] [ ? ] \n"
      blue_font "Command:"
      printf "%-16s %-s\n" 'vars' 'Display all variables'
      printf "%-16s %-s\n" 'imglist' 'Display all images'
      printf "%-16s %-s\n" 'hosts' 'Update hosts'

      printf "%-16s %-s\n" 'auto' 'Automated K8s Cluster Installer(Incremental Support)'

      printf "%-16s %-s\n" 'cri' 'Automated CRI Upgrade'

      printf "%-16s %-s\n" 'upgrade' 'Automated Cluster Upgrade'

      printf "%-16s %-s\n" 'backup' 'Backup containerd kubernetes and etcd'

      printf "%-16s %-s\n" 'clean' 'Destroy Entire K8s Cluster'

      blue_font "Option:"
      printf "%-16s %-s\n" '-f' 'After installing or upgrading k8s cluster, automatically deploy(update) flannel'
      exit 1
      ;;
  esac
}

# 开头 ':' 表示不打印错误信息, 字符后面 ':' 表示需要参数
while getopts ":a:f" opt; do
  case $opt in
    a)
      # OPTIND 指的下一个选项的 index
      blue_font "test: -a arg:$OPTARG index:$OPTIND"
      ;;
    f)
      cni_switch=1
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

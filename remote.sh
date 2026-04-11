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

remote_variables() {
  if [[ "${nodeUser}" == "root" ]]; then
    remote_sh='bash'
  else
    remote_sh='sudo bash'
  fi

  if [[ "${quiet_switch}" -eq 1 ]]; then
    common_args=(-u "${nodeUser}" -p '^·\[.*\]$' -q)
  else
    common_args=(-u "${nodeUser}" -p '^·\[.*\]$')
  fi

  ssh_args=(-a "-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=20")

  remote_cmd="${remote_sh} ${remoteScriptDir}/local.sh"

  profile_full=("${ssh_args[@]}" "${common_args[@]}" -j "${maxJobs}")
  profile_low=("${ssh_args[@]}" "${common_args[@]}" -j "${minJobs}")
  profile_upgrade=("${ssh_args[@]}" "${common_args[@]}" -j "${upgradeJobs}")
}

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

  local args="-e ssh-copy-id -o StrictHostKeyChecking=no -i ${HOME}/.ssh/id_rsa.pub"
  export SSHPASS="${nodePassword}"
  # copy public key 到各个节点
  if [[ -n $(echo "${1}" | tr -d '[:space:]') ]]; then
    rrcmd -b "sshpass" -a "${args}" "${common_args[@]}" -j "${maxJobs}" ${1}
  fi
  unset SSHPASS
}

# 前置操作, 安装 rsync
remote_front_operator() {
  if [[ -n $(echo "${1}" | tr -d '[:space:]') ]]; then
    local args="-o StrictHostKeyChecking=no -r ${script_dir}/front.sh"
    rrcmd -b "scp" -a "${args}" "${common_args[@]}" -j "${maxJobs}" -path "/tmp/front.sh" ${1}
    rrcmd "${profile_full[@]}" -c "${remote_sh} /tmp/front.sh" ${1}
  fi
}

# 检查 login 和 rsync 状态, 并自动处理
remote_check_login() {
  blue_font "[Check] login and rsync status..."

  local output rc=0
  output=$(rrcmd "${profile_full[@]}" -c "command -v rsync &>/dev/null" ${NODES_ALL}) || rc=$?

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

  # for i in $2; do
  #   blue_font "$1" ": ${i}"
  #   dest="${nodeUser}@${i}:${remoteScriptDir}/"
  #   rsync ${parm} ${excl} ${src} ${dest}
  # done
  # echo

  blue_font "$1"
  rrcmd -b "rsync" -a "${parm} ${excl} ${src}" "${common_args[@]}" -j "${maxJobs}" -path "${remoteScriptDir}/" $2
}

# rsync 被某个节点同步, 参数 $1=message $2=node $3=include and exclude parm
remote_rsync_own() {
  local dest
  local parm='-avc'
  local excl="$3"
  local src="${script_dir}/"
  local i="$2"

  # blue_font "$1" ": ${i}"
  # dest="${nodeUser}@${i}:${remoteScriptDir}/"
  # rsync ${parm} ${excl} ${dest} ${src}
  # echo

  blue_font "$1"
  rrcmd -b "rsync" -a "${parm} ${excl}" "${common_args[@]}" -j "${maxJobs}" -path "${remoteScriptDir}/" -c "${src}" $2
}

# 同步脚本文件和配置文件
remote_rsync_script() {
  local excl='--include=/modules/ --include=/modules/* --include=/bin/ --include=/bin/* --include=/config/ --include=/config/kube.yaml --include=/local.sh --exclude=*'
  remote_rsync_nodes "[Sync] script out to nodes" "${NODES_ALL}" "${excl}"
}

# 同步 master1 上的 kube.yaml 到各个节点
remote_rsync_kube() {
  local excl='--include=/config/ --include=/config/kube.yaml --exclude=*'
  remote_rsync_own "[Sync] kube.yaml in from master1" "${MASTER1_IP}" "${excl}"
  remote_rsync_nodes "[Sync] kube.yaml out to nodes" "${NODES_NOT_MASTER1}" "${excl}"
}

# 同步 master1 上的 backup 到 devops
remote_rsync_backup_in() {
  local excl='--include=/backup/ --include=/backup/* --exclude=*'
  remote_rsync_own "[Sync] backup in from master1" "${MASTER1_IP}" "${excl}"
}

# 同步 devops 上的 backup 到 master1
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

# 删除节点
remote_delete_nodes() {
  rrcmd "${profile_low[@]}" -c "${remote_cmd} delete" ${MASTER1_IP}

  if [[ -n "${DELETE_WORKS}" ]]; then
    local works
    for i in ${DELETE_WORKS}; do
      works+="${i#*=} "
    done
    rrcmd "${profile_full[@]}" -c "${remote_cmd} clean" ${works}
  fi
  sleep 1
  remote_rsync_kube
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

# 更新 /etc/hosts
remote_etc_hosts() {
  rrcmd "${profile_full[@]}" -c "${remote_cmd} hosts" ${NODES_ALL}
}

# 自动部署 cluster
remote_auto() {
  remote_base_install   # update hosts -> system base -> cri --> k8s
  remote_images_pull    # pull images
  remote_deploy_cluster # init m1 --> join command --> sync kube.yaml --> join cluster
  if [[ "${cni_switch}" -eq 1 ]]; then
    remote_deploy_flannel
  fi
  blue_font "✔ Cluster installation completed!"
}

# 自动清理 cluster
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

# 显示帮助
remote_help() {
  echo ''
  printf "Usage: bash $0 [ option ] [ ? ] \n"
  blue_font "Command:"
  printf "%-16s %-s\n" 'vars' 'Display all variables'
  printf "%-16s %-s\n" 'hosts' 'Update hosts'

  printf "%-16s %-s\n" 'auto' 'Automated K8s Cluster Installer(Incremental Support)'

  printf "%-16s %-s\n" 'cri' 'Automated CRI Upgrade'

  printf "%-16s %-s\n" 'upgrade' 'Automated Cluster Upgrade'

  printf "%-16s %-s\n" 'backup' 'Backup containerd kubernetes and etcd'

  printf "%-16s %-s\n" 'delete' 'Delete with work nodes by tag'
  printf "%-16s %-s\n" 'clean' 'Destroy Entire K8s Cluster'

  blue_font "Option:"
  printf "%-16s %-s\n" '-f' 'After installing or upgrading k8s cluster, automatically deploy(update) flannel'
  printf "%-16s %-s\n" '-q' 'Quiet mode, only display status and error message'
  exit 1
}

main() {
  remote_variables
  if [[ -n "$1" ]]; then
    remote_check_login
    remote_rsync_script
  fi

  case $1 in
    "vars") remote_display_vars ;;
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
      if [[ "${cni_switch}" -eq 1 ]]; then
        remote_deploy_flannel
      fi
      blue_font "✔ Cluster upgrade completed!"
      ;;

    "backup")
      remote_backup_cluster # backup /etc/kubernetes and etcd
      blue_font "✔ Cluster backup completed!"
      ;;

    "delete")
      remote_delete_nodes
      blue_font "✔ Work nodes deleted completed!"
      ;;
    "clean") remote_clean ;;
    *) remote_help ;;
  esac
}

cni_switch=0
quiet_switch=0

# 开头 ':' 表示不打印错误信息, 字符后面 ':' 表示需要参数
while getopts ":a:fhq" opt; do
  case $opt in
    a)
      # OPTIND 指的下一个选项的 index
      blue_font "test: -a arg:$OPTARG index:$OPTIND"
      ;;
    f)
      cni_switch=1
      ;;
    h)
      remote_help
      ;;
    q)
      quiet_switch=1
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

#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
    echo "请使用 bash $0 运行脚本!"
    exit 1
fi

set -e
script_dir=$(dirname $(readlink -f $0))

source ${script_dir}/modules/const.sh
source ${script_dir}/modules/variables.sh
source ${script_dir}/modules/check.sh
set +e

const_init
variables_remote
check_variables
set -e

# 默认变量
remote_BASH='bash'
remote_RM='rm'
remote_FLANNEL_SWITCH=0
remote_LOGIN_SWITCH=0
remote_LOGIN_NODES=all

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

# 安装和配置所需的基础
remote_install_basic() {
    remote_rsync_script
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh install" ${NODES_ALL}
}

# 签发 CA 证书(创建 pki 目录)
remote_issue_ca() {
    source ${script_dir}/modules/certs.sh

    if [ -d ${script_dir}/pki ]; then
        blue_font "已创建过 CA, 如需更换 CA, 请先手动删除 ${script_dir}/pki 目录!!!"
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
    for i in ${NODES_MASTER1_MASTER}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh certs" ${i}
    done
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
remote_install_cluster() {
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh initcluster" ${MASTER1_IP}
    sleep 1
    remote_rsync_join
    sleep 1
    for i in ${NODES_NOT_MASTER1}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh joincluster" ${i}
    done
}

# 签发 kubelet 证书
remote_kubelet_certs() {
    remote_rsync_kubelet_ca
    for i in ${NODES_ALL}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh kubelet" ${i}
        rrcmd "${nodeUser}" "${remote_RM} -f ${KUBELET_PKI}/ca.crt" ${i}
        rrcmd "${nodeUser}" "${remote_RM} -f ${KUBELET_PKI}/ca.key" ${i}
    done
}

# 部署 flannel
remote_deploy_flannel() {
    sleep 3
    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh flannel" ${MASTER1_IP}
}

# 更新集群版本
remote_upgrade_version() {
    remote_rsync_script

    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh upgrade" ${MASTER1_IP}

    for i in ${NODES_MASTER}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh upgrade" ${i}
    done

    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh tmpkubeconfig" ${MASTER1_IP}
    remote_rsync_kubeconfig_tmp
    for i in ${NODES_WORK}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh tmpkubectl upgrade" ${i}
    done
}

# 更新容器运行时版本
remote_cri_upgrade_version() {
    remote_rsync_script

    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh criupgrade" ${MASTER1_IP}

    for i in ${NODES_MASTER}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh criupgrade" ${i}
    done

    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh tmpkubeconfig" ${MASTER1_IP}
    remote_rsync_kubeconfig_tmp
    for i in ${NODES_WORK}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh tmpkubectl criupgrade" ${i}
    done

    for i in ${NODES_ALL}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh criupgradeopt" ${i}
    done
}

# 备份 etcd 快照
remote_backup_etcd() {
    remote_rsync_script

    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh backup" ${MASTER1_IP}
}

# 恢复 etcd
remote_restore_etcd() {
    remote_rsync_script

    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh restore" ${MASTER1_IP}

    remote_rsync_etcd_snap
    for i in ${NODES_MASTER}; do
        rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh restore" ${i}
    done

    rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh startetcd" ${NODES_MASTER1_MASTER}
}

# 删除整个集群
remote_clean_cluster() {
    remote_rsync_script
    for i in ${NODES_ALL}; do
        if rrcmd "${nodeUser}" "test -e ${remoteScriptDir}/local.sh" ${i}; then
            blue_font "清理节点: ${i}"
            rrcmd "${nodeUser}" "${remote_BASH} ${remoteScriptDir}/local.sh clean" ${i}
            rrcmd "${nodeUser}" "${remote_RM} -rf ${remoteScriptDir}" ${i}
        fi
    done
}
###

# 同步脚本文件和配置文件
remote_rsync_script() {
    local rsync_exclude='--include=/modules/ --include=/modules/* --include=/bin/ --include=/bin/* --include=/config/ --include=/config/kube.yaml --include=/local.sh --exclude=*'
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

    for i in $2; do
        blue_font "$1: ${i}"
        rsync_destination="${nodeUser}@${i}:${remoteScriptDir}/"
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

    blue_font "$1: ${i}"
    rsync_destination="${nodeUser}@${i}:${remoteScriptDir}/"
    rsync ${rsync_parm} ${rsync_exclude} ${rsync_destination} ${rsync_source}
}

# rsync 同步 kubelet 所需 ca 到所有节点
remote_rsync_kubelet_ca() {
    local rsync_destination
    local rsync_parm='-avc'
    local rsync_exclude="--include=/ca.crt --include=/ca.key --exclude=*"
    local rsync_source="${script_dir}/pki/"

    for i in ${NODES_ALL}; do
        blue_font "同步 kubelet CA: ${i}"
        rsync_destination="${nodeUser}@${i}:${KUBELET_PKI}/"
        rsync ${rsync_parm} ${rsync_exclude} ${rsync_source} ${rsync_destination}
    done
}

main() {
    if [ "${remote_LOGIN_NODES}" = 'all' ]; then
        remote_LOGIN_NODES="${NODES_ALL}"
    fi
    if [ "${nodeUser}" != 'root' ]; then
        remote_BASH='sudo bash'
        remote_RM='sudo rm'
    fi

    case $1 in
    "freelogin") remote_free_login ;; # 配置本机免密登录到所有节点
    # "front") remote_front_operator;;  # scp front.sh --> install rsync
    # "install") remote_install_basic;;  # update script,kube.yaml --> update hosts -> basic -> cri --> k8s
    # "imglist") remote_images_list;;  # 查看 images 信息
    # "imgpull") remote_images_pull;;  # 并发拉取 images
    # "cluster") remote_install_cluster;;  # init first node --> create or update join.sh --> update join.sh --> join cluster
    # "ca") remote_issue_ca;;  # 创建 CA 证书(pki 目录，不会覆盖)
    # "certs") remote_issue_certs;;  # 分发 CA, 并签发 k8s 证书(master node), 此操作会清空 ${KUBEADM_PKI}
    # "kubelet") remote_kubelet_certs;;  # 分发 CA, 签发 kubelet 证书，此操作会覆盖原有证书!!!
    "backup") remote_backup_etcd ;;   # update script,kube.yaml --> backup etcd
    "restore") remote_restore_etcd ;; # update script,kube.yaml --> resotre etcd
    "auto")
        if [ ${remote_LOGIN_SWITCH} -eq 1 ]; then
            remote_free_login
        fi
        remote_front_operator
        remote_install_basic
        if [ "${kubeadmSignCertificate}" = 'false' ]; then
            remote_issue_ca
            remote_issue_certs
        fi
        remote_images_pull
        remote_install_cluster
        if [ "${kubeadmSignCertificate}" = 'false' ]; then
            remote_kubelet_certs
        fi
        if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
            remote_deploy_flannel
        fi
        blue_font "集群自动安装已完成!"
        ;;
    "upgrade")
        remote_upgrade_version
        if [ ${remote_FLANNEL_SWITCH} -eq 1 ]; then
            remote_deploy_flannel
        fi
        blue_font "集群升级已完成!"
        ;;
    "criupgrade")
        remote_cri_upgrade_version
        blue_font "容器运行时升级已完成!"
        ;;
    "clean")
        blue_font "请确认是否要清除整个集群(y/n):"
        read confirm_yn
        if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
            blue_font "请再次确认是否要清除整个集群(y/n):"
            read confirm_yn
            if [ ${confirm_yn} ] && [ ${confirm_yn} = 'y' ]; then
                remote_clean_cluster
            fi
        fi
        blue_font "集群卸载已完成, 请手动重启所有节点!"
        ;;
    *)
        echo ''
        printf "Usage: bash $0 [ option ] [ ? ] \n"
        blue_font "命令："
        printf "%-16s %-s\n" 'auto' '全自动安装集群'
        printf "%-16s %-s\n" 'upgrade' '升级集群版本'
        printf "%-16s %-s\n" 'criupgrade' '升级容器运行时版本(支持 latest 每次升级至最新)'
        printf "%-16s %-s\n" 'backup' '备份 etcd 数据库快照'
        printf "%-16s %-s\n" 'restore' '恢复 etcd 数据库'
        printf "%-16s %-s\n" 'clean' '删除整个集群'
        blue_font "选项:"
        printf "%-16s %-s\n" '-l string' '自动创建 ssh 密钥, 并分发到节点, 实现免密登录(all or ip)'
        printf "%-16s %-s\n" '-f' '安装或升级集群后, 自动部署或更新 flannel 网络'
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
        if echo "$OPTARG" | grep -Eqi '^(([0-9]{1,3}\.){3}[0-9]{1,3}[[:space:]])*([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            remote_LOGIN_NODES="$OPTARG"
        elif [ "$OPTARG" = 'all' ] || [ "$OPTARG" = 'a' ]; then
            remote_LOGIN_NODES=all
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

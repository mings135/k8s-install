#!/usr/bin/env bash

if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "请使用 bash $0 运行脚本 ！"
  exit 1
fi

set -e
script_dir=$(dirname $(readlink -f $0))

source ${script_dir}/modules/result.sh
source ${script_dir}/config/kube.conf
source ${script_dir}/modules/check.sh


# 分发文件到所有节点
remote_distribute() {
  for i in ${all_nodes}
  do
    if ! ssh root@${i} test -f ${INSTALL_SCRIPT}/config/record.txt; then
      # 删除原目录，然后分发文件
      ssh root@${i} rm -rf ${INSTALL_SCRIPT}
      scp -r ${script_dir} root@${i}:${INSTALL_SCRIPT}
      # 删除不必要的文件
      ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh needless
      # 创建记录
      ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh record
    fi
  done
}


# 更新所有节点上 config/nodes.conf 和 /etc/hosts
remote_hosts() {
  for i in ${all_nodes}
  do
    scp ${script_dir}/config/nodes.conf root@${i}:${INSTALL_SCRIPT}/config
    ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh hosts
  done
}


# 初始化、优化所有节点
remote_init() {
  python3 ${script_dir}/script/concurrent.py "bash ${INSTALL_SCRIPT}/local.sh init" ${all_nodes}
}


# 所有节点安装 cri
remote_cri() {
  python3 ${script_dir}/script/concurrent.py "bash ${INSTALL_SCRIPT}/local.sh cri" ${all_nodes}
}


# 所有节点安装 kubeadm 等
remote_k8s() {
  python3 ${script_dir}/script/concurrent.py "bash ${INSTALL_SCRIPT}/local.sh k8s" ${all_nodes}
}


# 所有节点依次执行 hosts、init、cri、k8s
remote_all() {
  python3 ${script_dir}/script/concurrent.py "bash ${INSTALL_SCRIPT}/local.sh all" ${all_nodes}
}


# 查看所需镜像列表
remote_imglist() {
  local random_master=$(echo -e "${master_nodes}" | grep -v '^ *$' | sort --random-sort | head -n 1)
  ssh root@${random_master} bash ${INSTALL_SCRIPT}/local.sh imglist
}


# pull 所需的 k8s 镜像
remote_imgpull() {
  python3 ${script_dir}/script/concurrent.py "bash ${INSTALL_SCRIPT}/local.sh imgpull" ${all_nodes}
}


# 初始化集群
remote_initcluster() {
  ssh root@${node_m1} bash ${INSTALL_SCRIPT}/local.sh initcluster
}


# 获取加入集群的命令，并写入 config/join.conf
remote_joincmd() {
  ssh root@${node_m1} bash ${INSTALL_SCRIPT}/local.sh joincmd
  sleep 1
  scp -r root@${node_m1}:${INSTALL_SCRIPT}/config/join.conf ${script_dir}/config
  sleep 1
  for i in ${all_nodes}
  do
    scp -r ${script_dir}/config/join.conf root@${i}:${INSTALL_SCRIPT}/config
  done
}


remote_joincluster() {
  for i in ${all_nodes}
  do
    ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh joincluster
  done
}


# 本地创建 3 张 CA 证书，分发到各个节点
remote_ca() {
  bash ${script_dir}/local.sh ca
  for i in ${all_nodes}
  do
    ssh root@${i} rm -rf ${INSTALL_SCRIPT}/pki
    scp -r ${script_dir}/pki root@${i}:${INSTALL_SCRIPT}/pki
  done
}


# 所有 master 节点签发 k8s 证书
remote_certs() {
  for i in ${all_nodes}
  do
    ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh certs
  done
}


# 所有节点签发 kubelet 证书
remote_kubelet() {
  for i in ${all_nodes}
  do
    ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh kubelet
  done
}


# 删除非 master 节点上的 pki 目录
remote_delpki() {
  for i in ${all_nodes}
  do
    ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh delpki
  done
}


# 删除记录 record.txt
remote_delrecord() {
  for i in ${all_nodes}
  do
    ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh delrecord
  done
}


# 获取所有节点信息 all_nodes node_m1 master_nodes
get_nodes_info() {
  local node_ip node_role
  all_nodes=''
  master_nodes=''
  node_m1=''

  while read line
  do
    if echo "${line}" | grep -Eqi '^ *#|^ *$'; then
      continue
    fi
    check_node_line "${line}"

    node_ip=$(echo "${line}" | awk -F '=' '{print $2}')
    all_nodes="${all_nodes} ${node_ip}"

    node_role=$(echo "${line}" | awk -F '=' '{print $3}')
    if echo "${node_role}" | grep -Eqi '^m'; then
      master_nodes="${master_nodes}\n${node_ip}"
      if [ "${node_role}" = 'm1' ]; then
        node_m1="${node_ip}"
      fi
    fi
  done < ${script_dir}/config/nodes.conf

  if [ ! ${node_m1} ]; then
    yellow_font "nodes.conf 中必须存在 m1，并且唯一，须修改配置！"
    exit 1
  fi
}


# 免密登录各个节点
password_free_login() {
  # 密码为空时，继续手动输入
  while [ ! ${NODE_PASSWORD} ]
  do
    blue_font "请输入 k8s 所有节点的统一密码（root）："
    read -s NODE_PASSWORD
  done

  # 创建 ssh 密钥
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
  fi

  # 自动接受 key
  if ! grep -Eqi 'StrictHostKeyChecking no' /etc/ssh/ssh_config;then
    echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config
  fi

  # copy public key 到各个节点
  for i in ${all_nodes}
  do
    sshpass -p "${NODE_PASSWORD}" ssh-copy-id -i ~/.ssh/id_rsa.pub root@${i}
  done
}


remote_upscript() {
  local rsync_parm rsync_exclude rsync_source rsync_destination
  rsync_parm='-avc --delete'
  rsync_exclude='--exclude=/config --exclude=/.git --exclude=/pki --exclude=/kubeadm-init.log --exclude=/kubeadm-config.yaml --exclude=/remote.sh'
  rsync_source="${script_dir}/"

  for i in ${all_nodes}
  do
    blue_font "开始同步：${i}"
    rsync_destination="root@${i}:${INSTALL_SCRIPT}/"
    rsync ${rsync_parm} ${rsync_exclude} ${rsync_source} ${rsync_destination}
  done 
}


main() {
  check_script_dir
  get_nodes_info

  case $1 in
    "freelogin") password_free_login;;
    "distribute") remote_distribute;;
    "hosts") remote_hosts;;
    "init") remote_init;;
    "cri") remote_cri;;
    "k8s") remote_k8s;;
    "all") remote_all;;
    "imglist") remote_imglist;;
    "imgpull") remote_imgpull;;
    "initcluster") remote_initcluster;;
    "joincmd") remote_joincmd;;
    "joincluster") remote_joincluster;;
    "ca") remote_ca;;
    "certs") remote_certs;;
    "kubelet") remote_kubelet;;
    "delpki") remote_delpki;;
    "delrecord") remote_delrecord;;
    "upscript") remote_upscript;;
    "auto")
    remote_distribute
    remote_hosts
    remote_init
    remote_cri
    remote_k8s
    remote_ca
    remote_certs
    remote_imgpull
    remote_initcluster
    remote_joincmd
    remote_joincluster
    remote_kubelet
    remote_delpki
    ;;
    *)
    echo ''
    printf "Usage: bash $0 [ ? ] \n"
    blue_font "节点："
    printf "%-16s %-s\n" 'freelogin' '配置本机免密登录到所有 k8s 节点'
    printf "%-16s %-s\n" 'distribute' '分发项目文件到所有节点'
    printf "%-16s %-s\n" 'hosts' '所有节点：更新 config/nodes.conf；然后更新 /etc/hosts'
    printf "%-16s %-s\n" 'init' '所有节点：初始化、优化系统'
    printf "%-16s %-s\n" 'cri' '所有节点：安装容器运行时'
    printf "%-16s %-s\n" 'k8s' '所有节点：安装 kubeadm kubelet kubectl'
    printf "%-16s %-s\n" 'all' '所有节点：顺序执行：hosts -> init -> cri --> k8s'
    blue_font "集群："
    printf "%-16s %-s\n" 'imglist' '查看 kubeadm init images'
    printf "%-16s %-s\n" 'imgpull' '所有 master 节点：拉取 kubeadm init images'
    printf "%-16s %-s\n" 'initcluster' 'master 1 上 kubeadm init cluster'
    printf "%-16s %-s\n" 'joincmd' '获取加入集群的命令，写入 config/join.conf，分发到各个节点'
    printf "%-16s %-s\n" 'joincluster' '所有节点：kubeadm join cluster'
    blue_font "证书："
    printf "%-16s %-s\n" 'ca' '本地创建 ca 证书（pki 目录，不会覆盖），并分发到各个节点'
    printf "%-16s %-s\n" 'certs' "所有 master 节点：签发 k8s 证书，此操作会清空 ${K8S_PKI}！"
    printf "%-16s %-s\n" 'kubelet' '所有节点：签发 kubelet 证书，此操作会覆盖原有证书！'
    blue_font "其他："
    printf "%-16s %-s\n" 'auto' '全自动安装，并签发自定义证书'
    printf "%-16s %-s\n" 'upscript' '更新 k8s-install 脚本版本到各个节点'
    printf "%-16s %-s\n" 'delpki' '所有非 master：删除不需要的目录 pki，集群安装完成后可以删除'
    printf "%-16s %-s\n" 'delrecord' '所有节点：删除 config/record.txt；被记录的步骤不能重复执行'
    exit 1
    ;;
  esac
}


main $1
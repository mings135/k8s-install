#!/usr/bin/env bash

if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "请使用 bash $0 运行脚本!"
  exit 1
fi

set -e
script_dir=$(dirname $(readlink -f $0))
parent_dir=$(dirname ${script_dir})

source ${parent_dir}/config/kube.conf


password_free_login() {
  # 配置文件密码为空时，手动输入
  while [ ! ${NODE_PASSWORD} ]
  do
    echo "请输入 LBHA 所有节点的统一密码（root）："
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
  for i in ${LBHA_NODES}
  do
    sshpass -p "${NODE_PASSWORD}" ssh-copy-id -i ~/.ssh/id_rsa.pub root@${i}
  done
}


# 分发文件到所有节点
remote_distribute() {
  for i in ${LBHA_NODES}
  do
    # 删除原目录，然后分发文件
    ssh root@${i} rm -rf ${INSTALL_SCRIPT}
    scp -r ${parent_dir} root@${i}:${INSTALL_SCRIPT}

    # 伪造信息
    ssh root@${i} bash ${INSTALL_SCRIPT}/lbha/local.sh forge
  done
}


remote_docker() {
  python3 ${parent_dir}/script/concurrent.py "bash ${INSTALL_SCRIPT}/local.sh needless record init cri" ${LBHA_NODES}
}


remote_lbha() {
  local lbha_keepalive=false
  local lbha_node_num=$(echo ${LBHA_NODES} | tr ' ' '\n' | wc -l)

  if [ ${lbha_node_num} -gt 1 ]; then
    lbha_keepalive=true
  fi

  for i in ${LBHA_NODES}
  do
    # 安装 compose
    ssh root@${i} bash ${INSTALL_SCRIPT}/local.sh compose
    # 执行安装 nginx keepalive
    ssh root@${i} bash ${INSTALL_SCRIPT}/lbha/local.sh nginx
    if ${lbha_keepalive}; then
      ssh root@${i} bash ${INSTALL_SCRIPT}/lbha/local.sh keepalive
    fi
    # 清理不需要的
    ssh root@${i} bash ${INSTALL_SCRIPT}/lbha/local.sh cleanup
  done
}


main() {
  case $1 in
    "freelogin") password_free_login;;
    "distribute") remote_distribute;;
    "docker") remote_docker;;
    "lbha") remote_lbha;;
    "auto")
      remote_distribute
      remote_docker
      remote_lbha
      ;;
    *) exit 1;;
  esac
}


main $1
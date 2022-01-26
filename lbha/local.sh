#!/usr/bin/env bash

if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "请使用 bash $0 运行脚本!"
  exit 1
fi

set -e
script_dir=$(dirname $(readlink -f $0))
parent_dir=$(dirname ${script_dir})

source ${parent_dir}/config/kube.conf


local_nginx() {
  source ${script_dir}/nginx.sh
  nginx_config
  nginx_down
  nginx_up
}


local_keepalive() {
  source ${script_dir}/keepalive.sh
  keepalived_config
  keepalived_down
  keepalived_up
}


# 清理所有不需要的
local_cleanup() {
  for i in $(ls ${parent_dir})
  do
    if [ $i != 'lbha' ]; then
      rm -rf ${parent_dir}/${i}
    fi
  done

  for i in $(ls ${script_dir})
  do
    if [ $i != 'nginx' ] && [ $i != 'keepalive' ]; then
      rm -rf ${script_dir}/${i}
    fi
  done
}


local_forge() {
  forge_info="$(hostname)=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')=forge"
  if ! grep -Eqi "${forge_info}" ${parent_dir}/config/nodes.conf; then
    echo "${forge_info}" >> ${parent_dir}/config/nodes.conf
  fi 
  sed -i '/^K8S_CRI=/c K8S_CRI="docker"' ${parent_dir}/config/kube.conf
}


main() {
  case $1 in
    "forge") local_forge;;
    "nginx") local_nginx;;
    "keepalive") local_keepalive;;
    "cleanup") local_cleanup;;
    *) exit 1;;
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

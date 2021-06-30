#!/usr/bin/env bash

script_dir=$(dirname $(readlink -f $0))

source ${script_dir}/config/kube.conf
source ${script_dir}/script/calculation.sh
source ${script_dir}/script/kubelet.sh


check_record

[ $(grep 'issue_kubelet' ${script_dir}/config/record.txt | wc -l) -ne 0 ] || {
  kubelet_conf_crt
  systemctl restart kubelet
  # 添加记录
  echo "issue_kubelet" >> ${script_dir}/config/record.txt
}
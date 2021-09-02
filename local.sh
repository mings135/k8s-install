#!/usr/bin/env bash

script_dir=$(dirname $(readlink -f $0))
source ${script_dir}/config/kube.conf
source ${script_dir}/script/calculation.sh
source ${script_dir}/modules/result.sh


make_config() {
  check_record

  # 检查是否需要 make config
  [ $(grep 'make_config' ${script_dir}/config/record.txt | wc -l) -eq 0 ] || exit 0

  if [ ${IS_MASTER} == 'y' ];then
    export HOST_IP HOST_NAME CLUSTER_VIP CLUSTER_PORT K8S_VERSION POD_NETWORK SVC_NETWORK IMAGE_REPOSITORY
    envsubst < ${script_dir}/config_template/kubeadm-config.yaml > ${script_dir}/kubeadm-config.yaml
    result_msg "生成 kubeadm-config.yaml"
    # 1.22 版本以上修改部分配置
    ver="${K8S_VERSION}"
    if [ $(echo "${ver:0:4} >= 1.22" | bc) -eq 1 ]; then
      sed -i '/type: CoreDNS/d' ${script_dir}/kubeadm-config.yaml
      sed -i '/dns:/s/dns:/dns: {}/' ${script_dir}/kubeadm-config.yaml
      sed -i 's#kubeadm\.k8s\.io/v1beta2#kubeadm\.k8s\.io/v1beta3#' ${script_dir}/kubeadm-config.yaml
      result_msg "修改 >1.22 版本 kubeadm-config"
    fi
  fi

  # 添加记录
  echo "make_config" >> ${script_dir}/config/record.txt

  [ $(grep 'make_config_containerd' ${script_dir}/config/record.txt | wc -l) -eq 0 ] || exit 0

  if [ ${IS_MASTER} == 'y' ] && [ ${K8S_CRI} == 'containerd' ];then
    sed -i '/criSocket/s#/var/run/dockershim.sock#unix:///run/containerd/containerd.sock#' ${script_dir}/kubeadm-config.yaml && \
    result_msg "修改 kubeadm-config containerd" && echo "make_config_containerd" >> ${script_dir}/config/record.txt
  fi
}


initial_node() {
  check_record
  source ${script_dir}/modules/initial.sh
  source ${script_dir}/modules/install.sh

  # 检查是否需要 centos7_initial
  [ $(grep 'initial_centos' ${script_dir}/config/record.txt | wc -l) -ne 0 ] || {
    initial_centos
    # 添加记录
    echo "initial_centos" >> ${script_dir}/config/record.txt
  }

  if [ ${K8S_CRI} == 'containerd' ];then
    [ $(grep 'install_containerd' ${script_dir}/config/record.txt | wc -l) -ne 0 ] || {
      install_containerd
      # 添加记录
      echo "install_containerd" >> ${script_dir}/config/record.txt
    }
  elif [ ${K8S_CRI} == 'docker' ]; then
    [ $(grep 'install_docker' ${script_dir}/config/record.txt | wc -l) -ne 0 ] || {
      install_docker
      # 添加记录
      echo "install_docker" >> ${script_dir}/config/record.txt
    }
  fi

  [ $(grep 'install_kubeadm' ${script_dir}/config/record.txt | wc -l) -ne 0 ] || {
    install_kubeadm
    # 添加记录
    echo "install_kubeadm" >> ${script_dir}/config/record.txt
  }
  result_msg "完成初始化节点" || exit 1
}


issue_certs() {
  check_record
  source ${script_dir}/script/certs.sh

  [ $(grep 'issue_certs' ${script_dir}/config/record.txt | wc -l) -ne 0 ] || {
    # 复制 CA
    mkdir -p ${K8S_PKI}
    rm -rf ${K8S_PKI}
    /usr/bin/cp -a ${INSTALL_SCRIPT}/pki ${K8S_PKI}

    etcd_crt
    apiserver_crt
    front_crt
    admin_conf
    manager_conf
    scheduler_conf
    # 添加记录
    echo "issue_certs" >> ${script_dir}/config/record.txt
  }
}


issue_kubelet() {
  check_record
  source ${script_dir}/script/kubelet.sh

  [ $(grep 'issue_kubelet' ${script_dir}/config/record.txt | wc -l) -ne 0 ] || {
    kubelet_conf_crt
    systemctl restart kubelet
    # 添加记录
    echo "issue_kubelet" >> ${script_dir}/config/record.txt
  }
}


update_hosts() {
  master_number=${#MASTER_NODES[@]}
  work_number=${#WORK_NODES[@]}

  if [ ${INITIAL_HOSTS} == 'y' ];then
    echo '127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4' > /etc/hosts
    echo '::1         localhost localhost.localdomain localhost6 localhost6.localdomain6' >> /etc/hosts
  fi

  [ ${master_number} -ge 1 ] || exit 1
  for i in `seq 0 $[master_number - 1]`
  do
    [ $(grep "${MASTER_NODES[$i]}" /etc/hosts | wc -l) -ne 0 ] || {
      echo "${MASTER_NODES[$i]} ${MASTER_NAMES[$i]}" >> /etc/hosts
      result_msg "添加 ${MASTER_NODES[$i]} ${MASTER_NAMES[$i]}"
    }
  done

  if [ ${work_number} -ge 1 ];then
    for i in `seq 0 $[work_number - 1]`
    do
      [ $(grep "${WORK_NODES[$i]}" /etc/hosts | wc -l) -ne 0 ] || {
        echo "${WORK_NODES[$i]} ${WORK_NAMES[$i]}" >> /etc/hosts
        result_msg "添加 ${WORK_NODES[$i]} ${WORK_NAMES[$i]}"
      }
    done
  fi
}


scp_check() {
  rm -f ${script_dir}/remote.sh
  result_msg "删除所有 node 上的 remote 脚本" || exit 1

  if [ -d ${script_dir}/.git ];then
    rm -rf ${script_dir}/.git
    result_msg "删除所有 node 上的 .git" || exit 1
  fi

  [ ${IS_MASTER} == 'y' ] || {
    rm -rf ${script_dir}/pki
    result_msg "删除非 master 节点上的 pki" || exit 1
  }
}


main() {
  case $1 in
    "make_config" ) make_config;;
    "initial_node" ) initial_node;;
    "issue_certs" ) issue_certs;;
    "issue_kubelet" ) issue_kubelet;;
    "update_hosts" ) update_hosts;;
    "scp_check" ) scp_check;;
    * )
    exit 1
    ;;
  esac
}


main $1
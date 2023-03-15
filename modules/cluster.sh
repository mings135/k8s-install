# 集群操作


# 显示所需 images
cluster_images_list() {
  kubeadm config --config ${script_dir}/config/kubeadm-config.yaml images list
  result_msg "查看 images list"
}


# 拉取所需 images
cluster_images_pull() {
  kubeadm config --config ${script_dir}/config/kubeadm-config.yaml images pull
  result_msg "拉取 images"
}


# 初始化集群
cluster_master1_init() {
  kubeadm init --config ${script_dir}/config/kubeadm-config.yaml --upload-certs | tee ${script_dir}/kubeadm-init.log
  result_msg "创建 cluster"
  cluster_config_kubectl_command
}


# 如果 join 信息失效, 生成新的 join 信息
cluster_generate_join_command() {
  if ! cluster_join_token_valid; then
    local command_basic command_control token_timestamp
    command_basic="$(kubeadm token create --print-join-command)" \
      && command_control="--control-plane --certificate-key $(kubeadm init phase upload-certs --upload-certs 2> /dev/null | sed -n '$p')" \
      && token_timestamp="$(date '+%s')" \
      && echo "join_command_basic='${command_basic}'" > ${script_dir}/config/join.sh \
      && echo "join_command_control='${command_control}'" >> ${script_dir}/config/join.sh \
      && echo "join_token_timestamp='${token_timestamp}'" >> ${script_dir}/config/join.sh
    result_msg "生成 new join.sh"
  fi
}


# 加入集群
cluster_join_cluster() {
  source ${script_dir}/config/join.sh
  result_msg "加载 join 信息"
  if [ ${HOST_ROLE} = "master" ]; then
    result_blue_font "${join_command_basic} ${join_command_control}"
    ${join_command_basic} ${join_command_control}
    result_msg "加入 cluster 成为 master"
    cluster_config_kubectl_command
  elif [ ${HOST_ROLE} = "work" ]; then
    ${join_command_basic}
    result_msg "加入 cluster 成为 work"
  fi
}


# 同步更新 .kube/config, 并安装命令自动补全
cluster_config_kubectl_command() {
  mkdir -p $HOME/.kube \
    && /bin/cp ${KUBEADM_CONFIG}/admin.conf $HOME/.kube/config \
    && chmod 700 $HOME/.kube/config
  result_msg "配置 kubectl config"

  install_apps "bash-completion"
  mkdir -p /etc/bash_completion.d \
    && kubectl completion bash > /etc/bash_completion.d/kubectl
  result_msg "添加 命令自动补全"
}


# 判断 join 信息是否有效(默认有效期 2 小时)
cluster_join_token_valid() {
  if [ -e ${script_dir}/config/join.sh ]; then
    source ${script_dir}/config/join.sh
    result_msg "加载 join 信息"

    local current_timestamp=$(date '+%s')
    local run_interval=$(( current_timestamp - join_token_timestamp ))
    
    [ ${run_interval} -le ${JOIN_TOKEN_INTERVAL} ] && return 0 || return 1
  else
    return 1
  fi
}

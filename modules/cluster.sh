# 集群操作，提供以下函数：
# kubectl_config
# cluster_hosts
# images_list
# images_pull
# cluster_init
# cluster_join
# jointoken_valid


# 更新 /etc/hosts 配置
cluster_hosts() {
  local node_name node_ip

  if ${RESET_HOSTS}; then
    echo '127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4' > /etc/hosts
    echo '::1         localhost localhost.localdomain localhost6 localhost6.localdomain6' >> /etc/hosts
  fi

  while read line
  do
    if echo "${line}" | grep -Eqi '^ *#|^ *$'; then
      continue
    fi

    node_name=$(echo "${line}" | awk -F '=' '{print $1}')
    node_ip=$(echo "${line}" | awk -F '=' '{print $2}')
    if ! grep -Eqi "${node_ip} ${node_name}" /etc/hosts; then
      echo "${node_ip} ${node_name}" >> /etc/hosts
      result_msg "添加 hosts: ${node_ip}" || exit 1
    fi
  done < ${script_dir}/config/nodes.conf
}


images_list() {
  if ${IS_MASTER} && [ -f ${script_dir}/kubeadm-config.yaml ]; then
    kubeadm config --config ${script_dir}/kubeadm-config.yaml images list || exit 1
  fi
}


images_pull() {
  if ${IS_MASTER} && [ -f ${script_dir}/kubeadm-config.yaml ]; then
    kubeadm config --config ${script_dir}/kubeadm-config.yaml images pull
    result_msg "拉取 images" || exit 1
  else
    exit 0
  fi
}


cluster_init() {
  if ${IS_MASTER} && ${IS_MASTER_1} && [ -f ${script_dir}/kubeadm-config.yaml ]; then
    kubeadm init --config ${script_dir}/kubeadm-config.yaml --upload-certs | tee ${script_dir}/kubeadm-init.log
    result_msg "创建 cluster" || exit 1
  else
    exit 0
  fi 
}


kubectl_config() {
  if [ -f ${K8S_CONFIG}/admin.conf ] && [ ! -f $HOME/.kube/config ]; then
    mkdir -p $HOME/.kube && \
    /bin/cp ${K8S_CONFIG}/admin.conf $HOME/.kube/config && \
    chmod 700 $HOME/.kube/config
    result_msg "配置 kubectl config" || exit 1
  fi
}


jointoken_valid() {
  source ${script_dir}/config/join.conf || exit 1

  local current_timestamp=$(date '+%s')
  local run_interval=$[ current_timestamp - token_timestamp ]
  
  [ ${run_interval} -le ${token_interval} ] && return 0 || return 1
}


cluster_joincmd() {
  if ! jointoken_valid; then
    local join_command control_append certs_key token_timestamp
    join_command=$(kubeadm token create --print-join-command) || exit 1
    certs_key=$(kubeadm init phase upload-certs --upload-certs 2> /dev/null | sed -n '$p') || exit 1
    control_append="--control-plane --certificate-key ${certs_key}"
    token_timestamp=$(date '+%s') || exit 1

    sed -e "/join_command=/c join_command='${join_command}'" \
      -e "/control_append=/c control_append='${control_append}'" \
      -e "/token_timestamp=/c token_timestamp=${token_timestamp}" \
      -i ${script_dir}/config/join.conf
    result_msg "重写 join.conf" || exit 1
  else
    exit 0
  fi
}


cluster_join() {
  if jointoken_valid; then
    if ${IS_MASTER}; then
      ${join_command} \
      ${control_append}
      result_msg "加入 cluster 成为 master" || exit 1
    else
      ${join_command}
      result_msg "加入 cluster 成为 work" || exit 1
    fi
  fi
}
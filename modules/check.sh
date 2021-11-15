# 检查 config/nodes.conf domain and ip 是否合法
check_node_line() {
  local line="$1"

  local node_name node_ip
  node_name=$(echo "${line}" | awk -F '=' '{print $1}')
  node_ip=$(echo "${line}" | awk -F '=' '{print $2}')

  if ! echo "${node_name}" | grep -Eqi '[a-Z].*'; then
    yellow_font "nodes.conf 中 hostname 格式异常，格式：domain 必须字母开头 ！"
    exit 1
  fi

  if ! echo "${node_ip}" | grep -Eqi '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    yellow_font "nodes.conf 中 ip 地址格式异常 ！"
    exit 1
  fi
}


# 检查 record.txt 是否存在
check_record_exist() {
  [ -f ${script_dir}/config/record.txt ] || {
    yellow_font "record.txt 不存在，尝试执行 distribute or record !"
    exit 1
  }
}


# 检查节点 role，并得到 role 相关变量信息
check_node_role() {
  local line="$1"

  local node_role=$(echo "${line}" | awk -F '=' '{print $3}') 
  if echo "${node_role}" | grep -Eqi '^m'; then
    IS_MASTER=true
    if [ "${node_role}" = 'm1' ]; then
      IS_MASTER_1=true
    else
      IS_MASTER_1=false
    fi
  else
    IS_MASTER=false
  fi
}


check_script_dir() {
  if [ ! ${script_dir} ] || [ ! ${INSTALL_SCRIPT} ] ; then
    yellow_font "script 目录获取错误，请检查 kube.conf 或者 shell 环境 ！"
    exit 1
  fi
}
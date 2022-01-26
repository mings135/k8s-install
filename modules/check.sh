# 检查 config/nodes.conf domain and ip 是否合法
check_node_line() {
  local line="$1"

  local node_name node_ip
  node_name=$(echo "${line}" | awk -F '=' '{print $1}')
  node_ip=$(echo "${line}" | awk -F '=' '{print $2}')

  tmp="${RES_LEVEL}" && RES_LEVEL=1
  echo "${node_name}" | grep -Eqi '^[a-Z].*' && \
  echo "${node_ip}" | grep -Eqi '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  result_msg "检查 ${line} 格式"
  RES_LEVEL="${tmp}"
}


# 检查 record.txt 是否存在
check_record_exist() {
  tmp="${RES_LEVEL}" && RES_LEVEL=1
  test -f ${script_dir}/config/record.txt
  result_msg "检查 record.txt 是否存在"
  RES_LEVEL="${tmp}"
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


# 检查变量
check_script_variables() {
  tmp="${RES_LEVEL}" && RES_LEVEL=1
  test ${INSTALL_SCRIPT} && \
  test ${PRIVATE_REPOSITORY}
  result_msg "检查 variables"
  RES_LEVEL="${tmp}"
}
# 获取基础信息和基础检查
# base_check、base_info

# 全局变量
# script_dir=$(dirname $(readlink -f $0))
# 需要文件：config/nodes.conf


# 检查是否有记录文档
check_record_exists() {
  [ -f ${script_dir}/config/record.txt ] && return 0 || return 1
}


# 检查 master 节点是否存在
check_master_exists() {
  local master_nodes=0

  for line in $(cat ${script_dir}/config/nodes.conf)
  do
    if echo ${line} | grep -Eqi '^#'; then
      continue
    fi

    if [ $(echo ${line} | awk -F '=' '{print $3}') ]; then
      master_nodes=$[master_nodes + 1]
    fi
  done
  
  [ ${master_nodes} -gt 0 ] && return 0 || return 1
}


# 获取节点信息
get_node_info() {
  local node_name node_ip
  local host_ip=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')

  for line in $(cat ${script_dir}/config/nodes.conf)
  do
    if echo ${line} | grep -Eqi '^#'; then
      continue
    fi

    node_ip=$(echo ${line} | awk -F '=' '{print $2}')
    if [ "${host_ip}" = "${node_ip}" ]; then
      HOST_IP=${node_ip}
      HOST_NAME=$(echo ${line} | awk -F '=' '{print $1}')
      [ $(echo ${line} | awk -F '=' '{print $3}') ] && IS_MASTER='/bin/true' || IS_MASTER='/bin/false'
      break
    fi
  done

  [ ${HOST_IP} ] && return 0 || return 1
}


# 获取系统信息
get_system_info() {
  if [ -f /etc/redhat-release ]; then
    sys_release="centos"
    if cat /etc/redhat-release | grep -Eqi 'release 7'; then
      sys_version=7
      sys_pkg="yum"
    elif cat /etc/redhat-release | grep -Eqi 'release 8'; then
      sys_version=8
      sys_pkg="dnf"
    else
      return 1
    fi
  elif cat /etc/issue | grep -Eqi "debian"; then
    sys_release="debian"
    sys_pkg="apt-get"
    if cat /etc/issue | grep -Eqi 'linux 10'; then
      sys_version=10
    else
      return 1
    fi
  else
    return 1
}


base_check() {
  check_master_exists || exit 1
  check_record_exists || exit 1
}

base_info() {
  get_system_info || exit 1
  get_node_info || exit 1
}
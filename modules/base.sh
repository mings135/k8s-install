# 基础检查和获取基本信息，提供以下函数：
# base_info
# install_apps

# 所需变量：
# script_dir=$(dirname $(readlink -f $0))

# 必须先执行 check.sh


# 获取节点信息
get_node_info() {
  local node_ip
  local host_ip=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}') || return 1

  while read line
  do
    if echo "${line}" | grep -Eqi '^ *#|^ *$'; then
      continue
    fi
    check_node_line "${line}"

    node_ip=$(echo "${line}" | awk -F '=' '{print $2}')
    if [ ${host_ip} = ${node_ip} ]; then
      HOST_IP=${node_ip}
      HOST_NAME=$(echo "${line}" | awk -F '=' '{print $1}')
      check_node_role "${line}"
      break
    fi
  done < ${script_dir}/config/nodes.conf

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
    elif
      cat /etc/issue | grep -Eqi 'linux 11'; then
      sys_version=11
    else
      return 1
    fi
  else
    return 1
  fi
}


# 安装工具
install_apps() {
  # 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
  if [ ${sys_release} = 'debian' ]; then
    export DEBIAN_FRONTEND=noninteractive
  fi
  
  for i in $@
  do
    ${sys_pkg} install -y ${i} &> /dev/null
    result_msg "安装 $i" || return 1
  done
}


# 获取基础信息
base_info() {
  get_system_info ||  {
    yellow_font "获取 system info 出错！"
    exit 1
  }
  get_node_info ||  {
    yellow_font "获取 node info 出错！"
    exit 1
  }
}
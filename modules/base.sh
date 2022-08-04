# 基础检查和获取基本信息，提供以下函数：
# base_info
# install_apps

# 所需变量：
# script_dir=$(dirname $(readlink -f $0))

# 必须先执行 check.sh


# 获取节点信息
get_node_info() {
  local node_ip
  local host_ip=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')

  if [ ${host_ip} ]; then
    while read line
    do
      if echo "${line}" | grep -Eqi '^ *#|^ *$'; then
        continue
      fi

      node_ip=$(echo "${line}" | awk -F '=' '{print $2}')
      if [ ${host_ip} = ${node_ip} ]; then
        HOST_IP=${node_ip}
        HOST_NAME=$(echo "${line}" | awk -F '=' '{print $1}')
        check_node_role "${line}"
        break
      fi
    done < ${script_dir}/config/nodes.conf
  fi

  tmp="${RES_LEVEL}" && RES_LEVEL=1
  test ${HOST_IP}
  result_msg "获取 node info"
  RES_LEVEL="${tmp}"
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
    elif cat /etc/redhat-release | grep -Eqi 'release 9'; then
      sys_version=9
      sys_pkg="dnf"
    fi
  elif cat /etc/issue | grep -Eqi "debian"; then
    sys_release="debian"
    sys_pkg="apt-get"
    if cat /etc/issue | grep -Eqi 'linux 10'; then
      sys_version=10
    elif
      cat /etc/issue | grep -Eqi 'linux 11'; then
      sys_version=11
    fi
  fi

  tmp="${RES_LEVEL}" && RES_LEVEL=1
  test ${sys_release} && test ${sys_pkg} && test ${sys_version}
  result_msg "获取 system info"
  RES_LEVEL="${tmp}"
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
    result_msg "安装 $i"
  done
}


# 获取基础信息
base_info() {
  get_node_info
  get_system_info
}
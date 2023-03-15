#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "请使用 bash $0 运行脚本!"
  exit 1
fi

# 已经安装 rsync 直接退出
if which rsync &> /dev/null; then
  exit 0
fi


# 设置输出级别(0 or 1)
RES_LEVEL=0
RES_COL=60


if [ ! ${HOST_IP} ]; then
  HOST_IP=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')
fi


result_blue_font() {
  echo -e "\033[34m\033[01m$1\033[0m"
}


# $1 范围 0 ~ 7
result_auto_font() {
  echo -e "\033[3$1m\033[01m$2\033[0m"
}

result_action() {
  local STRING rc
  STRING=$1
  echo -n "$STRING "
  shift
  "$@" && result_echo_success || result_echo_failure
  rc=$?
  echo
  return $rc
}

result_echo_success() {
  local msg_text="success"
  echo -ne "\033[${RES_COL}G[ \033[32m\033[01m${msg_text}\033[0m ]"
  echo -ne "\r"
  return 0
}

result_echo_failure() {
  local msg_text="failure"
  echo -ne "\033[${RES_COL}G[ \033[31m\033[01m${msg_text}\033[0m ]"
  echo -ne "\r"
  return 1
}

result_msg() {
  if [ $? -eq 0 ]; then
    if [ ${RES_LEVEL} -eq 0 ]; then
      local ip_end="$(echo ${HOST_IP} | awk -F '.' '{print $NF}')"
      local ip_color=$(( ${ip_end} % 7 ))
      result_action "$(result_auto_font ${ip_color} ${HOST_IP}): $*" "/bin/true"
    fi
  else
    local ip_end="$(echo ${HOST_IP} | awk -F '.' '{print $NF}')"
    local ip_color=$(( ${ip_end} % 7 ))
    result_action "$(result_auto_font ${ip_color} ${HOST_IP}): $*" "/bin/false"
    exit 1
  fi
}


if [ -f /etc/redhat-release ]; then
  SYSTEM_RELEASE="centos"
  if cat /etc/redhat-release | grep -Eqi 'release 7'; then
    SYSTEM_PACKAGE="yum"
  else
    SYSTEM_PACKAGE="dnf"
  fi
elif cat /etc/issue | grep -Eqi "debian"; then
  SYSTEM_RELEASE="debian"
  SYSTEM_PACKAGE="apt-get"
fi

# 检查变量，异常显示
RES_LEVEL=1 && test ${SYSTEM_RELEASE} && test ${SYSTEM_PACKAGE}
result_msg "获取 system variables" && RES_LEVEL=0


# 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
if [ ${SYSTEM_RELEASE} = 'debian' ]; then
  export DEBIAN_FRONTEND=noninteractive
fi

${SYSTEM_PACKAGE} install -y rsync > /dev/null
result_msg "安装 rsync"

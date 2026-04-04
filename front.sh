#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
  echo "请使用 bash $0 运行脚本!"
  exit 1
fi

# 已经安装 rsync 直接退出
if command -v rsync &>/dev/null; then
  exit 0
fi

RES_LEVEL=0
RES_COLUM=50

if [[ -f /etc/debian_version ]]; then
  OS_NAME="debian"
  export DEBIAN_FRONTEND=noninteractive
fi

const_action() {
  local result rc color
  local msg=$1

  shift
  if "$@"; then
    result="success"
    rc=0
    color=32
  else
    result="failure"
    rc=1
    color=31
  fi
  printf "%-${RES_COLUM}s [ \033[%sm\033[01m%s\033[0m ]\n" "$msg" "$color" "$result"
  return $rc
}

# 执行结果捕获
result_msg() {
  local rc=$?
  if [[ ${rc} -eq 0 ]]; then
    if [[ ${RES_LEVEL} -eq 0 ]]; then
      const_action "$*" "/bin/true"
    fi
  else
    const_action "$*" "/bin/false"
    exit 1
  fi
}

# 检查变量，异常显示
RES_LEVEL=1 && [[ -n "${OS_NAME}" ]]
result_msg "检查 system variables" && RES_LEVEL=0

apt-get install -y rsync &>/dev/null
result_msg "安装 rsync"

# 格式化输出结果，提供以下函数：
# result_msg


RES_COL=60

if [ ! ${HOST_IP} ];then
  HOST_IP='127.0.0.1'
fi

yellow_font() {
  echo -e "\033[33m\033[01m$1\033[0m"
}


blue_font() {
  echo -e "\033[34m\033[01m$1\033[0m"
}


# $1 范围 0 ~ 7
auto_font() {
  echo -e "\033[3$1m\033[01m$2\033[0m"
}

action() {
  local STRING rc
  STRING=$1
  echo -n "$STRING "
  shift
  "$@" && echo_success || echo_failure
  rc=$?
  echo
  return $rc
}

echo_success() {
  local msg_text="success"
  echo -ne "\033[${RES_COL}G[ \033[32m\033[01m${msg_text}\033[0m ]"
  echo -ne "\r"
  return 0
}

echo_failure() {
  local msg_text="failure"
  echo -ne "\033[${RES_COL}G[ \033[31m\033[01m${msg_text}\033[0m ]"
  echo -ne "\r"
  return 1
}

result_msg() {
  if [ $? -eq 0 ];then
    local ip_end="$(echo ${HOST_IP} | awk -F '.' '{print $NF}')"
    local ip_color=$(( ${ip_end} % 7 ))
    action "$(auto_font ${ip_color} ${HOST_IP}): $*" "/bin/true"
  else
    local ip_end="$(echo ${HOST_IP} | awk -F '.' '{print $NF}')"
    local ip_color=$(( ${ip_end} % 7 ))
    action "$(auto_font ${ip_color} ${HOST_IP}): $*" "/bin/false"
  fi
}
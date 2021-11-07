# 格式化输出结果

RES_COL=48

if [ ! ${HOST_IP} ];then
  HOST_IP='127.0.0.1'
fi

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
  local ip_end="$(echo ${HOST_IP} | gawk -F '.' '{print $NF}')"
  local ip_color=$(( ${ip_end} % 7 ))
  if [ $? -eq 0 ];then
    action "$(auto_font ${ip_color} ${HOST_IP}): $*" "/bin/true"
  else
    action "$(auto_font ${ip_color} ${HOST_IP}): $*" "/bin/false"
  fi
}
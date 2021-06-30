# 格式化输出

BOOTUP=color
RES_COL=48
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

yellow_font() {
  echo -e "\033[33m\033[01m$1\033[0m"
}

green_font() {
   echo -e "\033[32m\033[01m$1\033[0m"
}

red_font() {
   echo -e "\033[31m\033[01m$1\033[0m"
}

pink_font() {
   echo -e "\033[35m\033[01m$1\033[0m"
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
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "[ "
  [ "$BOOTUP" = "color" ] && $SETCOLOR_SUCCESS
  echo -n $"success"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n " ]"
  echo -ne "\r"
  return 0
}

echo_failure() {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "[ "
  [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
  echo -n $"failure"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n " ]"
  echo -ne "\r"
  return 1
}

result_msg()
{
  if [ $? -eq 0 ];then
    action "$(green_font ${HOST_IP}): $*" "/bin/true"
  else
    action "$(red_font ${HOST_IP}): $*" "/bin/false"
  fi
}
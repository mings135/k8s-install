
################## 自动计算    ##################
ALL_NODES=(${MASTER_NODES[@]} ${WORK_NODES[@]})

host_ip=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')
master_number=${#MASTER_NODES[@]}
work_number=${#WORK_NODES[@]}

IS_MASTER='n'
IS_WORK='n'
HOST_IP='127.0.0.2'

[ ${master_number} -ge 1 ] || exit 1
for i in `seq 0 $[master_number - 1]`
do
  [ "${host_ip}" == "${MASTER_NODES[$i]}" ] && {
    HOST_IP="${host_ip}"
    HOST_NAME="${MASTER_NAMES[$i]}"
    IS_MASTER='y'
    break
  }
done

if [ ${work_number} -ge 1 ];then
  for i in `seq 0 $[work_number - 1]`
  do
    [ "${host_ip}" == "${WORK_NODES[$i]}" ] && {
      HOST_IP="${host_ip}"
      HOST_NAME="${WORK_NAMES[$i]}"
      IS_WORK='y'
      break
    }
  done
fi


check_record() {
  # 报错
  [ -f ${script_dir}/config/record.txt ] || {
    red_font "ERROR：没有 record.txt 文件，必须先分发安装脚本！"
    exit 1
  }
}
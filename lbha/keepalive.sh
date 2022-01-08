keepalived_config() {
  interface_ip=$(ip a | grep global | awk -F '/' '{print $1}' | awk 'NR==1{print $2}')
  interface_name=$(ip a | grep global | awk 'NR==1{print $NF}')
  interface_priority=$(echo ${interface_ip} | awk -F '.' '{print $NF}')
  
  export interface_ip interface_name interface_priority CLUSTER_PORT CLUSTER_VIP
  envsubst < ${script_dir}/keepalive/keepalived.conf.temp > ${script_dir}/keepalive/keepalived.conf
  chmod 755 ${script_dir}/keepalive/check_port.sh
}


keepalived_up() {
  cd ${script_dir}/keepalive
  docker-compose up -d
}


keepalived_down() {
  cd ${script_dir}/keepalive
  docker-compose down
}

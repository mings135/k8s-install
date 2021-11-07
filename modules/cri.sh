centos_repo() {
  # yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo &> /dev/null
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null
  result_msg "添加 docker repo" || return 1
  sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
  result_msg "修改 docker repo" || return 1
}

debian_repo() {

}

install_docker() {

}

install_containerd() {
    
}
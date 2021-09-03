# 初始化系统等

# initial_centos： centos 系统初始化（支持 7 和 8）
#MODIFY_YUM='y'
#HOST_NAME='localhost'
#INSTALL_TOOLS=('net-tools' 'nfs-utils' 'ipvsadm' 'chrony' 'yum-utils' 'device-mapper-persistent-data' 'lvm2' 'bc')


initial_centos() {
  [ ${MODIFY_YUM} == 'y' ] && {
    if cat /etc/redhat-release | grep -Eqi 'release 8';then
      yum install -y epel-release &> /dev/null
      result_msg "安装 epel" || exit 1
      yum clean all &> /dev/null && yum makecache &> /dev/null
      result_msg "重置 yum cache" || exit 1
    else
      curl -fsSL https://mirrors.aliyun.com/repo/Centos-7.repo -o /etc/yum.repos.d/CentOS-Base.repo
      result_msg "下载阿里 base repo" || exit 1
      curl -fsSL http://mirrors.aliyun.com/repo/epel-7.repo -o /etc/yum.repos.d/epel.repo
      result_msg "下载阿里 epel repo" || exit 1
      yum clean all &> /dev/null && yum makecache &> /dev/null
      result_msg "重置 yum cache" || exit 1
    fi
  }

  [ ${HOST_NAME} ] && [ ${HOST_NAME} != $(hostname) ] && {
    hostnamectl set-hostname "${HOST_NAME}"
    result_msg "设置 hostname ${HOST_NAME}" || exit 1
  }

  cat /etc/ssh/sshd_config | grep -Eqi 'GSSAPIAuthentication yes|#UseDNS yes' && {
    sed -i '/GSSAPIAuthentication/s/GSSAPIAuthentication yes/GSSAPIAuthentication no/' /etc/ssh/sshd_config
    sed -i '/UseDNS/s/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
    systemctl restart sshd
    result_msg "关闭 sshd dns config" || exit 1
  }

  cat /etc/selinux/config | grep -Eqi 'SELINUX=enforcing' && {
    sed -i '/SELINUX=enforcing/s/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config && setenforce 0
    result_msg "关闭 selinux" || exit 1
  }

  for i in "${INSTALL_TOOLS[@]}"
  do
    yum install -y ${i} &> /dev/null
    result_msg "安装 $i"
  done

  systemctl disable --now firewalld &> /dev/null
  result_msg "停止 firewalld" || exit 1

  [ $(cat /etc/security/limits.conf | grep nofile | grep 65535 | wc -l) -eq 0 ] && {
    echo '*   -   nofile   65536' >> /etc/security/limits.conf
    result_msg '修改 limit file' || exit 1
  }

  cat > /etc/chrony.conf << EOF
# 阿里官方的配置文件
server ntp.aliyun.com iburst
stratumweight 0
driftfile /var/lib/chrony/drift
rtcsync
makestep 10 3
bindcmdaddress 127.0.0.1
bindcmdaddress ::1
keyfile /etc/chrony.keys
commandkey 1
generatecommandkey
logchange 0.5
logdir /var/log/chrony
EOF
  systemctl enable --now chronyd &> /dev/null
  result_msg '启动 chronyd' || exit 1
}


initial_debain() {
  echo "build ..."
}
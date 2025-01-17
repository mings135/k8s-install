# 集群操作

# 显示所需 images
cluster_images_list() {
    kubeadm config --config ${script_dir}/config/kubeadm-config.yaml images list
    result_msg "查看 images list"
}

# 拉取所需 images
cluster_images_pull() {
    kubeadm config --config ${script_dir}/config/kubeadm-config.yaml images pull
    result_msg "拉取 images"
}

# 初始化集群
cluster_master1_init() {
    systemctl daemon-reload && systemctl restart kubelet
    result_msg "重启 重载 kubelet"
    kubeadm init --config ${script_dir}/config/kubeadm-config.yaml --upload-certs
    result_msg "创建 cluster"
    cluster_config_kubectl_command
}

# 如果 join token 失效, 生成新的 join token
cluster_generate_join_command() {
    if ! cluster_join_token_valid; then
        local command_basic command_control token_timestamp
        command_basic="$(kubeadm token create --print-join-command)" &&
            command_control="--control-plane --certificate-key $(kubeadm init phase upload-certs --upload-certs 2>/dev/null | sed -n '$p')" &&
            token_timestamp="$(date '+%s')" &&
            echo "join_command_basic='${command_basic}'" >${script_dir}/config/join.sh &&
            echo "join_command_control='${command_control}'" >>${script_dir}/config/join.sh &&
            echo "join_token_timestamp='${token_timestamp}'" >>${script_dir}/config/join.sh &&
            chown ${SCRIPT_OWN}:${SCRIPT_OWN} ${script_dir}/config/join.sh
        result_msg "生成 new join.sh"
    fi
}

# 加入集群
cluster_join_cluster() {
    source ${script_dir}/config/join.sh
    result_msg "加载 join 信息"
    systemctl daemon-reload && systemctl restart kubelet
    result_msg "重启 重载 kubelet"
    if [ ${HOST_ROLE} = "master" ]; then
        blue_font "${join_command_basic} ${join_command_control}"
        ${join_command_basic} ${join_command_control}
        result_msg "加入 cluster 成为 master"
        cluster_config_kubectl_command
    elif [ ${HOST_ROLE} = "work" ]; then
        ${join_command_basic}
        result_msg "加入 cluster 成为 work"
    fi
}

# 集群升级 kubeadm 和核心组件版本
cluster_upgrade_version_kubeadm() {
    if [ ${SYSTEM_RELEASE} = 'centos' ]; then
        install_apps "kubeadm-${upgradeVersion}" '--disableexcludes=kubernetes'
        result_msg "升级 kubeadm"
    elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
        apt-mark unhold kubeadm &&
            install_apps "kubeadm=${upgradeVersion}" &&
            apt-mark hold kubeadm
        result_msg "升级 kubeadm"
    fi

    if [ "${HOST_ROLE}" = "master1" ]; then
        kubeadm upgrade plan v${upgradeVersion}
        result_msg "检查 集群是否可被升级"
        kubeadm upgrade apply v${upgradeVersion} -y --certificate-renewal=${kubeadmSignCertificate}
        result_msg "升级 master1 上各个容器组件"
    elif [ "${HOST_ROLE}" = "master" ]; then
        kubeadm upgrade node --certificate-renewal=${kubeadmSignCertificate}
        result_msg "升级 master 上各个容器组件"
    elif [ "${HOST_ROLE}" = "work" ]; then
        kubeadm upgrade node --certificate-renewal=${kubeadmSignCertificate}
        result_msg "升级 work 上 kubelet 配置"
    fi
}

# 集群升级 kubelet kubectl 版本
cluster_upgrade_version_kubelet() {
    kubectl drain ${HOST_NAME} --ignore-daemonsets
    result_msg "腾空 当前节点"

    if [ ${SYSTEM_RELEASE} = 'centos' ]; then
        install_apps "kubelet-${upgradeVersion} kubectl-${upgradeVersion}" '--disableexcludes=kubernetes'
        result_msg "升级 kubelet kubectl"
    elif [ ${SYSTEM_RELEASE} = 'debian' ]; then
        apt-mark unhold kubelet kubectl &&
            install_apps "kubelet=${upgradeVersion} kubectl=${upgradeVersion}" &&
            apt-mark hold kubelet kubectl
        result_msg "升级 kubelet kubectl"
    fi

    systemctl daemon-reload && systemctl restart kubelet
    result_msg "重启 重载 kubelet"

    kubectl uncordon ${HOST_NAME}
    result_msg "解除 当前节点的保护"

    kubectl wait --for=condition=Ready nodes/${HOST_NAME} --timeout=50s
    result_msg "等待 节点 Ready"
}

# 备份 etcd 数据库
cluster_backup_etcd() {
    if [ -e ${script_dir}/config/etcd-snap.db ]; then
        rm -f ${script_dir}/config/etcd-snap.db
        result_msg "清理 旧的备份 etcd 数据库快照"
    fi

    ETCDCTL_API=3 etcdctl snapshot save ${script_dir}/config/etcd-snap.db \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=${KUBEADM_PKI}/etcd/ca.crt \
        --cert=${KUBEADM_PKI}/etcd/server.crt \
        --key=${KUBEADM_PKI}/etcd/server.key &&
        chmod 644 ${script_dir}/config/etcd-snap.db &&
        chown ${SCRIPT_OWN}:${SCRIPT_OWN} ${script_dir}/config/etcd-snap.db
    result_msg "备份 etcd 数据库快照"
}

# 恢复 etcd 数据库
cluster_restore_etcd() {
    if which etcdutl &>/dev/null; then
        local tmp_command='etcdutl'
    else
        local tmp_command='etcdctl'
    fi
    RES_LEVEL=1 && test -e ${script_dir}/config/etcd-snap.db
    result_msg "检查 是否存在备份快照文件" && RES_LEVEL=0

    if [ -e ${KUBEADM_MANIFESTS}/etcd.yaml ]; then
        mv ${KUBEADM_MANIFESTS}/kube-apiserver.yaml ${script_dir}/config/kube-apiserver.yaml &&
            mv ${KUBEADM_MANIFESTS}/etcd.yaml ${script_dir}/config/etcd.yaml
        result_msg "停止 etcd 和 apiserver 服务"
        sleep 3
    fi

    if [ -e ${ETCD_DATA_DIR}.bak ] && [ -e ${ETCD_DATA_DIR} ]; then
        rm -rf ${ETCD_DATA_DIR}.bak
        result_msg "清理 旧的备份 etcd 数据文件夹"
    fi
    if [ -e ${ETCD_DATA_DIR} ]; then
        mv ${ETCD_DATA_DIR} ${ETCD_DATA_DIR}.bak
        result_msg "备份 etcd 数据文件夹"
    fi

    ETCDCTL_API=3 ${tmp_command} snapshot restore ${script_dir}/config/etcd-snap.db --data-dir=${ETCD_DATA_DIR}
    result_msg "恢复 etcd 数据库快照到数据文件夹"
}

# 启动 etcd
cluster_start_etcd() {
    if [ -e ${script_dir}/config/etcd.yaml ]; then
        mv ${script_dir}/config/kube-apiserver.yaml ${KUBEADM_MANIFESTS}/kube-apiserver.yaml &&
            mv ${script_dir}/config/etcd.yaml ${KUBEADM_MANIFESTS}/etcd.yaml
        result_msg "启动 etcd 和 apiserver 服务"
    fi
}

# 生成 admin.conf, 有效期 12h
cluster_generate_kubeconfig_tmp() {
    cd ${script_dir}/config &&
        kubectl get cm kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' >tmp-kubeadm-config.yaml &&
        kubeadm kubeconfig user --client-name=kubernetes-admin --org=system:masters --config=tmp-kubeadm-config.yaml --validity-period=12h >tmp-admin.conf &&
        chown ${SCRIPT_OWN}:${SCRIPT_OWN} tmp-admin.conf
    result_msg "生成 tmp-admim.conf(12h)"
}

# 配置临时的 .kube/config
cluster_config_kubectl_tmp() {
    mkdir -p $HOME/.kube &&
        /bin/cp ${script_dir}/config/tmp-admin.conf $HOME/.kube/config &&
        chmod 700 $HOME/.kube/config
    result_msg "配置 临时 kubectl config"
}

# 同步更新 .kube/config, 并安装命令自动补全
cluster_config_kubectl_command() {
    mkdir -p $HOME/.kube &&
        /bin/cp ${KUBEADM_CONFIG}/admin.conf $HOME/.kube/config &&
        chmod 700 $HOME/.kube/config
    result_msg "配置 kubectl config"

    install_apps "bash-completion"
    mkdir -p /etc/bash_completion.d &&
        kubectl completion bash >/etc/bash_completion.d/kubectl
    result_msg "添加 命令自动补全"
}

# 判断 join 信息是否有效(默认有效期 2 小时)
cluster_join_token_valid() {
    if [ -e ${script_dir}/config/join.sh ]; then
        source ${script_dir}/config/join.sh
        result_msg "加载 join 信息"

        local current_timestamp=$(date '+%s')
        local run_interval=$((current_timestamp - join_token_timestamp))

        [ ${run_interval} -le ${JOIN_TOKEN_INTERVAL} ] && return 0 || return 1
    else
        return 1
    fi
}

# 检查变量

check_by_const() {
    test ${SYSTEM_RELEASE} && test ${SYSTEM_PACKAGE} && test ${SYSTEM_VERSION} && test ${HOST_IP}
    result_msg "检查 const"
    echo "${HOST_IP}" | grep -Eqi '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    result_msg "检查 HOST_IP"
}

check_by_variables() {
    test ${MASTER1_IP} && test ${MASTER1_NAME}
    result_msg "检查 master1 var"
    test ${HOST_NAME} && test ${HOST_ROLE}
    result_msg "检查 localhost var"

    test ${criSocket}
    result_msg "检查 criSocket var"
    if [ ${criVersion} != 'latest' ]; then
        if [ ${criName} = 'containerd' ]; then
            compare_version_ge "$(echo ${criVersion} | awk -F '.' '{print $1"."$2}')" "1.5"
            result_msg "检查 criVersion >= 1.5"
        fi
    fi

    test $(echo "${kubernetesVersion}" | awk -F '.' '{print NF}') -eq 3 && echo "${kubernetesVersion}" | awk -F '.' '{print $1$2$3}' | grep -Eqi '^[[:digit:]]*$'
    result_msg "检查 kubernetesVersion 格式"
    compare_version_ge "${kubernetesMajorMinor}" "1.24"
    result_msg "检查 kubernetesVersion >= 1.24"
}

check_variables() {
    # 检查变量，异常才显示
    RES_LEVEL=1
    check_by_const
    check_by_variables
    RES_LEVEL=0
}

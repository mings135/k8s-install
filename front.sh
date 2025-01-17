#!/usr/bin/env bash

# Author: MingQ
if ! ps -ocmd $$ | grep -q "^bash"; then
    echo "请使用 bash $0 运行脚本!"
    exit 1
fi

# 已经安装 rsync 直接退出
if which rsync &>/dev/null; then
    exit 0
fi

RES_LEVEL=0
RES_COLUM=50

const_action() {
    local tmp_result tmp_rc tmp_color
    local tmp_msg=$1
    echo -n "$tmp_msg "
    shift
    if "$@"; then
        tmp_result="success"
        tmp_rc=0
        tmp_color=32
    else
        tmp_result="failure"
        tmp_rc=1
        tmp_color=31
    fi
    echo -ne "\033[${RES_COLUM}G[ \033[${tmp_color}m\033[01m${tmp_result}\033[0m ]"
    echo -ne "\r"
    echo
    return $tmp_rc
}

result_msg() {
    local tmp_rc=$?
    if [ ${tmp_rc} -eq 0 ]; then
        if [ ${RES_LEVEL} -eq 0 ]; then
            const_action "$*" "/bin/true"
        fi
    else
        const_action "$*" "/bin/false"
        exit 1
    fi
}

if [ -f /etc/redhat-release ]; then
    SYSTEM_RELEASE="centos"
    SYSTEM_PACKAGE="dnf"
elif cat /etc/issue | grep -Eqi "debian"; then
    SYSTEM_RELEASE="debian"
    SYSTEM_PACKAGE="apt-get"
fi

# 检查变量，异常显示
RES_LEVEL=1 && test ${SYSTEM_RELEASE} && test ${SYSTEM_PACKAGE}
result_msg "检查 system var" && RES_LEVEL=0

# 解决 debian 系统 debconf: unable to initialize frontend: Dialog 问题
if [ ${SYSTEM_RELEASE} = 'debian' ]; then
    export DEBIAN_FRONTEND=noninteractive
fi

${SYSTEM_PACKAGE} install -y rsync &>/dev/null
result_msg "安装 rsync"

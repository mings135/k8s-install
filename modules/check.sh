# 检查变量

upgrade_cluster_check() {
  RES_LEVEL=1

  local value
  value="$(get_record ".sys.init")"
  [[ "${value}" == "true" ]]
  result_msg "检查 sys.init"

  value="$(get_record ".cri.install")"
  [[ "${value}" == "true" ]]
  result_msg "检查 cri.install"

  value="$(get_record ".k8s.install")"
  [[ "${value}" == "true" ]]
  result_msg "检查 k8s.install"

  value="$(get_record ".cluster.join")"
  [[ "${value}" == "true" ]]
  result_msg "检查 cluster.join"

  value="$(get_record ".cluster.version")"
  version_ge "${kubernetesVersion}" "${value}"
  result_msg "检查 cluster.version"

  RES_LEVEL=0
}

upgrade_cri_check() {
  RES_LEVEL=1

  local value
  value="$(get_record ".cri.install")"
  [[ "${value}" == "true" ]]
  result_msg "检查 cri.install"

  if [[ "${criVersion}" != "latest" ]]; then
    value="$(get_record ".cri.version")"
    version_ge "${criVersion}" "${value}"
    result_msg "检查 cri.version"
  fi

  RES_LEVEL=0
}

check_by_const() {
  [[ -n "${script_own}" ]] && [[ -n "${HOST_IP}" ]] && [[ -n ${OS_VERSION} ]]
  result_msg "检查 const"

  version_ge "${OS_VERSION}" "12.0"
  result_msg "检查 OS_VERSION >=12.0"

  [[ "${HOST_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
  result_msg "检查 HOST_IP"
}

check_by_nodes() {
  [[ -n "${MASTER1_IP}" ]] && [[ -n "${MASTER1_NAME}" ]]
  result_msg "检查 master1 var"

  if [[ "${script_type}" == "local" ]]; then
    [[ -n "${HOST_NAME}" ]] && [[ -n "${HOST_ROLE}" ]]
    result_msg "检查 host var"

    [[ -f "${KUBE_RECORD}" ]]
    result_msg "检查 record 文件"
  fi

  [[ -f "${KUBE_FILE}" ]]
  result_msg "检查 config 文件"
  [[ -f "${KUBE_BIN}/yq" ]]
  result_msg "检查 yq"
  [[ -f "${KUBE_BIN}/rrcmd" ]]
  result_msg "检查 rrcmd"
  [[ -f "${KUBE_BIN}/etcdctl" ]]
  result_msg "检查 etcdctl"
}

check_by_config() {
  [[ "${kubernetesVersion}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  result_msg "检查 kubernetesVersion 格式"
  version_ge "${kubernetesVersion}" "1.31.0"
  result_msg "检查 kubernetesVersion >= 1.31.0"

  if [[ "${criVersion}" != "latest" ]]; then
    [[ "${criVersion}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    result_msg "检查 criVersion 格式"
    version_ge "${criVersion}" "1.7.0"
    result_msg "检查 criVersion >= 1.7.0"
  fi

  local pattern="^[0-9]+h[0-9]+m[0-9]+s$"
  [[ "${caCertificateValidityPeriod}" =~ ${pattern} ]]
  result_msg "检查 caCertificateValidityPeriod 格式"
  [[ "${certificateValidityPeriod}" =~ ${pattern} ]]
  result_msg "检查 certificateValidityPeriod 格式"
}

check_variables() {
  # 检查变量，异常才显示
  RES_LEVEL=1
  check_by_const
  check_by_nodes
  check_by_config
  RES_LEVEL=0
}

[[ $- == *e* ]] && old_errexit="set -e" || old_errexit="set +e"
set +e
check_variables
${old_errexit}

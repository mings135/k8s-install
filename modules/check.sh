# 检查变量

upgrade_cluster_check() {
  RES_LEVEL=1

  local value
  value="$(get_record ".sys.init")"
  [[ "${value}" == "true" ]]
  result_msg "[Check] sys.init"

  value="$(get_record ".cri.install")"
  [[ "${value}" == "true" ]]
  result_msg "[Check] cri.install"

  value="$(get_record ".k8s.install")"
  [[ "${value}" == "true" ]]
  result_msg "[Check] k8s.install"

  value="$(get_record ".cluster.join")"
  [[ "${value}" == "true" ]]
  result_msg "[Check] cluster.join"

  value="$(get_record ".cluster.version")"
  version_ge "${kubernetesVersion}" "${value}"
  result_msg "[Check] cluster.version"

  RES_LEVEL=0
}

upgrade_cri_check() {
  RES_LEVEL=1

  local value
  value="$(get_record ".cri.install")"
  [[ "${value}" == "true" ]]
  result_msg "[Check] cri.install"

  if [[ "${criVersion}" != "latest" ]]; then
    value="$(get_record ".cri.version")"
    version_ge "${criVersion}" "${value}"
    result_msg "[Check] cri.version"
  fi

  RES_LEVEL=0
}

check_by_const() {
  [[ -n "${script_own}" ]] && [[ -n "${HOST_IP}" ]] && [[ -n ${OS_VERSION} ]]
  result_msg "[Check] const"

  version_ge "${OS_VERSION}" "12.0"
  result_msg "[Check] OS_VERSION >=12.0"

  local pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
  [[ "${HOST_IP}" =~ ${pattern} ]]
  result_msg "[Check] HOST_IP format"
}

check_by_nodes() {
  [[ -n "${MASTER1_IP}" ]] && [[ -n "${MASTER1_NAME}" ]]
  result_msg "[Check] master1 var"

  if [[ "${script_type}" == "local" ]]; then
    [[ -n "${HOST_NAME}" ]] && [[ -n "${HOST_ROLE}" ]]
    result_msg "[Check] host var"

    [[ -f "${KUBE_RECORD}" ]]
    result_msg "[Check] ${KUBE_RECORD}"
  fi

  [[ -f "${KUBE_FILE}" ]]
  result_msg "[Check] ${KUBE_FILE}"
  [[ -f "${KUBE_BIN}/yq" ]]
  result_msg "[Check] yq command"
  [[ -f "${KUBE_BIN}/rrcmd" ]]
  result_msg "[Check] rrcmd command"
  [[ -f "${KUBE_BIN}/etcdctl" ]]
  result_msg "[Check] etcdctl command"
}

check_by_config() {
  local pattern="^[0-9]+\.[0-9]+\.[0-9]+$"
  [[ "${kubernetesVersion}" =~ ${pattern} ]]
  result_msg "[Check] kubernetesVersion format"
  version_ge "${kubernetesVersion}" "1.31.0"
  result_msg "[Check] kubernetesVersion >= 1.31.0"

  pattern="^(([0-9]{1,3}\.){3}[0-9]{1,3}|([a-z0-9][-a-z0-9]*\.)+[a-z0-9]+[a-z]):[0-9]{1,5}$"
  [[ "${controlPlaneEndpoint}" =~ ${pattern} ]]
  result_msg "[Check] controlPlaneEndpoint format"

  pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
  if [[ -n "${controlPlaneTarget}" ]]; then
    [[ "${controlPlaneTarget}" =~ ${pattern} ]]
    result_msg "[Check] controlPlaneTarget format"
  fi

  pattern="^[0-9]+\.[0-9]+\.[0-9]+$"
  if [[ "${criVersion}" != "latest" ]]; then
    [[ "${criVersion}" =~ ${pattern} ]]
    result_msg "[Check] criVersion format"
    version_ge "${criVersion}" "1.7.0"
    result_msg "[Check] criVersion >= 1.7.0"
  fi

  pattern="^[0-9]+h[0-9]+m[0-9]+s$"
  [[ "${caCertificateValidityPeriod}" =~ ${pattern} ]]
  result_msg "[Check] caCertificateValidityPeriod format"
  [[ "${certificateValidityPeriod}" =~ ${pattern} ]]
  result_msg "[Check] certificateValidityPeriod format"

  local value="$(has_config ".nodes" "master")"
  if [[ "${value}" == "true" ]]; then
    value="$(kind_config ".nodes.master" "seq")"
    [[ "${value}" == "true" ]]
    result_msg "[Check] .nodes.master kind seq"
  fi

  value="$(has_config ".nodes" "work")"
  if [[ "${value}" == "true" ]]; then
    value="$(kind_config ".nodes.work" "seq")"
    [[ "${value}" == "true" ]]
    result_msg "[Check] .nodes.work kind seq"
  fi

  value="$(has_config ".cluster" "certSANs")"
  if [[ "${value}" == "true" ]]; then
    value="$(kind_config ".cluster.certSANs" "seq")"
    [[ "${value}" == "true" ]]
    result_msg "[Check] .cluster.certSANs kind seq"
  fi
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

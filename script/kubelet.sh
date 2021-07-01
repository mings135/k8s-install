
# 安装 kubelet 相关证书

# 全局变量
#CERT_SIZE=2048
#VALID_DAYS=18250
#HOST_NAME=''
#KUBELET_PKI='/var/lib/kubelet/pki'

kubelet_conf_crt() {
  cd ${KUBELET_PKI} || exit 1

  cat > kubelet.cnf << EOF
[server]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=serverAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectAltName = DNS:${HOST_NAME}
subjectKeyIdentifier=hash

[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  # server crt
  openssl genrsa -out "kubelet.key" ${CERT_SIZE}

  openssl req -new -key "kubelet.key" \
          -out "kubelet.csr" -sha256 \
          -subj "/CN=kubelet-${HOST_NAME}"

  openssl x509 -req -days ${VALID_DAYS} -in "kubelet.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "kubelet.crt" -extfile "kubelet.cnf" -extensions server

  # client conf
  openssl genrsa -out "client.key" ${CERT_SIZE}

  openssl req -new -key "client.key" \
          -out "client.csr" -sha256 \
          -subj "/O=system:nodes/CN=system:node:${HOST_NAME}"

  openssl x509 -req -days ${VALID_DAYS} -in "client.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "client.crt" -extfile "kubelet.cnf" -extensions client

  cat client.key >> client.crt
  mv -f client.crt kubelet-client-long.pem
  rm -f kubelet-client-current.pem
  ln -s ${KUBELET_PKI}/kubelet-client-long.pem ${KUBELET_PKI}/kubelet-client-current.pem

  rm -f kubelet.{cnf,csr} client.{key,csr} ca.srl
}
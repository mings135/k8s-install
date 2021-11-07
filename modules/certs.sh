# 安装 etcd_crt、apiserver_crt、front-proxy_crt、admin_conf、controller-manager_conf、scheduler_conf 证书等文件

# 全局变量
#CERT_SIZE=2048
#VALID_DAYS=18250
#K8S_PKI='/etc/kubernetes/pki'
#K8S_CONFIG='/etc/kubernetes'
#HOST_NAME=''
#HOST_IP=''
#CLUSTER_VIP='192.168.10.31'
#CLUSTER_PORT=6443
#CLUSTER_IP='10.96.0.1'


etcd_crt() {
  # 证书目录
  cd ${K8S_PKI} || exit 1

  cat > etcd.cnf << EOF
[ peer ]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=serverAuth,clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectAltName = @alt_names
subjectKeyIdentifier=hash

[ client ]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash

[ alt_names ]
DNS.1 = ${HOST_NAME}
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = 0:0:0:0:0:0:0:1
IP.3 = ${HOST_IP}
EOF

  # etcd/server.crt(CN=${HOST_NAME})
  openssl genrsa -out "etcd/server.key" ${CERT_SIZE}
  openssl req -new -key "etcd/server.key" \
          -out "etcd/server.csr" -sha256 \
          -subj "/CN=${HOST_NAME}"

  openssl x509 -req -days ${VALID_DAYS} -in "etcd/server.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "etcd/server.crt" -extfile "etcd.cnf" -extensions peer

  # etcd/peer.crt(CN=${HOST_NAME})
  openssl genrsa -out "etcd/peer.key" ${CERT_SIZE}
  openssl req -new -key "etcd/peer.key" \
          -out "etcd/peer.csr" -sha256 \
          -subj "/CN=${HOST_NAME}"

  openssl x509 -req -days ${VALID_DAYS} -in "etcd/peer.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "etcd/peer.crt" -extfile "etcd.cnf" -extensions peer

  # etcd/healthcheck-client.crt(CN=kube-etcd-healthcheck-client)
  openssl genrsa -out "etcd/healthcheck-client.key" ${CERT_SIZE}
  openssl req -new -key "etcd/healthcheck-client.key" \
          -out "etcd/healthcheck-client.csr" -sha256 \
          -subj "/O=system:masters/CN=kube-etcd-healthcheck-client"

  openssl x509 -req -days ${VALID_DAYS} -in "etcd/healthcheck-client.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "etcd/healthcheck-client.crt" -extfile "etcd.cnf" -extensions client

  # apiserver-etcd-client.crt(CN=kube-apiserver-etcd-client)
  openssl genrsa -out "apiserver-etcd-client.key" ${CERT_SIZE}

  openssl req -new -key "apiserver-etcd-client.key" \
          -out "apiserver-etcd-client.csr" -sha256 \
          -subj "/O=system:masters/CN=kube-apiserver-etcd-client"

  openssl x509 -req -days ${VALID_DAYS} -in "apiserver-etcd-client.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "apiserver-etcd-client.crt" -extfile "etcd.cnf" -extensions client

  rm -f etcd.cnf etcd/{server,peer,healthcheck-client}.csr apiserver-etcd-client.csr
}


apiserver_crt() {
  # pki 目录
  cd ${K8S_PKI} || exit 1

  cat > apiserver.cnf << EOF
[server]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=serverAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectAltName = @alt_names
subjectKeyIdentifier=hash

[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = ${HOST_NAME}
IP.1 = ${CLUSTER_IP}
IP.2 = ${HOST_IP}
IP.3 = ${CLUSTER_VIP}
EOF

  # apiserver.crt(CN=kube-apiserver)
  openssl genrsa -out "apiserver.key" ${CERT_SIZE}
  openssl req -new -key "apiserver.key" \
          -out "apiserver.csr" -sha256 \
          -subj "/CN=kube-apiserver"

  openssl x509 -req -days ${VALID_DAYS} -in "apiserver.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "apiserver.crt" -extfile "apiserver.cnf" -extensions server

  # apiserver-kubelet-client.crt(CN=kube-apiserver-kubelet-client)
  openssl genrsa -out "apiserver-kubelet-client.key" ${CERT_SIZE}
  openssl req -new -key "apiserver-kubelet-client.key" \
          -out "apiserver-kubelet-client.csr" -sha256 \
          -subj "/O=system:masters/CN=kube-apiserver-kubelet-client"

  openssl x509 -req -days ${VALID_DAYS} -in "apiserver-kubelet-client.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "apiserver-kubelet-client.crt" -extfile "apiserver.cnf" -extensions client

  rm -f apiserver.cnf {apiserver,apiserver-kubelet-client}.csr
}


front_crt() {
  cd ${K8S_PKI} || exit 1

  cat > front.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  # front-proxy-client.crt(CN=front-proxy-client)
  openssl genrsa -out "front-proxy-client.key" ${CERT_SIZE}
  openssl req -new -key "front-proxy-client.key" \
          -out "front-proxy-client.csr" -sha256 \
          -subj '/CN=front-proxy-client'

  openssl x509 -req -days ${VALID_DAYS} -in "front-proxy-client.csr" -sha256 \
      -CA "front-proxy-ca.crt" -CAkey "front-proxy-ca.key" -CAcreateserial \
      -out "front-proxy-client.crt" -extfile "front.cnf" -extensions client

  rm -f front.cnf front-proxy-client.csr
}


admin_conf() {
  cd ${K8S_CONFIG} || exit 1

  cat > admin.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  openssl genrsa -out "admin.key" ${CERT_SIZE}
  openssl req -new -key "admin.key" \
          -out "admin.csr" -sha256 \
          -subj '/O=system:masters/CN=kubernetes-admin'

  openssl x509 -req -days ${VALID_DAYS} -in "admin.csr" -sha256 \
      -CA "pki/ca.crt" -CAkey "pki/ca.key" -CAcreateserial \
      -out "admin.crt" -extfile "admin.cnf" -extensions client

  kubectl config set-cluster kubernetes \
    --certificate-authority=pki/ca.crt \
    --embed-certs=true \
    --server=https://${CLUSTER_VIP}:${CLUSTER_PORT} \
    --kubeconfig=admin.conf

  kubectl config set-credentials kubernetes-admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.conf

  kubectl config set-context kubernetes-admin@kubernetes \
    --cluster=kubernetes \
    --user=kubernetes-admin \
    --kubeconfig=admin.conf

  kubectl config use-context kubernetes-admin@kubernetes --kubeconfig=admin.conf

  rm -f admin.{cnf,csr,crt,key}
}


manager_conf() {
  cd ${K8S_CONFIG} || exit 1

  cat > manager.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  openssl genrsa -out "controller-manager.key" ${CERT_SIZE}
  openssl req -new -key "controller-manager.key" \
          -out "controller-manager.csr" -sha256 \
          -subj '/CN=system:kube-controller-manager'

  openssl x509 -req -days ${VALID_DAYS} -in "controller-manager.csr" -sha256 \
      -CA "pki/ca.crt" -CAkey "pki/ca.key" -CAcreateserial \
      -out "controller-manager.crt" -extfile "manager.cnf" -extensions client

  kubectl config set-cluster kubernetes \
    --certificate-authority=pki/ca.crt \
    --embed-certs=true \
    --server=https://${CLUSTER_VIP}:${CLUSTER_PORT} \
    --kubeconfig=controller-manager.conf

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=controller-manager.crt \
    --client-key=controller-manager.key \
    --embed-certs=true \
    --kubeconfig=controller-manager.conf

  kubectl config set-context system:kube-controller-manager@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=controller-manager.conf

  kubectl config use-context system:kube-controller-manager@kubernetes --kubeconfig=controller-manager.conf

  rm -f manager.cnf controller-manager.{csr,key,crt}
}


scheduler_conf() {
  cd ${K8S_CONFIG} || exit 1

  cat > scheduler.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  openssl genrsa -out "scheduler.key" ${CERT_SIZE}
  openssl req -new -key "scheduler.key" \
          -out "scheduler.csr" -sha256 \
          -subj '/CN=system:kube-scheduler'

  openssl x509 -req -days ${VALID_DAYS} -in "scheduler.csr" -sha256 \
      -CA "pki/ca.crt" -CAkey "pki/ca.key" -CAcreateserial \
      -out "scheduler.crt" -extfile "scheduler.cnf" -extensions client

  kubectl config set-cluster kubernetes \
    --certificate-authority=pki/ca.crt \
    --embed-certs=true \
    --server=https://${CLUSTER_VIP}:${CLUSTER_PORT} \
    --kubeconfig=scheduler.conf

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=scheduler.crt \
    --client-key=scheduler.key \
    --embed-certs=true \
    --kubeconfig=scheduler.conf

  kubectl config set-context system:kube-scheduler@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=scheduler.conf

  kubectl config use-context system:kube-scheduler@kubernetes --kubeconfig=scheduler.conf

  rm -f scheduler.{cnf,csr,crt,key}
}
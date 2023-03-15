# 安装证书，函数:
# certs_ca_remote
# certs_etcd
# certs_apiserver
# certs_front-proxy
# certs_admin_conf
# certs_controller-manager_conf
# certs_scheduler_conf
# certs_kubelet_pem

# 所需变量:
# script_dir=''
# certificatesSize=2048
# certificatesVaild=18250
# KUBEADM_PKI='/etc/kubernetes/pki'
# KUBEADM_CONFIG='/etc/kubernetes'
# KUBELET_PKI='/var/lib/kubelet/pki'
# HOST_NAME=''
# HOST_IP=''
# apiServerClusterIP=''
# controlPlaneAddress='192.168.10.31'
# controlPlaneEndpoint='192.168.10.31:6443'


# 签发所有 CA 和 sa 证书
certs_ca_remote() {
  cd ${script_dir}/pki
  mkdir -p etcd
  cat > ca.cnf << EOF
[ root_ca ]
basicConstraints        = critical, CA:TRUE
subjectKeyIdentifier    = hash
keyUsage                = critical, cRLSign, digitalSignature, keyCertSign
EOF

  # ca.crt(CN=kubernetes)
  openssl genrsa -out "ca.key" ${certificatesSize}
  openssl req -new -key "ca.key" \
          -out "ca.csr" -sha256 \
          -subj '/CN=kubernetes'

  openssl x509 -req -days ${certificatesVaild} -in "ca.csr" \
               -signkey "ca.key" -sha256 -out "ca.crt" \
               -extfile "ca.cnf" -extensions \
               root_ca

  # front-proxy-ca.crt(CN=front-proxy-ca)
  openssl genrsa -out "front-proxy-ca.key" ${certificatesSize}
  openssl req -new -key "front-proxy-ca.key" \
          -out "front-proxy-ca.csr" -sha256 \
          -subj '/CN=front-proxy-ca'

  openssl x509 -req -days ${certificatesVaild} -in "front-proxy-ca.csr" \
               -signkey "front-proxy-ca.key" -sha256 -out "front-proxy-ca.crt" \
               -extfile "ca.cnf" -extensions \
               root_ca

  # etcd/ca.crt(CN=etcd-ca)
  openssl genrsa -out "etcd/ca.key" ${certificatesSize}
  openssl req -new -key "etcd/ca.key" \
          -out "etcd/ca.csr" -sha256 \
          -subj '/CN=etcd-ca'

  openssl x509 -req -days ${certificatesVaild} -in "etcd/ca.csr" \
               -signkey "etcd/ca.key" -sha256 -out "etcd/ca.crt" \
               -extfile "ca.cnf" -extensions \
               root_ca

  # sa.key sa.pub
  openssl genrsa -out "sa.key" ${certificatesSize}
  openssl rsa -in sa.key -pubout > sa.pub

  rm -f ca.cnf {ca,front-proxy-ca}.csr etcd/ca.csr
}


# 创建 etcd/server.crt、etcd/peer.crt、etcd/healthcheck-client.crt、apiserver-etcd-client.crt 证书
certs_etcd() {
  # 证书目录
  cd ${KUBEADM_PKI}

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
  openssl genrsa -out "etcd/server.key" ${certificatesSize}
  openssl req -new -key "etcd/server.key" \
          -out "etcd/server.csr" -sha256 \
          -subj "/CN=${HOST_NAME}"

  openssl x509 -req -days ${certificatesVaild} -in "etcd/server.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "etcd/server.crt" -extfile "etcd.cnf" -extensions peer

  # etcd/peer.crt(CN=${HOST_NAME})
  openssl genrsa -out "etcd/peer.key" ${certificatesSize}
  openssl req -new -key "etcd/peer.key" \
          -out "etcd/peer.csr" -sha256 \
          -subj "/CN=${HOST_NAME}"

  openssl x509 -req -days ${certificatesVaild} -in "etcd/peer.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "etcd/peer.crt" -extfile "etcd.cnf" -extensions peer

  # etcd/healthcheck-client.crt(CN=kube-etcd-healthcheck-client)
  openssl genrsa -out "etcd/healthcheck-client.key" ${certificatesSize}
  openssl req -new -key "etcd/healthcheck-client.key" \
          -out "etcd/healthcheck-client.csr" -sha256 \
          -subj "/O=system:masters/CN=kube-etcd-healthcheck-client"

  openssl x509 -req -days ${certificatesVaild} -in "etcd/healthcheck-client.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "etcd/healthcheck-client.crt" -extfile "etcd.cnf" -extensions client

  # apiserver-etcd-client.crt(CN=kube-apiserver-etcd-client)
  openssl genrsa -out "apiserver-etcd-client.key" ${certificatesSize}

  openssl req -new -key "apiserver-etcd-client.key" \
          -out "apiserver-etcd-client.csr" -sha256 \
          -subj "/O=system:masters/CN=kube-apiserver-etcd-client"

  openssl x509 -req -days ${certificatesVaild} -in "apiserver-etcd-client.csr" -sha256 \
      -CA "etcd/ca.crt" -CAkey "etcd/ca.key" -CAcreateserial \
      -out "apiserver-etcd-client.crt" -extfile "etcd.cnf" -extensions client

  rm -f etcd.cnf etcd/{server,peer,healthcheck-client}.csr apiserver-etcd-client.csr etcd/ca.srl
}


# 创建 apiserver.crt 和 apiserver-kubelet-client.crt 证书
certs_apiserver() {
  # pki 目录
  cd ${KUBEADM_PKI}

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
IP.1 = ${apiServerClusterIP}
IP.2 = ${HOST_IP}
EOF
  if [ "${controlPlaneAddress}" != "${HOST_IP}" ]; then
    echo "IP.3 = ${controlPlaneAddress}" >> apiserver.cnf
  fi

  # apiserver.crt(CN=kube-apiserver)
  openssl genrsa -out "apiserver.key" ${certificatesSize}
  openssl req -new -key "apiserver.key" \
          -out "apiserver.csr" -sha256 \
          -subj "/CN=kube-apiserver"

  openssl x509 -req -days ${certificatesVaild} -in "apiserver.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "apiserver.crt" -extfile "apiserver.cnf" -extensions server

  # apiserver-kubelet-client.crt(CN=kube-apiserver-kubelet-client)
  openssl genrsa -out "apiserver-kubelet-client.key" ${certificatesSize}
  openssl req -new -key "apiserver-kubelet-client.key" \
          -out "apiserver-kubelet-client.csr" -sha256 \
          -subj "/O=system:masters/CN=kube-apiserver-kubelet-client"

  openssl x509 -req -days ${certificatesVaild} -in "apiserver-kubelet-client.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "apiserver-kubelet-client.crt" -extfile "apiserver.cnf" -extensions client

  rm -f apiserver.cnf {apiserver,apiserver-kubelet-client}.csr ca.srl
}


# 创建 front-proxy-client.crt 证书
certs_front-proxy() {
  cd ${KUBEADM_PKI}

  cat > front.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  # front-proxy-client.crt(CN=front-proxy-client)
  openssl genrsa -out "front-proxy-client.key" ${certificatesSize}
  openssl req -new -key "front-proxy-client.key" \
          -out "front-proxy-client.csr" -sha256 \
          -subj '/CN=front-proxy-client'

  openssl x509 -req -days ${certificatesVaild} -in "front-proxy-client.csr" -sha256 \
      -CA "front-proxy-ca.crt" -CAkey "front-proxy-ca.key" -CAcreateserial \
      -out "front-proxy-client.crt" -extfile "front.cnf" -extensions client

  rm -f front.cnf front-proxy-client.csr front-proxy-ca.srl
}


# 创建 admin.conf 证书配置文件
certs_admin_conf() {
  cd ${KUBEADM_CONFIG}

  cat > admin.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  openssl genrsa -out "admin.key" ${certificatesSize}
  openssl req -new -key "admin.key" \
          -out "admin.csr" -sha256 \
          -subj '/O=system:masters/CN=kubernetes-admin'

  openssl x509 -req -days ${certificatesVaild} -in "admin.csr" -sha256 \
      -CA "pki/ca.crt" -CAkey "pki/ca.key" -CAcreateserial \
      -out "admin.crt" -extfile "admin.cnf" -extensions client

  kubectl config set-cluster kubernetes \
    --certificate-authority=pki/ca.crt \
    --embed-certs=true \
    --server=https://${controlPlaneEndpoint} \
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

  rm -f admin.{cnf,csr,crt,key} pki/ca.srl
}


# 创建 controller-manager.conf 证书配置文件
certs_controller-manager_conf() {
  cd ${KUBEADM_CONFIG}

  cat > manager.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  openssl genrsa -out "controller-manager.key" ${certificatesSize}
  openssl req -new -key "controller-manager.key" \
          -out "controller-manager.csr" -sha256 \
          -subj '/CN=system:kube-controller-manager'

  openssl x509 -req -days ${certificatesVaild} -in "controller-manager.csr" -sha256 \
      -CA "pki/ca.crt" -CAkey "pki/ca.key" -CAcreateserial \
      -out "controller-manager.crt" -extfile "manager.cnf" -extensions client

  kubectl config set-cluster kubernetes \
    --certificate-authority=pki/ca.crt \
    --embed-certs=true \
    --server=https://${HOST_IP}:6443 \
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

  rm -f manager.cnf controller-manager.{csr,key,crt} pki/ca.srl
}


# 创建 scheduler.conf 证书配置文件
certs_scheduler_conf() {
  cd ${KUBEADM_CONFIG}

  cat > scheduler.cnf << EOF
[client]
authorityKeyIdentifier=keyid,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
subjectKeyIdentifier=hash
EOF

  openssl genrsa -out "scheduler.key" ${certificatesSize}
  openssl req -new -key "scheduler.key" \
          -out "scheduler.csr" -sha256 \
          -subj '/CN=system:kube-scheduler'

  openssl x509 -req -days ${certificatesVaild} -in "scheduler.csr" -sha256 \
      -CA "pki/ca.crt" -CAkey "pki/ca.key" -CAcreateserial \
      -out "scheduler.crt" -extfile "scheduler.cnf" -extensions client

  kubectl config set-cluster kubernetes \
    --certificate-authority=pki/ca.crt \
    --embed-certs=true \
    --server=https://${HOST_IP}:6443 \
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

  rm -f scheduler.{cnf,csr,crt,key} pki/ca.srl
}


# 创建新 kubelet 证书, 并将 key 追加到 crt 中, 最后修改软连接 kubelet-client-current.pem 的指向
certs_kubelet_pem() {
  cd ${KUBELET_PKI}

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
  openssl genrsa -out "kubelet.key" ${certificatesSize}

  openssl req -new -key "kubelet.key" \
          -out "kubelet.csr" -sha256 \
          -subj "/CN=kubelet-${HOST_NAME}"

  openssl x509 -req -days ${certificatesVaild} -in "kubelet.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "kubelet.crt" -extfile "kubelet.cnf" -extensions server

  # client conf
  openssl genrsa -out "client.key" ${certificatesSize}

  openssl req -new -key "client.key" \
          -out "client.csr" -sha256 \
          -subj "/O=system:nodes/CN=system:node:${HOST_NAME}"

  openssl x509 -req -days ${certificatesVaild} -in "client.csr" -sha256 \
      -CA "ca.crt" -CAkey "ca.key" -CAcreateserial \
      -out "client.crt" -extfile "kubelet.cnf" -extensions client

  cat client.key >> client.crt
  mv -f client.crt kubelet-client-long.pem
  rm -f kubelet-client-current.pem
  ln -s ${KUBELET_PKI}/kubelet-client-long.pem ${KUBELET_PKI}/kubelet-client-current.pem

  rm -f kubelet.{cnf,csr} client.{key,csr} ca.srl
}

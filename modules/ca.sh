# 签发所有 CA 和 sa 证书

# 全局变量
#CERT_SIZE=2048
#VALID_DAYS=18250


ca_crt() {
  [ -d etcd ] || mkdir etcd
  cat > ca.cnf << EOF
[ root_ca ]
basicConstraints        = critical, CA:TRUE
subjectKeyIdentifier    = hash
keyUsage                = critical, cRLSign, digitalSignature, keyCertSign
EOF

  # ca.crt(CN=kubernetes)
  openssl genrsa -out "ca.key" ${CERT_SIZE}
  openssl req -new -key "ca.key" \
          -out "ca.csr" -sha256 \
          -subj '/CN=kubernetes'

  openssl x509 -req -days ${VALID_DAYS} -in "ca.csr" \
               -signkey "ca.key" -sha256 -out "ca.crt" \
               -extfile "ca.cnf" -extensions \
               root_ca

  # front-proxy-ca.crt(CN=front-proxy-ca)
  openssl genrsa -out "front-proxy-ca.key" ${CERT_SIZE}
  openssl req -new -key "front-proxy-ca.key" \
          -out "front-proxy-ca.csr" -sha256 \
          -subj '/CN=front-proxy-ca'

  openssl x509 -req -days ${VALID_DAYS} -in "front-proxy-ca.csr" \
               -signkey "front-proxy-ca.key" -sha256 -out "front-proxy-ca.crt" \
               -extfile "ca.cnf" -extensions \
               root_ca

  # etcd/ca.crt(CN=etcd-ca)
  openssl genrsa -out "etcd/ca.key" ${CERT_SIZE}
  openssl req -new -key "etcd/ca.key" \
          -out "etcd/ca.csr" -sha256 \
          -subj '/CN=etcd-ca'

  openssl x509 -req -days ${VALID_DAYS} -in "etcd/ca.csr" \
               -signkey "etcd/ca.key" -sha256 -out "etcd/ca.crt" \
               -extfile "ca.cnf" -extensions \
               root_ca

  # sa.key sa.pub
  openssl genrsa -out "sa.key" ${CERT_SIZE}
  openssl rsa -in sa.key -pubout > sa.pub

  rm -f ca.cnf {ca,front-proxy-ca}.csr etcd/ca.csr
}
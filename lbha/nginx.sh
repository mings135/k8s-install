nginx_config() {
  local nginx_conf_file="${script_dir}/nginx/nginx.conf"
  local k8s_node_ip k8s_node_role

  cat > ${nginx_conf_file} << EOF
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    use epoll;
    worker_connections  10240;
}

stream {
    upstream kube-apiserver {
EOF

  while read line
  do
    if echo "${line}" | grep -Eqi '^ *#|^ *$'; then
      continue
    fi

    k8s_node_role=$(echo "${line}" | awk -F '=' '{print $3}') 
    if echo "${k8s_node_role}" | grep -Eqi '^m'; then
      k8s_node_ip=$(echo "${line}" | awk -F '=' '{print $2}')
      echo "        server ${k8s_node_ip}:6443     max_fails=3 fail_timeout=30s;" >> ${nginx_conf_file}
    fi
  done < ${parent_dir}/config/nodes.conf

  cat >> ${nginx_conf_file} << EOF
    }
    server {
        listen ${CLUSTER_PORT};
        proxy_connect_timeout 2s;
        proxy_timeout 900s;
        proxy_pass kube-apiserver;
    }
}
EOF
}


nginx_up() {
  cd ${script_dir}/nginx
  docker-compose up -d
}


nginx_down() {
  cd ${script_dir}/nginx
  docker-compose down
}

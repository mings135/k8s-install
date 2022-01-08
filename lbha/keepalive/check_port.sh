#!/bin/bash
# keepalived 监控本机端口脚本

CHK_PORT=$1
if [ "$CHK_PORT" ]; then
  PORT_PROCESS=$(netstat -tlnp | grep $CHK_PORT | wc -l)
  if [ $PORT_PROCESS -eq 0 ]; then
    echo "Port: $CHK_PORT ERROR"
    exit 1
  fi
else
  echo "Check Port Cant Be Empty!"
fi
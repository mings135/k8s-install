FROM debian:11.1

ARG DEBIAN_FRONTEND=noninteractive

ADD sources.list /etc/apt/sources.list
RUN apt-get update && apt-get install -y keepalived net-tools

CMD keepalived -n -d -l -D -f /etc/keepalived/keepalived.conf
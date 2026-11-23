#!/bin/sh
# Dựng image quantum-learn:vps KHÔNG dùng buildx/buildkit (hay hỏng trên Kiri): run → cài gói → commit.
set -e
cd "$(dirname "$0")"
IMG=quantum-learn:vps
docker rm -f ql-build >/dev/null 2>&1 || true
docker run -d --name ql-build ubuntu:24.04 sleep 3600 >/dev/null
docker exec -e DEBIAN_FRONTEND=noninteractive ql-build bash -c '
  apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    sudo procps psmisc iproute2 iputils-ping net-tools dnsutils curl wget ca-certificates \
    vim-tiny nano less file tree htop lsof strace cron openssh-client rsync git jq \
    unzip zip tar gzip xz-utils bzip2 man-db python3 nginx-light logrotate bc \
    systemd systemd-sysv dbus openssh-server nodejs >/dev/null &&
  systemctl mask getty.target console-getty.service systemd-logind.service systemd-networkd.service systemd-resolved.service apt-daily.timer apt-daily-upgrade.timer motd-news.timer >/dev/null 2>&1 || true &&
  systemctl disable nginx ssh >/dev/null 2>&1 || true &&
  rm -rf /var/lib/apt/lists/* &&
  echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ql && chmod 440 /etc/sudoers.d/ql &&
  mkdir -p /opt/ql'
docker cp bashrc ql-build:/opt/ql/bashrc
docker cp dump.sh ql-build:/opt/ql/dump.sh
docker cp dump_state.py ql-build:/opt/ql/dump_state.py
docker exec ql-build chmod +x /opt/ql/dump_state.py
docker exec ql-build chmod +x /opt/ql/dump.sh
docker commit ql-build "$IMG" >/dev/null
docker rm -f ql-build >/dev/null
echo "ok $IMG"

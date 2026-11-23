# Image lab thật của Quantum Learn: Ubuntu 24.04 + công cụ quản trị VPS thường dùng.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      sudo procps psmisc iproute2 iputils-ping net-tools dnsutils curl wget ca-certificates \
      vim-tiny nano less file tree htop lsof strace cron openssh-client rsync git jq \
      unzip zip tar gzip xz-utils bzip2 man-db python3 nginx-light logrotate bc \
    && rm -rf /var/lib/apt/lists/* \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ql && chmod 440 /etc/sudoers.d/ql
COPY bashrc /opt/ql/bashrc
COPY dump.sh /opt/ql/dump.sh
RUN chmod +x /opt/ql/dump.sh

# syntax=docker/dockerfile:1.7.0
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN <<eof
ARCH="$(dpkg --print-architecture)"
LOCALE="C.UTF-8"
TIMEZONE="America/Toronto"
apt-get update -yq
apt-get install -y \
  apparmor \
  apt-transport-https \
  bash \
  ca-certificates \
  conntrack \
  cron \
  curl \
  dbus \
  ethtool \
  file \
  fuse-overlayfs \
  gettext \
  git \
  gnupg \
  gnupg-agent \
  gnupg2 \
  iproute2 \
  iptables \
  jq \
  kmod \
  libseccomp2 \
  mount \
  nfs-common \
  nftables \
  open-iscsi \
  openssh-server \
  openssl \
  pigz \
  procps \
  software-properties-common \
  ssh \
  sudo \
  systemd \
  udev \
  util-linux \
  vim
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
add-apt-repository "deb https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get install -y \
  containerd.io \
  docker-ce \
  docker-ce-cli
useradd -m -d /home/devcontainer -s /bin/bash -G sudo,docker devcontainer
echo "sudo mount --make-rshared /" >/opt/mount.sh
echo "PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin\"\nEDITOR=\"vim\"" >/etc/environment
echo "[Service]\nDelegate=cpu cpuset io memory pids" >/usr/lib/systemd/system/user@.service.d/delegate.conf
echo "devcontainer ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/devcontainer
chmod 0440 /etc/sudoers.d/devcontainer
chmod 0644 /etc/environment /usr/lib/systemd/system/user@.service.d/delegate.conf
chmod 0755 /opt/mount.sh
swapoff -a && sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab || true
localectl set-locale LANG="${LOCALE}"
timedatectl set-ntp true
timedatectl set-timezone "${TIMEZONE}"
apt-get clean
rm -rf /var/lib/apt/lists/*
stat -c %T -f /sys/fs/cgroup
eof
CMD [ "/sbin/init" ]
USER devcontainer
HEALTHCHECK NONE

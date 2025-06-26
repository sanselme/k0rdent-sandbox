#!/bin/bash
set -exo pipefail

ipv6() {
  timestamp="$(date +%s%N)"
  machineid="$(cat /etc/machine-id)"
  shasum="$(printf ${timestamp}${machineid} | sha1sum)"
  bytes="$(printf ${shasum} | cut -c 31- | tr -d '-')"

  printf fd${bytes:0:2}:${bytes:2:4}:${bytes:4:4}::/64
}

# MARK: - pre

sudo apt-get update -yq
sudo apt-get install -y --no-install-recommends \
  bind9 \
  frr \
  qrencode \
  wireguard

# MARK: - networking

export VIP="172.16.254.0/24"
export IP4_RANGE="10.10.10.0/24"
export IP6_RANGE="$(ipv6)"

upstream_dns="1.1.1.1"
ipv4_net="$(printf ${IP4_RANGE} | cut -d '/' -f 1)"
ipv6_net="$(printf ${IP6_RANGE} | cut -d '/' -f 1)"

export allowed_ips="${IP4_RANGE}, ${IP6_RANGE}, ${VIP}"
export server_ip="$(ip route list default | awk '{ print $9 }')"
export wg_port=51820

# config network
sudo sed -i 's/[#]net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sed -i 's/[#]net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
sudo sysctl -p
sudo ufw allow ${wg_port}/udp
sudo ufw allow 6443/tcp
sudo ufw allow bgp
sudo ufw allow bind9
sudo ufw allow ssh

# reload firewall
sudo ufw --force disable
sudo ufw --force enable
sudo ufw status

# MARK: - bind
# TODO: bind

# MARK: - frr

# enable bgpd
sudo sed -i 's/bgpd=.*/bgpd=yes/g' /etc/frr/daemons
sudo systemctl enable frr.service
sudo systemctl restart frr.service

# generate config
envsubst < frr.conf.tmpl | sudo tee /etc/frr/frr.conf >/dev/null

# MARK: - wireguard

# create wg-quick@wg0.service
stat /etc/systemd/system/wg-quick@wg0.service >/dev/null ||
sudo cat <<eof >/etc/systemd/system/wg-quick@wg0.service
[Unit]
Description=WireGuard via wg-quick(8) for %I
After=network-online.target
Wants=network-online.target
ConditionPathExists=/etc/wireguard/%i.conf

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up %i
ExecStop=/usr/bin/wg-quick down %i
ExecReload=/usr/bin/wg-quick down %i; /usr/bin/wg-quick up %i

[Install]
WantedBy=multi-user.target
eof
sudo systemctl daemon-reload

# create server key pair
server_priv_key="/etc/wireguard/private.key"
server_pub_key="/etc/wireguard/public.key"
if ! sudo stat "${server_priv_key}" >/dev/null; then
  wg genkey | sudo tee "${server_priv_key}" >/dev/null
  sudo chmod go= "${server_priv_key}"
fi
sudo stat "${server_pub_key}" >/dev/null ||
sudo cat "${server_priv_key}" | wg pubkey | sudo tee "${server_pub_key}" >/dev/null

# create client key pair
client_priv_key="/etc/wireguard/client.private.key"
client_pub_key="/etc/wireguard/client.public.key"
if ! sudo stat "${client_priv_key}" >/dev/null; then
  wg genkey | sudo tee "${client_priv_key}" >/dev/null
  sudo chmod go= "${client_priv_key}"
fi
sudo stat "${client_pub_key}" >/dev/null ||
sudo cat "${client_priv_key}" | wg pubkey | sudo tee "${client_pub_key}" >/dev/null

# generate server config
if ! sudo stat /etc/wireguard/wg0.conf >/dev/null; then
  export privkey="$(sudo cat ${server_priv_key})"
  export pubkey="$(sudo cat ${client_pub_key})"
  export netdev="$(ip route list default | awk '{ print $5 }')"
  export ipv4_addr="$(printf ${ipv4_net%?}1)/24"
  export ipv6_addr="$(printf ${ipv6_net%?}:1)/64"

  envsubst < wireguard/wg0.conf.tmpl | sudo tee /etc/wireguard/wg0.conf >/dev/null
  sudo systemctl enable wg-quick@wg0.service
  sudo systemctl restart wg-quick@wg0.service
fi

# generate client config
if ! stat client.conf >/dev/null && ! stat client.png >/dev/null; then
  export privkey="$(sudo cat ${client_priv_key})"
  export pubkey="$(sudo cat ${server_pub_key})"
  export ipv4_addr="$(printf ${ipv4_net%?}2)/24"
  export ipv6_addr="$(printf ${ipv6_net%?}:2)/64"
  export dns_servers="${server_ip}, ${upstream_dns}"

  echo "ips: ${allowed_ips}"

  envsubst < wireguard/client.conf.tmpl | tee ~/client.conf >/dev/null
  qrencode -s 10 -l H -o ~/client.png < ~/client.conf
fi

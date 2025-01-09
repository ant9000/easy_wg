#!/bin/bash

DEFAULT_PORT=51820
DEFAULT_DEV=$(ip -j r show default | jq -r '.[].dev')

VPN_IFACE=$1
VPN_ADDR=$2
VPN_PORT=${3:-$DEFAULT_PORT}
WAN_DEV=${4:-$DEFAULT_DEV}
if [ -z "$VPN_IFACE" ] || [ -z "$VPN_ADDR" ]; then
  echo "Usage: $(basename $0) iface local_address [port] [wan dev]"
  echo "port and wan dev are optional, default to $DEFAULT_PORT, $DEFAULT_DEV respectively"
  echo ""
  exit 1
fi

cd "$(dirname $0)"
VPN_CONF="${VPN_IFACE}.conf"
if [ -f "$VPN_CONF" ]; then
  echo "Iface '$VPN_IFACE' already exists"
  exit 1
fi

ip_info=$(ipcalc-ng -j "$VPN_ADDR" 2>&1)
if [ $? != 0 ]; then
  echo "Wrong local address: ${ip_info/ipcalc-ng: /}"
  exit 1
fi
prefix=$(jq -r .PREFIX <<<$ip_info)
if [ $prefix -eq 32 ]; then
  echo "Wrong local address '$VPN_ADDR': please provide a network prefix smaller than 32 bits"
  exit 1
fi
address=$(jq -r .ADDRESS <<<$ip_info | cat)
broadcast=$(jq -r .BROADCAST <<<$ip_info)
if [[ "$address" == "null" || "$address" == "$broadcast" ]]; then
  echo "Wrong local address '$VPN_ADDR': please assign an IP within the network range"
  exit 1
fi

if ! [[ "$VPN_PORT" =~ ^[0-9]+$ && "$VPN_PORT" -ge 1 && "$VPN_PORT" -le 65535 ]]; then
  echo "Wrong port number '$VPN_PORT'"
  exit 1
fi

[ "$WAN_DEV" != "lo" ] && egrep -q "\b${WAN_DEV}:" /proc/net/dev
if [ "$?" != 0 ]; then
  echo "Invalid WAN interface '$WAN_DEV'"
  exit 1
fi

VPN_KEY=$(wg genkey)

cat >"$VPN_CONF" <<EOF
[Interface]
Address = $VPN_ADDR
ListenPort = $VPN_PORT
PrivateKey = $VPN_KEY
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $WAN_DEV -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $WAN_DEV -j MASQUERADE
EOF

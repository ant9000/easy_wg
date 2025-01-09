#!/bin/bash -e

DEFAULT_IFACE=wg0
DEFAULT_DNS=1.1.1.1
DEFAULT_ROUTES=0.0.0.0/0

PEER_NAME=$1
VPN_IFACE=${2:-$DEFAULT_IFACE}
DNS=${3:-$DEFAULT_DNS}
PEER_ROUTES=${4:-$DEFAULT_ROUTES}
if [ -z "$PEER_NAME" ]; then
  echo "Usage: $(basename $0) client-name [iface] [dns] [routes]"
  echo "Iface, DNS, routes are optional, and default to $DEFAULT_IFACE, $DEFAULT_DNS, $DEFAULT_ROUTES respectively"
  echo ""
  exit 1
fi

cd "$(dirname $0)"
VPN_CONF="${VPN_IFACE}.conf"
if [ ! -f "$VPN_CONF" ]; then
  echo "Invalid iface '$VPN_IFACE'"
  exit 1
fi
VPN_PEERS_DIR="${VPN_IFACE}-peers"
if [ -d "$VPN_PEERS_DIR" ] && [ -f "$VPN_PEERS_DIR/${PEER_NAME}.conf" ]; then
  echo "Client '$PEER_NAME' already exists"
  exit 1
fi
VPN_PUBLIC_IP=$(curl -s https://wtfismyip.com/text)
VPN_PORT=$(perl -ne'/ListenPort\s*=\s*(\d+)/ && print $1' "$VPN_CONF")
VPN_PUBKEY=$(perl -ne '/PrivateKey\s*=\s*(.*)/ && print $1' "$VPN_CONF" | wg pubkey)
VPN_NET=$(perl -ne '/Address\s*=\s*(.*)/ && print $1' "$VPN_CONF")

ip2num() { local ip=$1; IFS="./" read i1 i2 i3 i4 mask <<<"$ip"; echo "$(( ($i1<<24) + ($i2<<16) + ($i3<<8) + $i4 ))"; }
num2ip() { local num=$1; echo "$(($num>>24 & 0xff)).$(($num>>16 & 0xff)).$(($num>>8 & 0xff)).$(($num & 0xff))"; }

minip=$(ipcalc-ng --minaddr --no-decorate $VPN_NET)
maxip=$(ipcalc-ng --maxaddr --no-decorate $VPN_NET)
minnum=$(ip2num $minip)
maxnum=$(ip2num $maxip)

available=0
for num in $(seq $minnum $maxnum)
do
  PEER_ADDR=$(num2ip $num)
  egrep -qrs "Address\s*=\s*${PEER_ADDR//./\\.}/" "$VPN_CONF" "$VPN_PEERS_DIR" || available=1
  [ $available -eq 1 ] && break
done
if [ $available -eq 0 ]; then
  echo "No more clients in VPN subnet $VPN_NET"
  exit 1
fi
PEER_KEY=$(wg genkey)
PEER_PUBKEY=$(echo $PEER_KEY|wg pubkey)
SHARED_KEY=$(wg genkey)

[ -d "$VPN_PEERS_DIR" ] || mkdir "$VPN_PEERS_DIR"
cat >"${VPN_PEERS_DIR}/${PEER_NAME}.conf" <<EOF
[Interface]
Address = ${PEER_ADDR}/32
PrivateKey = $PEER_KEY
DNS = $DNS

[Peer]
PublicKey = $VPN_PUBKEY
PresharedKey = $SHARED_KEY
Endpoint = ${VPN_PUBLIC_IP}:${VPN_PORT}
AllowedIPs = $PEER_ROUTES
EOF

cat >>"$VPN_CONF" <<EOF

[Peer]
# $PEER_NAME
PublicKey = $PEER_PUBKEY
PresharedKey = $SHARED_KEY
AllowedIPs = ${PEER_ADDR}/32
EOF

egrep -q "\b${VPN_IFACE}:" /proc/net/dev && wg syncconf "$VPN_IFACE" <(wg-quick strip "$VPN_IFACE")
qrencode -t ANSIUTF8 < "$VPN_PEERS_DIR/${PEER_NAME}.conf"

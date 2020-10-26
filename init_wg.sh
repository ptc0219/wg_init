#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root !!!"
   exit 1
fi

if ! command -v wg &> /dev/null || ! command -v resolvconf &> /dev/null
then
    echo "Installing requirement..."
    apt update && apt install wireguard resolvconf
fi

if [ ! -f /etc/wireguard/server_privatekey ];
then
    echo "Generating keypairs..."
    umask 077
    wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey > /etc/wireguard/server_pubkey
fi

export LOCAL_PRIV_KEY=$(cat /etc/wireguard/server_privatekey)
export LOCAL_PUB_KEY=$(cat /etc/wireguard/server_pubkey)

echo -n "REMOTE_PUB_KEY: "
read REMOTE_PUB_KEY

echo -n "TUNNEL_IP <x.x.x.x/x>: "
read TUNNEL_IP

echo -n "ENDPOINT_HOST (IP or Domain): "
read ENDPOINT_HOST

echo -n "ENDPOINT_PORT (1-65535): "
read ENDPOINT_PORT

devs=""
for dev in $(ls /sys/class/net/ | grep -iE "en|eth" )
do
    devs="${dev} ${devs}"
done
devs=$(echo $devs | sed 's/ $//g')

echo -n "ETH_INTERFACE (values: ${devs}): "
read ETH_INTERFACE

echo -n "WG_INTERFACE <wgN> (e.g. wg0): "
read WG_INTERFACE

echo -n "WG_LISTEN_PORT (1-65535): "
read WG_LISTEN_PORT

(
cat << WG
[Interface]
  PrivateKey = ${LOCAL_PRIV_KEY}
  Address = ${TUNNEL_IP}
  PostUp   = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -A FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${ETH_INTERFACE} -j MASQUERADE
  PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -D FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${ETH_INTERFACE} -j MASQUERADE
  ListenPort = ${WG_LISTEN_PORT}
  Table = off
  DNS = 8.8.8.8
  MTU = 1420

[Peer]
  PublicKey = ${REMOTE_PUB_KEY}
  AllowedIPs = 0.0.0.0/0
  Endpoint = ${ENDPOINT_HOST}:${ENDPOINT_PORT}
WG
) > /etc/wireguard/${WG_INTERFACE}.conf

systemctl enable --now wg-quick@${WG_INTERFACE}

echo
echo "Everything done, Config: /etc/wireguard/${WG_INTERFACE}.conf"
echo "Public Key of this node: ${LOCAL_PUB_KEY}"

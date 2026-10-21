#!/bin/sh
# Brings up the WireGuard tunnel from this Alpine VM to the AWS server.
# Usage: sh wg-up.sh AWS_PUBLIC_IP

if [ -z "$1" ]; then
  echo "Usage: sh wg-up.sh AWS_PUBLIC_IP"
  exit 1
fi

for f in /etc/wireguard/lab.key /etc/wireguard/aws.pub; do
  if [ ! -f "$f" ]; then
    echo "Missing file: $f"
    exit 1
  fi
done

modprobe wireguard 2>/dev/null
ip link del wg0 2>/dev/null
ip link add wg0 type wireguard || exit 1
wg set wg0 private-key /etc/wireguard/lab.key
wg set wg0 peer "$(cat /etc/wireguard/aws.pub)" allowed-ips 10.99.0.1/32 endpoint "$1:51820" persistent-keepalive 25
ip addr add 10.99.0.2/30 dev wg0
ip link set wg0 up
echo "Tunnel interface is up. Waiting a few seconds for the handshake..."
sleep 5
wg show

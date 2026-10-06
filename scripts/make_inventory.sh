#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../terraform"

ips=$(terraform output -json public_ips | python3 -c "import sys,json; print('\n'.join(json.load(sys.stdin)))")

{
  echo "[fleet]"
  i=1
  for ip in $ips; do
    echo "fleet-node-0${i} ansible_host=${ip}"
    i=$((i+1))
  done
} > ../ansible/inventory.ini

echo "Wrote ansible/inventory.ini:"
cat ../ansible/inventory.ini

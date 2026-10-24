#!/usr/bin/env bash
# Installs Loki and Alloy on the Debian management VM.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root. Type: sudo -i"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nftables curl gpg ca-certificates

# Grafana repository (already there if Grafana was installed from it)
mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/grafana.gpg ]; then
  curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
fi
if [ ! -f /etc/apt/sources.list.d/grafana.list ]; then
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
fi
apt-get update
apt-get install -y loki alloy

# Loki: single node, files on disk, 7 days of history
mkdir -p /var/lib/loki
cat > /etc/loki/config.yml << 'EOF'
auth_enabled: false

server:
  log_level: warn
  http_listen_address: 0.0.0.0
  http_listen_port: 3100
  grpc_listen_address: 127.0.0.1
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-04-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 168h

compactor:
  working_directory: /var/lib/loki/compactor
  retention_enabled: true
  delete_request_store: filesystem

analytics:
  reporting_enabled: false
EOF
LOKI_USER=$(systemctl show -p User --value loki)
LOKI_USER=${LOKI_USER:-root}
chown -R "${LOKI_USER}" /var/lib/loki
chmod 644 /etc/loki/config.yml

# Soft memory cap so Loki cannot starve Grafana and Prometheus
mkdir -p /etc/systemd/system/loki.service.d
cat > /etc/systemd/system/loki.service.d/memory.conf << 'EOF'
[Service]
MemoryHigh=500M
EOF

# Firewall: port 3100 only from this VM and from the AWS tunnel address
cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet fleet {
  chain input {
    type filter hook input priority 0; policy accept;
    tcp dport 3100 iifname "lo" accept
    tcp dport 3100 iifname "wg0" ip saddr 10.99.0.1 accept
    tcp dport 3100 drop
  }
}
EOF
nft -c -f /etc/nftables.conf
systemctl enable nftables
nft -f /etc/nftables.conf

# Alloy: read this VM's journal and send it to the local Loki
ALLOY_USER=$(systemctl show -p User --value alloy)
if [ -n "${ALLOY_USER}" ] && [ "${ALLOY_USER}" != "root" ]; then
  usermod -aG systemd-journal "${ALLOY_USER}"
fi
cat > /etc/alloy/config.alloy << 'EOF'
loki.relabel "journal" {
  forward_to = []
  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
  rule {
    source_labels = ["__journal_priority_keyword"]
    target_label  = "level"
  }
}

loki.source.journal "read" {
  forward_to    = [loki.write.local.receiver]
  relabel_rules = loki.relabel.journal.rules
  labels        = { job = "systemd-journal", host = "mgmt-server", site = "lab" }
  max_age       = "12h"
}

loki.write "local" {
  endpoint {
    url = "http://localhost:3100/loki/api/v1/push"
  }
}
EOF
chmod 644 /etc/alloy/config.alloy

systemctl daemon-reload
systemctl enable loki alloy
systemctl restart loki alloy

echo "Waiting for Loki to be ready..."
for i in $(seq 1 30); do
  if curl -s localhost:3100/ready | grep -q ready; then
    echo "Loki is ready"
    break
  fi
  sleep 2
done

systemctl is-active loki alloy nftables
echo
free -h

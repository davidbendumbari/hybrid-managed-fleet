#!/usr/bin/env bash
# Installs Prometheus, node exporter and Grafana on the Debian management VM.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root. Type: sudo -i"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y prometheus prometheus-node-exporter wget gpg ca-certificates

# Keep Prometheus small: keep 7 days of data
if grep -q '^ARGS=' /etc/default/prometheus; then
  sed -i 's|^ARGS=.*|ARGS="--storage.tsdb.retention.time=7d"|' /etc/default/prometheus
else
  echo 'ARGS="--storage.tsdb.retention.time=7d"' >> /etc/default/prometheus
fi

cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 30s
  evaluation_interval: 30s

rule_files:
  - /etc/prometheus/rules.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: mgmt-server
    static_configs:
      - targets: ["localhost:9100"]
        labels:
          site: lab

  - job_name: aws-node
    static_configs:
      - targets: ["10.99.0.1:9100"]
        labels:
          site: aws-stockholm
EOF

cat > /etc/prometheus/rules.yml << 'EOF'
groups:
  - name: fleet
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.job }} is not answering"

      - alert: HighMemoryUse
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memory above 90 percent on {{ $labels.job }}"

      - alert: DiskAlmostFull
        expr: node_filesystem_avail_bytes{fstype=~"ext4|xfs"} / node_filesystem_size_bytes{fstype=~"ext4|xfs"} < 0.15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Less than 15 percent disk free on {{ $labels.job }}"
EOF

promtool check config /etc/prometheus/prometheus.yml

# Grafana from its official repository
mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y grafana

mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

systemctl daemon-reload
systemctl enable prometheus prometheus-node-exporter grafana-server
chown root:prometheus /etc/prometheus/prometheus.yml /etc/prometheus/rules.yml
chmod 640 /etc/prometheus/prometheus.yml /etc/prometheus/rules.yml
systemctl restart prometheus prometheus-node-exporter grafana-server
sleep 5

echo
echo "Service status:"
systemctl is-active prometheus prometheus-node-exporter grafana-server
echo
free -h
echo
echo "Grafana:    http://10.10.10.60:3000"
echo "Prometheus: http://10.10.10.60:9090"

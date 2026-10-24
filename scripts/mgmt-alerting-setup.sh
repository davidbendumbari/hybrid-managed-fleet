#!/usr/bin/env bash
# Sets up Alertmanager with Telegram alerts on the Debian management VM.
# Secrets are read from files in the shared folder and never stored in Git.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root. Type: sudo -i"
  exit 1
fi

TOKEN_FILE=/mnt/share/tg-token.txt
CHAT_FILE=/mnt/share/tg-chat.txt

for f in "$TOKEN_FILE" "$CHAT_FILE"; do
  [ -f "$f" ] || { echo "Missing file: $f"; exit 1; }
done

TOKEN=$(tr -d ' \r\n\t' < "$TOKEN_FILE")
CHAT=$(tr -d ' \r\n\t' < "$CHAT_FILE")

if ! echo "$TOKEN" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]+$'; then
  echo "The token file does not look like a Telegram bot token."
  exit 1
fi
if ! echo "$CHAT" | grep -Eq '^-?[0-9]+$'; then
  echo "The chat ID file should contain only a number."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y prometheus-alertmanager

cat > /etc/prometheus/alertmanager.yml << EOF
route:
  receiver: telegram
  group_by: [alertname, job]
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 4h

receivers:
  - name: telegram
    telegram_configs:
      - bot_token: "${TOKEN}"
        chat_id: ${CHAT}
        send_resolved: true
EOF
chown root:prometheus /etc/prometheus/alertmanager.yml
chmod 640 /etc/prometheus/alertmanager.yml
amtool check-config /etc/prometheus/alertmanager.yml

# Keep Alertmanager local only, and turn off clustering (single node)
cat > /etc/default/prometheus-alertmanager << 'EOF'
ARGS="--config.file=/etc/prometheus/alertmanager.yml --web.listen-address=127.0.0.1:9093 --cluster.listen-address="
EOF

if ! grep -q '^alerting:' /etc/prometheus/prometheus.yml; then
  cat >> /etc/prometheus/prometheus.yml << 'EOF'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["localhost:9093"]
EOF
fi
chown root:prometheus /etc/prometheus/prometheus.yml /etc/prometheus/rules.yml
chmod 640 /etc/prometheus/prometheus.yml /etc/prometheus/rules.yml
promtool check config /etc/prometheus/prometheus.yml

systemctl enable prometheus-alertmanager
systemctl restart prometheus-alertmanager prometheus
sleep 5
systemctl is-active prometheus-alertmanager prometheus

amtool alert add alertname=TestAlert severity=info job=lab \
  --annotation=summary="Test alert from the monitoring VM" \
  --alertmanager.url=http://localhost:9093

# Remove the secret files from the shared folder
rm -f "$TOKEN_FILE" "$CHAT_FILE"

echo "Done. A test message should reach Telegram within about 30 seconds."
free -h

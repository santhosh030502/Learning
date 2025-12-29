#!/bin/bash
set -e

# === CONFIGURATION === #
BUNDLE_DIR="/opt/bundle"
INSTALL_DIR="/opt/cas"
ES_CONFIG_DIR="/etc/elasticsearch"
ES_YML="$ES_CONFIG_DIR/elasticsearch.yml"
LOG_DIR="$INSTALL_DIR/es_logs"
HOST_IP="192.168.2.219"
EPOCH_TIME=$(($(date +%s%N)/1000000))

ES_USER="elastic"
ES_PASS="Pa55w0rd"

# Certificates
CERT_DIR="$ES_CONFIG_DIR/certs"
KEY_FILE="$CERT_DIR/cas.key"
CRT_FILE="$CERT_DIR/cas.crt"
PEM_FILE="$CERT_DIR/cas.pem"

# === LOG FILES === #
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup.log"

# === INSTALL JAVA === #
echo "Installing Java..." | tee -a "$LOG_FILE"
rpm -ivh --force "$BUNDLE_DIR/jdk-17.0.12_linux-x64_bin.rpm" >> "$LOG_FILE" 2>&1 || true
export JAVA_HOME="/usr/java/latest"
export PATH="$JAVA_HOME/bin:$PATH"
echo "JAVA_HOME set to $JAVA_HOME" | tee -a "$LOG_FILE"

# === INSTALL ELASTICSEARCH === #
echo "Installing Elasticsearch..." | tee -a "$LOG_FILE"
rpm -ivh --force "$BUNDLE_DIR/elasticsearch-7.17.0-x86_64.rpm" >> "$LOG_FILE" 2>&1 || true

# --- Create elasticsearch user & group if not exist ---
if ! id elasticsearch &>/dev/null; then
    echo "Creating elasticsearch user and group..." | tee -a "$LOG_FILE"
    groupadd elasticsearch
    useradd -r -g elasticsearch -s /sbin/nologin elasticsearch
fi

# --- Fix permissions ---
chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /usr/share/elasticsearch

# Enable service
systemctl daemon-reload
systemctl enable elasticsearch

# === GENERATE CERTIFICATES === #
echo "Generating self-signed certificates..." | tee -a "$LOG_FILE"
mkdir -p "$CERT_DIR"

# Generate private key
openssl genrsa -out "$KEY_FILE" 2048

# Generate self-signed certificate with SAN for IP
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -key "$KEY_FILE" -out "$CRT_FILE" \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$HOST_IP" \
  -addext "subjectAltName=IP:$HOST_IP"

# Combine key and cert to create PEM file
cat "$KEY_FILE" "$CRT_FILE" > "$PEM_FILE"

# Set permissions
chown -R elasticsearch:elasticsearch "$CERT_DIR"

# === CONFIGURE elasticsearch.yml === #
echo "Configuring elasticsearch.yml..." | tee -a "$LOG_FILE"
if [ -f "$ES_YML" ]; then
    cp "$ES_YML" "$ES_CONFIG_DIR/elasticsearch.yml.bak"
fi

cat > "$ES_YML" <<EOF
# ----------------------- Basic Config -----------------------
cluster.name: cas-oversight
node.name: node-1
node.master: true
node.data: true
node.max_local_storage_nodes: 1
discovery.type: single-node

# ---------------------- Network Config ----------------------
network.host: $HOST_IP
http.port: 9200
transport.port: 9300

# ----------------------- Security Config ----------------------
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.http.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.http.ssl.key: $KEY_FILE
xpack.security.http.ssl.certificate: $CRT_FILE

# ---------------------- Paths ----------------------
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

xpack.security.authc:
  realms:
    native:
      native1:
        order: 0
EOF

chown elasticsearch:elasticsearch "$ES_YML"

# === CLEAN OLD DATA === #
rm -rf /var/lib/elasticsearch/*
rm -f /etc/elasticsearch/elasticsearch.keystore
journalctl --rotate
journalctl --vacuum-time=1s

# === CREATE KEYSTORE AND SET BOOTSTRAP PASSWORD BEFORE FIRST START === #
echo "Creating Elasticsearch keystore and setting bootstrap password..." | tee -a "$LOG_FILE"
sudo -u elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore create
echo "$ES_PASS" | sudo -u elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore add -x "bootstrap.password"
chown elasticsearch:elasticsearch /etc/elasticsearch/elasticsearch.keystore

# === START ELASTICSEARCH === #
echo "Starting Elasticsearch..." | tee -a "$LOG_FILE"
systemctl restart elasticsearch

# === WAIT FOR ELASTICSEARCH TO BE READY (SSL) === #
for i in {1..60}; do
    if curl -s "https://$HOST_IP:9200" --insecure >/dev/null; then
        echo "✅ Elasticsearch is up and running!" | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    if [ $i -eq 60 ]; then
        echo "❌ Elasticsearch did not start in time." >&2
        exit 1
    fi
done

# === VERIFY ELASTIC USER LOGIN === #
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u $ES_USER:$ES_PASS "https://$HOST_IP:9200" --insecure)
if [ "$STATUS" != "200" ]; then
    echo "❌ Elasticsearch setup failed. Check logs." >&2
    exit 1
fi

echo "🎉 Elasticsearch onboarding complete!"
echo "Login with:"
echo "Username: $ES_USER"
echo "Password: $ES_PASS"
echo "URL: https://$HOST_IP:9200"

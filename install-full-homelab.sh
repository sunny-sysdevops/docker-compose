#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/homelab"
TUNNEL_ID="${CLOUDFLARE_TUNNEL_ID:-96a958a5-5fca-42e5-98e6-ed648b3f7f9f}"
TUNNEL_JSON_CONTENT="${CLOUDFLARE_TUNNEL_JSON:-}"

if [ "${EUID}" -ne 0 ]; then
  echo "Please run as root or via sudo."
  exit 1
fi

if [ -n "${TUNNEL_JSON_CONTENT}" ]; then
  mkdir -p /etc/cloudflared
  printf '%s' "$TUNNEL_JSON_CONTENT" > "/etc/cloudflared/${TUNNEL_ID}.json"
fi

if [ ! -f "/etc/cloudflared/${TUNNEL_ID}.json" ]; then
  echo "Cloudflare tunnel credentials are missing."
  echo "Create the tunnel in Cloudflare Zero Trust, then either:"
  echo "  1) export CLOUDFLARE_TUNNEL_ID and CLOUDFLARE_TUNNEL_JSON, or"
  echo "  2) save the JSON to /etc/cloudflared/${TUNNEL_ID}.json"
  echo "Example:"
  echo "  sudo mkdir -p /etc/cloudflared"
  echo "  sudo cp /path/to/tunnel.json /etc/cloudflared/${TUNNEL_ID}.json"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release git

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  usermod -aG docker "$SUDO_USER" || true
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  curl -L --output /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  dpkg -i /tmp/cloudflared.deb
fi

mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  git clone https://github.com/sunny-sysdevops/docker-compose.git "$APP_DIR"
fi

mkdir -p "$APP_DIR"/{downloads,pihole/etc,pihole/dnsmasq,ndata,dashboard,glance,uptime-kuma,npm/data,npm/letsencrypt,tailscale}

cat > /etc/cloudflared/config.yml <<EOF
# Cloudflare Tunnel config for homelab
# Tunnel ID: ${TUNNEL_ID}
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: dashboard.thesunny.net
    service: http://localhost:3000
  - hostname: downtify.thesunny.net
    service: http://localhost:30321
  - hostname: kuma.thesunny.net
    service: http://localhost:3001
  - hostname: portainer.thesunny.net
    service: http://localhost:9000
  - hostname: pihole.thesunny.net
    service: http://localhost:8080
  - hostname: nexus.thesunny.net
    service: http://localhost:8082
  - hostname: npm.thesunny.net
    service: http://localhost:81
  - hostname: glance.thesunny.net
    service: http://localhost:8081
  - service: http_status:404
EOF

cat > "$APP_DIR/start-homelab.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="/opt/homelab"
cd "$APP_DIR"
CMD="${1:-start}"
case "$CMD" in
  start)
    docker compose up -d --remove-orphans
    ;;
  stop)
    docker compose down
    ;;
  restart)
    docker compose down
    docker compose up -d --remove-orphans
    ;;
  status)
    docker compose ps
    ;;
  logs)
    docker compose logs -f --tail=200
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
SH
chmod +x "$APP_DIR/start-homelab.sh"

cat > /etc/systemd/system/homelab.service <<'SVC'
[Unit]
Description=Homelab stack via Docker Compose
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/homelab
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose up -d --force-recreate --remove-orphans

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now docker

cd "$APP_DIR"
docker compose up -d --remove-orphans

cloudflared service install || true
systemctl enable --now cloudflared || true

systemctl enable --now homelab.service

echo "==============================================="
echo "Homelab setup complete."
echo "Repo: ${APP_DIR}"
echo "Docker compose: ${APP_DIR}/docker-compose.yml"
echo "Tunnel config: /etc/cloudflared/config.yml"
echo "Credentials: /etc/cloudflared/${TUNNEL_ID}.json"
echo "Local URLs:"
echo "  http://localhost:3000  (dashboard)"
echo "  http://localhost:3001  (uptime kuma)"
echo "  http://localhost:9000  (portainer)"
echo "  http://localhost:30321 (downtify)"
echo "  http://localhost:8080  (pihole)"
echo "  http://localhost:8081  (glance)"
echo "  http://localhost:81    (nginx proxy manager)"
echo "==============================================="

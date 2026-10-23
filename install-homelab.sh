#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/homelab"
TUNNEL_ID="96a958a5-5fca-42e5-98e6-ed648b3f7f9f"

sudo mkdir -p "$APP_DIR"/{downloads,pihole/etc,pihole/dnsmasq,ndata,dashboard,glance,uptime-kuma,npm/data,npm/letsencrypt,tailscale}

if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
  echo "Copying docker-compose.yml..."
  sudo cp /path/to/this/repo/docker-compose.yml "$APP_DIR/docker-compose.yml"
fi

mkdir -p /etc/cloudflared
if [ ! -f "/etc/cloudflared/config.yml" ]; then
  sudo tee /etc/cloudflared/config.yml >/dev/null <<CFG

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
CFG
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "Installing Cloudflared..."
  sudo mkdir -p /tmp/cloudflared
  cd /tmp/cloudflared
  curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  sudo dpkg -i cloudflared.deb
fi

if [ ! -f "/etc/cloudflared/${TUNNEL_ID}.json" ]; then
  echo "Missing Cloudflare tunnel credentials: /etc/cloudflared/${TUNNEL_ID}.json"
  echo "Create the tunnel in Cloudflare Zero Trust, then copy the JSON here and rerun this script."
  exit 1
fi

cd "$APP_DIR"
sudo docker compose up -d

echo "Docker Compose stack is running."
echo "Open: http://localhost:3000 for dashboard"
echo "Open: http://localhost:30321 for downtify"

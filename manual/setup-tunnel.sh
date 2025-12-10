#!/bin/bash
set -euo pipefail

GUARD_ID=100
BRAIN_IP="10.0.0.200"

echo "=== Cloudflare Tunnel Setup ==="
echo ""
echo "You need your Cloudflare Tunnel Token"
echo "Get it from: https://one.dash.cloudflare.com/ > Access > Tunnels"
echo ""
read -p "Enter your Cloudflare Tunnel Token: " TUNNEL_TOKEN

if [ -z "$TUNNEL_TOKEN" ]; then
    echo "ERROR: Token cannot be empty"
    exit 1
fi

echo ""
read -p "Enter your domain (e.g., yourdomain.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "ERROR: Domain cannot be empty"
    exit 1
fi

# Configure tunnel in Guard container
pct exec $GUARD_ID -- bash -c "
    mkdir -p /etc/cloudflared
    cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_TOKEN
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: nomad.$DOMAIN
    service: http://$BRAIN_IP:4646
  - hostname: dashboard.$DOMAIN
    service: http://$BRAIN_IP:8080
  - service: http_status:404
EOF

    cat > /etc/cloudflared/credentials.json <<EOF
{
  \"TunnelSecret\": \"$TUNNEL_TOKEN\"
}
EOF

    # Install as service
    cloudflared service install
    systemctl enable cloudflared
    systemctl start cloudflared
"

echo ""
echo "✓ Tunnel configured!"
echo ""
echo "Access URLs:"
echo "  Nomad UI:   https://nomad.$DOMAIN"
echo "  Dashboard:  https://dashboard.$DOMAIN"
echo ""
echo "Check tunnel status:"
echo "  pct exec $GUARD_ID -- systemctl status cloudflared"
echo ""
echo "Note: Make sure you've configured DNS records in Cloudflare dashboard:"
echo "  nomad.$DOMAIN -> CNAME to your tunnel"
echo "  dashboard.$DOMAIN -> CNAME to your tunnel"

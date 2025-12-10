# OOPUO Quick Start Guide

## Prerequisites

Before running the installer, ensure you have:

1. **Proxmox VE** installed on bare metal
2. **Root SSH access** to the Proxmox host
3. **Network configuration**:
   - A bridge (default: vmbr0)
   - Available IPs (default: 10.0.0.100-200)
   - Gateway configured (default: 10.0.0.1)
4. **Cloudflare account** (free tier is fine)
5. **Storage** configured in Proxmox (default: local-lvm)

## Installation Steps

### Step 1: Transfer Files to Proxmox

From your local machine:

```bash
# Create directory on Proxmox
ssh root@YOUR_PROXMOX_IP "mkdir -p /root/oopuo"

# Transfer the files
scp -r oopuo-nomad-prototype/* root@YOUR_PROXMOX_IP:/root/oopuo/

# SSH into Proxmox
ssh root@YOUR_PROXMOX_IP
cd /root/oopuo
```

### Step 2: Customize Configuration (Optional)

Edit `install.sh` if you need different settings:

```bash
nano install.sh

# Change these if needed:
GUARD_ID=100              # LXC container ID
BRAIN_ID=200              # VM ID
GUARD_IP="10.0.0.100/24"  # Guard IP address
BRAIN_IP="10.0.0.200/24"  # Brain IP address
GATEWAY="10.0.0.1"        # Your network gateway
BRIDGE="vmbr0"            # Proxmox bridge name
STORAGE="local-lvm"       # Storage pool name
```

### Step 3: Run the Installer

```bash
chmod +x install.sh
./install.sh
```

This will take 5-10 minutes and will:
- Download Ubuntu templates
- Create Guard LXC container (ID 100)
- Create Brain VM (ID 200)
- Install Cloudflare Tunnel in Guard
- Install Nomad + Docker in Brain

### Step 4: Configure Cloudflare Tunnel

Two options:

#### Option A: Automated Script

```bash
chmod +x setup-tunnel.sh
./setup-tunnel.sh
```

You'll need:
- Your Cloudflare Tunnel Token (from dashboard)
- Your domain name (e.g., yourdomain.com)

#### Option B: Manual Configuration

```bash
# Enter Guard container
pct enter 100

# Login to Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create oopuo

# Configure DNS
cloudflared tunnel route dns oopuo dashboard.yourdomain.com
cloudflared tunnel route dns oopuo nomad.yourdomain.com

# Create config file
nano /etc/cloudflared/config.yml
```

Paste:
```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: nomad.yourdomain.com
    service: http://10.0.0.200:4646
  - hostname: dashboard.yourdomain.com
    service: http://10.0.0.200:8080
  - service: http_status:404
```

Start tunnel:
```bash
cloudflared service install
systemctl enable cloudflared
systemctl start cloudflared
exit
```

### Step 5: Deploy Dashboard

```bash
# SSH into Brain VM
ssh ubuntu@10.0.0.200
# Password: oopuo2024

# Create directory
sudo mkdir -p /opt/oopuo/dashboard

# Exit and copy files from Proxmox
exit

# From Proxmox host
scp dashboard/* ubuntu@10.0.0.200:/tmp/
ssh ubuntu@10.0.0.200 "sudo mv /tmp/main.py /tmp/dashboard.nomad /opt/oopuo/dashboard/"

# Deploy via Nomad
ssh ubuntu@10.0.0.200
nomad job run /opt/oopuo/dashboard/dashboard.nomad
```

### Step 6: Verify Installation

```bash
# Check Guard status
pct exec 100 -- systemctl status cloudflared

# Check Brain status
ssh ubuntu@10.0.0.200 "
    systemctl status nomad
    nomad server members
    nomad node status
"

# Try the TUI dashboard
ssh ubuntu@10.0.0.200
python3 /opt/oopuo/dashboard/main.py
# Press 'Q' to quit
```

## Access Points

After installation:

| Service | URL | Access From |
|---------|-----|-------------|
| Nomad UI | http://10.0.0.200:4646 | Proxmox host |
| Nomad UI (Tunnel) | https://nomad.yourdomain.com | Anywhere |
| Dashboard | http://10.0.0.200:8080 | Proxmox host |
| Dashboard (Tunnel) | https://dashboard.yourdomain.com | Anywhere |
| TUI Dashboard | SSH to Brain, run main.py | SSH |
| Guard Container | `pct enter 100` | Proxmox host |
| Brain VM | `ssh ubuntu@10.0.0.200` | Proxmox host |

## Common Commands

### Check Status
```bash
# Guard container
pct status 100
pct exec 100 -- systemctl status cloudflared

# Brain VM
qm status 200
ssh ubuntu@10.0.0.200 "systemctl status nomad"
```

### View Logs
```bash
# Guard logs
pct exec 100 -- journalctl -u cloudflared -f

# Brain logs
ssh ubuntu@10.0.0.200 "journalctl -u nomad -f"
```

### Restart Services
```bash
# Restart Guard tunnel
pct exec 100 -- systemctl restart cloudflared

# Restart Brain Nomad
ssh ubuntu@10.0.0.200 "sudo systemctl restart nomad"
```

### Deploy Sample AI Service
```bash
ssh ubuntu@10.0.0.200
nomad job run /opt/oopuo/dashboard/ollama.nomad

# Check status
nomad job status ollama

# Test it
curl http://localhost:11434/api/version
```

## Troubleshooting

### VM Won't Start
```bash
qm status 200
tail -f /var/log/pve/tasks/qmstart-200-*.log
```

### No Network in VM
```bash
ssh ubuntu@10.0.0.200
sudo cloud-init status
ip addr show
```

### Nomad Won't Start
```bash
ssh ubuntu@10.0.0.200
sudo journalctl -u nomad -n 100 --no-pager
sudo systemctl status nomad
```

### Tunnel Not Connecting
```bash
pct exec 100 -- systemctl status cloudflared
pct exec 100 -- journalctl -u cloudflared -n 50
pct exec 100 -- cloudflared tunnel info
```

### Can't SSH to Brain
```bash
# From Proxmox host
qm terminal 200
# Login: ubuntu / oopuo2024

# Check networking
ip addr show
ip route show
ping 8.8.8.8
```

## Next Steps

1. **Secure the installation**:
   - Change default password: `ssh ubuntu@10.0.0.200 "passwd"`
   - Add SSH keys
   - Configure firewall

2. **Add more services**:
   - Deploy Ollama for LLM inference
   - Add JupyterLab
   - Install Coolify

3. **Enhance dashboard**:
   - Add tmux integration
   - Add systemd service for auto-start
   - Implement the "Time Machine" snapshot UI

4. **Scale up**:
   - Add Consul for service discovery
   - Add Vault for secrets management
   - Prepare for multi-node federation

## Getting Help

If you encounter issues:

1. Check logs using commands above
2. Verify network connectivity
3. Ensure storage has enough space: `df -h`
4. Check Proxmox resources: `pvesh get /nodes/YOUR_NODE/status`

## File Structure

```
/root/oopuo/
├── PROJECT_PLAN.md          # Comprehensive project documentation
├── QUICKSTART.md            # This file
├── install.sh               # Main installer
├── setup-tunnel.sh          # Tunnel configurator
└── dashboard/
    ├── main.py              # TUI dashboard
    ├── dashboard.nomad      # Nomad job for web UI
    └── ollama.nomad         # Sample AI service
```

## Default Credentials

- **Brain VM SSH**: ubuntu / oopuo2024
- **Proxmox Root**: (your existing password)
- **Cloudflare**: (your account credentials)

**IMPORTANT**: Change default passwords in production!

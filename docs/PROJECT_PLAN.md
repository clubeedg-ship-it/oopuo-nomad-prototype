# OOPUO-Nomad Prototype: Day 1 Deployment Plan

**Objective**: Build a working prototype that installs on your Proxmox server and connects via Cloudflare Tunnel TODAY.

**Timeline**: 4-6 hours for a skilled coding agent
**Target**: Functional system you can SSH into and see working

---

## PHASE 0: Prerequisites Check (15 min)

### Environment Requirements
- Proxmox VE host (bare metal)
- Root SSH access to Proxmox
- Cloudflare account with tunnel token ready
- Internet connectivity

### What You Need Before Starting
```bash
# From your local machine, ensure you can:
ssh root@your-proxmox-ip

# You need:
# 1. Cloudflare Tunnel Token (get from: https://one.dash.cloudflare.com/)
# 2. Your Proxmox IP address
# 3. Your desired VM IPs (e.g., 10.0.0.100 for Guard, 10.0.0.200 for Brain)
```

---

## PHASE 1: Foundation Setup (45 min)

### 1.1 Create the Installation Script
Create a single bash installer that will:
- Run on Proxmox host
- Create two containers: Guard (LXC) and Brain (VM)
- Install all dependencies
- Configure networking

**File**: `install.sh`

```bash
#!/bin/bash
set -euo pipefail

# Configuration Variables
GUARD_ID=100
BRAIN_ID=200
GUARD_IP="10.0.0.100/24"
BRAIN_IP="10.0.0.200/24"
GATEWAY="10.0.0.1"
BRIDGE="vmbr0"
STORAGE="local-lvm"

echo "=== OOPUO-Nomad Installer v1.0 ==="
echo "This will deploy the Guard and Brain architecture"
echo ""

# Check if running on Proxmox
if ! command -v pveversion &> /dev/null; then
    echo "ERROR: This must run on a Proxmox VE host"
    exit 1
fi

# Function: Create LXC Container (The Guard)
create_guard() {
    echo "[1/4] Creating Guard LXC Container (ID: $GUARD_ID)..."
    
    # Download Ubuntu 24.04 template if not exists
    if [ ! -f /var/lib/vz/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst ]; then
        pveam update
        pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst
    fi
    
    # Destroy existing container if exists
    if pct status $GUARD_ID &>/dev/null; then
        echo "  Destroying existing Guard container..."
        pct stop $GUARD_ID || true
        pct destroy $GUARD_ID
    fi
    
    # Create new container
    pct create $GUARD_ID \
        local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
        --hostname guard \
        --cores 2 \
        --memory 2048 \
        --swap 512 \
        --net0 name=eth0,bridge=$BRIDGE,ip=$GUARD_IP,gw=$GATEWAY \
        --storage $STORAGE \
        --rootfs $STORAGE:8 \
        --unprivileged 1 \
        --features nesting=1 \
        --onboot 1
    
    # Start container
    pct start $GUARD_ID
    sleep 5
    
    echo "  Guard container created successfully!"
}

# Function: Create VM (The Brain)
create_brain() {
    echo "[2/4] Creating Brain VM (ID: $BRAIN_ID)..."
    
    # Download Ubuntu cloud image if not exists
    if [ ! -f /var/lib/vz/template/iso/ubuntu-24.04-server-cloudimg-amd64.img ]; then
        echo "  Downloading Ubuntu 24.04 cloud image..."
        wget -O /var/lib/vz/template/iso/ubuntu-24.04-server-cloudimg-amd64.img \
            https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
    fi
    
    # Destroy existing VM if exists
    if qm status $BRAIN_ID &>/dev/null; then
        echo "  Destroying existing Brain VM..."
        qm stop $BRAIN_ID || true
        qm destroy $BRAIN_ID
    fi
    
    # Create VM
    qm create $BRAIN_ID \
        --name brain \
        --cores 4 \
        --memory 8192 \
        --net0 virtio,bridge=$BRIDGE \
        --scsihw virtio-scsi-pci
    
    # Import disk
    qm importdisk $BRAIN_ID \
        /var/lib/vz/template/iso/ubuntu-24.04-server-cloudimg-amd64.img \
        $STORAGE
    
    # Attach disk
    qm set $BRAIN_ID \
        --scsi0 $STORAGE:vm-$BRAIN_ID-disk-0 \
        --boot order=scsi0 \
        --serial0 socket \
        --vga serial0
    
    # Add cloud-init drive
    qm set $BRAIN_ID --ide2 $STORAGE:cloudinit
    
    # Configure cloud-init
    qm set $BRAIN_ID \
        --ciuser ubuntu \
        --cipassword oopuo2024 \
        --ipconfig0 ip=$BRAIN_IP,gw=$GATEWAY \
        --nameserver 8.8.8.8 \
        --onboot 1
    
    # Start VM
    qm start $BRAIN_ID
    
    echo "  Brain VM created successfully!"
    echo "  Waiting 30s for VM to boot..."
    sleep 30
}

# Function: Install Guard Services
setup_guard() {
    echo "[3/4] Setting up Guard services..."
    
    # Wait for container to be ready
    for i in {1..30}; do
        if pct exec $GUARD_ID -- test -d /root; then
            break
        fi
        sleep 2
    done
    
    # Update and install dependencies
    pct exec $GUARD_ID -- bash -c "
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            curl \
            gnupg \
            lsb-release \
            ca-certificates
    "
    
    echo "  Installing Cloudflare Tunnel..."
    pct exec $GUARD_ID -- bash -c "
        curl -L https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-archive-keyring.gpg >/dev/null
        echo \"deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared \$(lsb_release -cs) main\" | tee /etc/apt/sources.list.d/cloudflared.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared
    "
    
    echo "  Guard setup complete!"
}

# Function: Install Brain Services
setup_brain() {
    echo "[4/4] Setting up Brain services..."
    
    # Extract IP without subnet mask
    BRAIN_IP_ADDR=$(echo $BRAIN_IP | cut -d'/' -f1)
    
    # Wait for SSH to be available
    echo "  Waiting for Brain SSH..."
    for i in {1..60}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 ubuntu@$BRAIN_IP_ADDR "echo ready" &>/dev/null; then
            break
        fi
        sleep 2
    done
    
    # Install Nomad
    echo "  Installing Nomad..."
    ssh ubuntu@$BRAIN_IP_ADDR "
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nomad
    "
    
    # Install Docker
    echo "  Installing Docker..."
    ssh ubuntu@$BRAIN_IP_ADDR "
        curl -fsSL https://get.docker.com | sudo bash
        sudo usermod -aG docker ubuntu
    "
    
    # Create Nomad config
    echo "  Configuring Nomad..."
    ssh ubuntu@$BRAIN_IP_ADDR "sudo mkdir -p /etc/nomad.d"
    
    cat > /tmp/nomad.hcl <<'EOF'
datacenter = "oopuo-edge"
data_dir = "/opt/nomad/data"

server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
}

plugin "docker" {
  config {
    allow_privileged = true
  }
}
EOF
    
    scp /tmp/nomad.hcl ubuntu@$BRAIN_IP_ADDR:/tmp/
    ssh ubuntu@$BRAIN_IP_ADDR "sudo mv /tmp/nomad.hcl /etc/nomad.d/nomad.hcl"
    
    # Start Nomad
    ssh ubuntu@$BRAIN_IP_ADDR "
        sudo systemctl enable nomad
        sudo systemctl start nomad
    "
    
    echo "  Brain setup complete!"
}

# Main execution
main() {
    create_guard
    create_brain
    setup_guard
    setup_brain
    
    echo ""
    echo "=== Installation Complete! ==="
    echo ""
    echo "Access Points:"
    echo "  Guard (LXC):  pct enter $GUARD_ID"
    echo "  Brain (SSH):  ssh ubuntu@$(echo $BRAIN_IP | cut -d'/' -f1)"
    echo "  Brain (VM):   qm terminal $BRAIN_ID"
    echo ""
    echo "Nomad UI: http://$(echo $BRAIN_IP | cut -d'/' -f1):4646"
    echo ""
    echo "Next Steps:"
    echo "  1. Configure Cloudflare Tunnel in Guard container"
    echo "  2. Deploy OOPUO Dashboard via Nomad"
    echo "  3. Access via tunnel URL"
}

main
```

### 1.2 Make Executable and Run
```bash
chmod +x install.sh
./install.sh
```

**Expected Output**: Two containers created, Nomad running, ready for services.

---

## PHASE 2: Cloudflare Tunnel Configuration (30 min)

### 2.1 Configure the Tunnel

**File**: `setup-tunnel.sh`

```bash
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

# Configure tunnel in Guard container
pct exec $GUARD_ID -- bash -c "
    mkdir -p /etc/cloudflared
    cat > /etc/cloudflared/config.yml <<EOF
tunnel: $(echo $TUNNEL_TOKEN | cut -d'.' -f1)
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: nomad.yourdomain.com
    service: http://$BRAIN_IP:4646
  - hostname: dashboard.yourdomain.com
    service: http://$BRAIN_IP:8080
  - service: http_status:404
EOF

    cat > /etc/cloudflared/credentials.json <<EOF
{
  \"AccountTag\": \"your-account-id\",
  \"TunnelSecret\": \"$TUNNEL_TOKEN\",
  \"TunnelID\": \"$(echo $TUNNEL_TOKEN | cut -d'.' -f1)\"
}
EOF

    # Install as service
    cloudflared service install
    systemctl enable cloudflared
    systemctl start cloudflared
"

echo ""
echo "Tunnel configured! Check status:"
echo "  pct exec $GUARD_ID -- systemctl status cloudflared"
```

### 2.2 Alternative: Manual Quick Setup
If the above is too complex, use the interactive installer inside the Guard:

```bash
pct enter 100
cloudflared tunnel login
cloudflared tunnel create oopuo
cloudflared tunnel route dns oopuo dashboard.yourdomain.com
# Create config.yml manually
systemctl enable --now cloudflared
```

---

## PHASE 3: OOPUO Dashboard Deployment (60 min)

### 3.1 Create the Dashboard Application

**File**: `dashboard/main.py`

```python
#!/usr/bin/env python3
"""
OOPUO Dashboard - Prototype v1.0
A simple TUI that shows system status and provides navigation
"""

import curses
import subprocess
import time
from datetime import datetime

class Dashboard:
    def __init__(self, stdscr):
        self.stdscr = stdscr
        self.height, self.width = stdscr.getmaxyx()
        curses.curs_set(0)  # Hide cursor
        stdscr.nodelay(1)   # Non-blocking input
        stdscr.timeout(1000)  # Refresh every second
        
        # Initialize colors
        curses.start_color()
        curses.init_pair(1, curses.COLOR_CYAN, curses.COLOR_BLACK)
        curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)
        curses.init_pair(3, curses.COLOR_YELLOW, curses.COLOR_BLACK)
        curses.init_pair(4, curses.COLOR_RED, curses.COLOR_BLACK)
        
    def get_system_info(self):
        """Gather system metrics"""
        try:
            # CPU info
            cpu_cmd = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
            cpu_usage = subprocess.check_output(cpu_cmd, shell=True).decode().strip()
            
            # Memory info
            mem_cmd = "free | grep Mem | awk '{printf \"%.1f\", $3/$2 * 100}'"
            mem_usage = subprocess.check_output(mem_cmd, shell=True).decode().strip()
            
            # Nomad status
            nomad_cmd = "systemctl is-active nomad || echo 'inactive'"
            nomad_status = subprocess.check_output(nomad_cmd, shell=True).decode().strip()
            
            return {
                'cpu': float(cpu_usage),
                'mem': float(mem_usage),
                'nomad': nomad_status,
                'time': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
        except:
            return {
                'cpu': 0.0,
                'mem': 0.0,
                'nomad': 'unknown',
                'time': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
    
    def draw_header(self):
        """Draw the top header bar"""
        header = "╔═══ OOPUO ENTERPRISE ═══╗"
        self.stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
        self.stdscr.addstr(0, 0, header.center(self.width))
        self.stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)
        
    def draw_metrics(self, info):
        """Draw system metrics"""
        row = 2
        
        # Time
        self.stdscr.addstr(row, 2, f"Time: {info['time']}", curses.color_pair(2))
        row += 2
        
        # CPU
        cpu_color = 2 if info['cpu'] < 70 else 3 if info['cpu'] < 90 else 4
        self.stdscr.addstr(row, 2, f"CPU:  {info['cpu']:5.1f}%", curses.color_pair(cpu_color))
        self.draw_bar(row, 20, info['cpu'], 100)
        row += 1
        
        # Memory
        mem_color = 2 if info['mem'] < 70 else 3 if info['mem'] < 90 else 4
        self.stdscr.addstr(row, 2, f"MEM:  {info['mem']:5.1f}%", curses.color_pair(mem_color))
        self.draw_bar(row, 20, info['mem'], 100)
        row += 2
        
        # Nomad status
        nomad_color = 2 if info['nomad'] == 'active' else 4
        status_text = "●" if info['nomad'] == 'active' else "○"
        self.stdscr.addstr(row, 2, f"Nomad: {status_text} {info['nomad']}", curses.color_pair(nomad_color))
        
    def draw_bar(self, row, col, value, max_val):
        """Draw a progress bar"""
        bar_width = 30
        filled = int((value / max_val) * bar_width)
        bar = "█" * filled + "░" * (bar_width - filled)
        self.stdscr.addstr(row, col, f"[{bar}]")
        
    def draw_menu(self):
        """Draw navigation menu"""
        row = self.height - 6
        
        self.stdscr.addstr(row, 2, "╔═══ NAVIGATION ═══╗", curses.color_pair(1))
        row += 1
        self.stdscr.addstr(row, 2, "  [N] Nomad UI")
        row += 1
        self.stdscr.addstr(row, 2, "  [L] View Logs")
        row += 1
        self.stdscr.addstr(row, 2, "  [Q] Quit")
        
    def draw_footer(self):
        """Draw footer"""
        footer = "OOPUO v1.0 | Press Q to quit"
        self.stdscr.addstr(self.height - 1, 0, footer.center(self.width), curses.color_pair(1))
        
    def handle_input(self, key):
        """Handle user input"""
        if key == ord('q') or key == ord('Q'):
            return False
        elif key == ord('n') or key == ord('N'):
            self.show_message("Opening Nomad UI... (http://localhost:4646)")
        elif key == ord('l') or key == ord('L'):
            self.show_logs()
        return True
    
    def show_message(self, msg):
        """Show a temporary message"""
        row = self.height // 2
        self.stdscr.addstr(row, 2, " " * (self.width - 4))
        self.stdscr.addstr(row, 2, msg, curses.color_pair(3))
        self.stdscr.refresh()
        time.sleep(2)
    
    def show_logs(self):
        """Show recent logs"""
        curses.endwin()
        subprocess.run("journalctl -u nomad -n 50", shell=True)
        self.stdscr = curses.initscr()
        curses.start_color()
        
    def run(self):
        """Main event loop"""
        running = True
        
        while running:
            self.stdscr.clear()
            
            # Get fresh data
            info = self.get_system_info()
            
            # Draw UI
            self.draw_header()
            self.draw_metrics(info)
            self.draw_menu()
            self.draw_footer()
            
            # Refresh screen
            self.stdscr.refresh()
            
            # Handle input
            key = self.stdscr.getch()
            if key != -1:
                running = self.handle_input(key)

def main(stdscr):
    dashboard = Dashboard(stdscr)
    dashboard.run()

if __name__ == "__main__":
    curses.wrapper(main)
```

### 3.2 Create Nomad Job Definition

**File**: `dashboard/dashboard.nomad`

```hcl
job "oopuo-dashboard" {
  datacenters = ["oopuo-edge"]
  type = "service"

  group "dashboard" {
    count = 1

    network {
      port "http" {
        static = 8080
      }
    }

    task "web" {
      driver = "docker"

      config {
        image = "python:3.11-slim"
        ports = ["http"]
        
        # Mount dashboard code
        volumes = [
          "/opt/oopuo/dashboard:/app"
        ]
        
        command = "python3"
        args = ["-m", "http.server", "8080", "--directory", "/app"]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
```

### 3.3 Deploy to Brain

```bash
# Create directory on Brain
ssh ubuntu@10.0.0.200 "sudo mkdir -p /opt/oopuo/dashboard"

# Copy dashboard files
scp dashboard/main.py ubuntu@10.0.0.200:/tmp/
ssh ubuntu@10.0.0.200 "sudo mv /tmp/main.py /opt/oopuo/dashboard/"

# Deploy via Nomad
scp dashboard/dashboard.nomad ubuntu@10.0.0.200:/tmp/
ssh ubuntu@10.0.0.200 "nomad job run /tmp/dashboard.nomad"
```

---

## PHASE 4: Verification & Testing (30 min)

### 4.1 System Health Checks

```bash
# Check Guard container
pct exec 100 -- systemctl status cloudflared

# Check Brain VM
ssh ubuntu@10.0.0.200 "
    systemctl status nomad
    nomad server members
    nomad node status
"

# Check tunnel
pct exec 100 -- cloudflared tunnel info
```

### 4.2 Access the Dashboard

1. **Via Cloudflare Tunnel**: https://dashboard.yourdomain.com
2. **Direct (from Proxmox host)**: http://10.0.0.200:8080
3. **Nomad UI**: http://10.0.0.200:4646

### 4.3 Test the TUI Dashboard

```bash
ssh ubuntu@10.0.0.200
python3 /opt/oopuo/dashboard/main.py
# Should see the cyberpunk dashboard
# Press 'Q' to quit
```

---

## PHASE 5: Quick Wins (Optional, 30 min)

### 5.1 Add SSH Persistence

Make dashboard start on login:

```bash
ssh ubuntu@10.0.0.200
echo 'python3 /opt/oopuo/dashboard/main.py' >> ~/.bashrc
```

### 5.2 Deploy Sample AI Service

Create a test Ollama deployment:

**File**: `ollama.nomad`

```hcl
job "ollama" {
  datacenters = ["oopuo-edge"]
  type = "service"

  group "ollama" {
    count = 1

    network {
      port "http" {
        static = 11434
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "ollama/ollama:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 2000
        memory = 4096
      }
    }
  }
}
```

Deploy:
```bash
nomad job run ollama.nomad
```

---

## SUCCESS CRITERIA

At the end of today, you should have:

✅ **Infrastructure**:
- Guard LXC (ID 100) running Cloudflare Tunnel
- Brain VM (ID 200) running Nomad + Docker
- Zero open ports on router

✅ **Connectivity**:
- Access dashboard via Cloudflare Tunnel URL
- SSH into Brain VM
- View Nomad UI

✅ **Dashboard**:
- TUI showing real-time CPU/Memory
- Navigation menu working
- Persistent across reconnects

✅ **Foundation**:
- Nomad cluster operational (single node)
- Ready to deploy additional services
- Clean separation of concerns (Guard vs Brain)

---

## TROUBLESHOOTING

### Issue: VM won't start
```bash
qm status 200
tail -f /var/log/pve/tasks/qmstart-200-*.log
```

### Issue: No network in VM
```bash
# Check cloud-init
ssh ubuntu@10.0.0.200
sudo cloud-init status
```

### Issue: Nomad won't start
```bash
ssh ubuntu@10.0.0.200
sudo journalctl -u nomad -f
```

### Issue: Tunnel not connecting
```bash
pct exec 100 -- journalctl -u cloudflared -f
pct exec 100 -- cloudflared tunnel info
```

---

## NEXT STEPS (Post-Deployment)

After you have the prototype running:

1. **Add Consul** for service discovery
2. **Add Vault** for secrets management  
3. **Build the Python Dashboard** with tmux/systemd integration
4. **Add more AI services** (Jupyter, PyTorch, etc.)
5. **Implement the "Time Machine"** (snapshot management)
6. **Multi-node testing** (prepare for federation)

---

## COST & RESOURCE NOTES

**Server Requirements**:
- CPU: 6+ cores (2 for Guard, 4 for Brain)
- RAM: 10GB+ (2GB Guard, 8GB Brain)
- Storage: 50GB+ (8GB Guard, 32GB+ Brain)
- Network: Static IP or Cloudflare Tunnel

**Monthly Costs**:
- Cloudflare Tunnel: Free tier (0-50 users)
- Hardware: Your existing server
- Domain: ~$15/year
- Total: ~$1.25/month

---

## FILES GENERATED BY THIS PLAN

```
oopuo-nomad-prototype/
├── PROJECT_PLAN.md          # This file
├── install.sh               # Main installer
├── setup-tunnel.sh          # Tunnel configurator
└── dashboard/
    ├── main.py              # TUI dashboard
    ├── dashboard.nomad      # Nomad job for web UI
    └── ollama.nomad         # Sample AI service
```

---

## EXECUTION TIMELINE

**Total Time**: 4-6 hours

| Phase | Time | Critical? |
|-------|------|-----------|
| Phase 0: Prerequisites | 15 min | YES |
| Phase 1: Foundation | 45 min | YES |
| Phase 2: Tunnel | 30 min | YES |
| Phase 3: Dashboard | 60 min | YES |
| Phase 4: Testing | 30 min | YES |
| Phase 5: Quick Wins | 30 min | NO |

**Minimum Viable**: Phases 0-4 (2.5 hours)
**Full Prototype**: All phases (4 hours)

---

## CODING AGENT CHECKLIST

Before you start, confirm:

- [ ] You have root SSH access to Proxmox
- [ ] You have a Cloudflare account and tunnel token
- [ ] You understand the Guard/Brain architecture
- [ ] You have 4-6 hours available
- [ ] You have a backup of any existing VMs

Then execute in order:

1. [ ] Create all files from this plan
2. [ ] Run `install.sh` on Proxmox host
3. [ ] Run `setup-tunnel.sh` (or configure manually)
4. [ ] Deploy dashboard to Brain
5. [ ] Verify all services running
6. [ ] Access via tunnel URL
7. [ ] Test dashboard functionality

**When done, report**:
- All URLs (tunnel, nomad, ssh)
- Any errors encountered
- Services status (all should be "active")
- Next recommended steps

---

**Ready to deploy? Start with Phase 0!**

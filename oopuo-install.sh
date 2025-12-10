#!/bin/bash
#
# OOPUO Unified Installer v1.0
# Privacy-First AI Infrastructure Suite
#
# One-command installation for Proxmox servers
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/oopuo-install.sh | bash
#        OR: wget -qO- https://raw.githubusercontent.com/YOUR_REPO/main/oopuo-install.sh | bash
#        OR: ./oopuo-install.sh
#

set -e  # Exit on error

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

VERSION="1.0.0"
GUARD_ID=100
BRAIN_ID=200
REQUIRED_RAM_GB=10
REQUIRED_CORES=6
REQUIRED_STORAGE_GB=50

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║              OOPUO UNIFIED INSTALLER v1.0                        ║
║         Privacy-First AI Infrastructure Suite                    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}═══ $1 ═══${NC}\n"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local value
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " value
        echo "${value:-$default}"
    else
        read -p "$prompt: " value
        echo "$value"
    fi
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# ENVIRONMENT DETECTION & VALIDATION
# ============================================================================

detect_environment() {
    log_step "Detecting Environment"
    
    # Check if running on Proxmox
    if ! check_command pveversion; then
        log_error "This installer must run on a Proxmox VE host"
        log_info "Detected system: $(uname -a)"
        exit 1
    fi
    
    log_success "Proxmox VE detected: $(pveversion | head -1)"
    
    # Get system resources
    TOTAL_CORES=$(nproc)
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    TOTAL_STORAGE_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    log_info "System resources:"
    log_info "  CPU cores: $TOTAL_CORES"
    log_info "  RAM: ${TOTAL_RAM_GB}GB"
    log_info "  Available storage: ${TOTAL_STORAGE_GB}GB"
    
    # Validate resources
    local all_good=true
    
    if [ "$TOTAL_CORES" -lt "$REQUIRED_CORES" ]; then
        log_warning "Recommended $REQUIRED_CORES cores, found $TOTAL_CORES"
        all_good=false
    fi
    
    if [ "$TOTAL_RAM_GB" -lt "$REQUIRED_RAM_GB" ]; then
        log_warning "Recommended ${REQUIRED_RAM_GB}GB RAM, found ${TOTAL_RAM_GB}GB"
        all_good=false
    fi
    
    if [ "$TOTAL_STORAGE_GB" -lt "$REQUIRED_STORAGE_GB" ]; then
        log_warning "Recommended ${REQUIRED_STORAGE_GB}GB storage, found ${TOTAL_STORAGE_GB}GB"
        all_good=false
    fi
    
    if [ "$all_good" = false ]; then
        echo ""
        if ! prompt_yes_no "Resources are below recommended. Continue anyway?"; then
            log_info "Installation cancelled"
            exit 0
        fi
    else
        log_success "All resource requirements met"
    fi
}

detect_network() {
    log_step "Detecting Network Configuration"
    
    # Find default bridge
    if pvesh get /nodes/$(hostname)/network --type bridge 2>/dev/null | grep -q vmbr0; then
        DEFAULT_BRIDGE="vmbr0"
    else
        DEFAULT_BRIDGE=$(pvesh get /nodes/$(hostname)/network --type bridge 2>/dev/null | grep -o 'vmbr[0-9]*' | head -1)
    fi
    
    # Find default storage
    DEFAULT_STORAGE=$(pvesm status | awk 'NR>1 && $2=="active" {print $1; exit}')
    
    # Detect network range
    DEFAULT_GATEWAY=$(ip route | awk '/default/ {print $3}')
    NETWORK_PREFIX=$(echo $DEFAULT_GATEWAY | cut -d'.' -f1-3)
    
    log_info "Network configuration detected:"
    log_info "  Bridge: $DEFAULT_BRIDGE"
    log_info "  Storage: $DEFAULT_STORAGE"
    log_info "  Gateway: $DEFAULT_GATEWAY"
    log_info "  Network: ${NETWORK_PREFIX}.0/24"
}

check_existing_vms() {
    log_step "Checking for Conflicts"
    
    local conflicts=false
    
    if pct status $GUARD_ID &>/dev/null; then
        log_warning "Container ID $GUARD_ID already exists"
        conflicts=true
    fi
    
    if qm status $BRAIN_ID &>/dev/null; then
        log_warning "VM ID $BRAIN_ID already exists"
        conflicts=true
    fi
    
    if [ "$conflicts" = true ]; then
        echo ""
        if prompt_yes_no "Destroy existing containers/VMs with these IDs?"; then
            log_info "Cleaning up existing resources..."
            pct stop $GUARD_ID 2>/dev/null || true
            pct destroy $GUARD_ID 2>/dev/null || true
            qm stop $BRAIN_ID 2>/dev/null || true
            qm destroy $BRAIN_ID 2>/dev/null || true
            log_success "Cleanup complete"
        else
            log_error "Cannot proceed with existing IDs. Please remove them manually or choose different IDs."
            exit 1
        fi
    else
        log_success "No conflicts detected"
    fi
}

# ============================================================================
# CONFIGURATION GATHERING
# ============================================================================

gather_configuration() {
    log_step "Configuration"
    
    echo "Let's configure your OOPUO installation."
    echo ""
    
    # Network configuration
    BRIDGE=$(prompt_input "Network bridge" "$DEFAULT_BRIDGE")
    STORAGE=$(prompt_input "Storage pool" "$DEFAULT_STORAGE")
    GATEWAY=$(prompt_input "Gateway IP" "$DEFAULT_GATEWAY")
    
    # Suggest IPs based on network
    SUGGESTED_GUARD_IP="${NETWORK_PREFIX}.100"
    SUGGESTED_BRAIN_IP="${NETWORK_PREFIX}.200"
    
    GUARD_IP=$(prompt_input "Guard container IP" "$SUGGESTED_GUARD_IP")
    BRAIN_IP=$(prompt_input "Brain VM IP" "$SUGGESTED_BRAIN_IP")
    
    # Add subnet mask
    GUARD_IP_CIDR="${GUARD_IP}/24"
    BRAIN_IP_CIDR="${BRAIN_IP}/24"
    
    echo ""
    log_info "Configuration summary:"
    log_info "  Guard (LXC $GUARD_ID): $GUARD_IP"
    log_info "  Brain (VM $BRAIN_ID): $BRAIN_IP"
    log_info "  Bridge: $BRIDGE"
    log_info "  Storage: $STORAGE"
    log_info "  Gateway: $GATEWAY"
    echo ""
    
    if ! prompt_yes_no "Proceed with this configuration?"; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

install_guard() {
    log_step "Installing Guard Container (Network Gateway)"
    
    # Download template if needed
    local template="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    local template_path="/var/lib/vz/template/cache/$template"
    
    if [ ! -f "$template_path" ]; then
        log_info "Downloading Ubuntu 24.04 template..."
        pveam update
        pveam download local $template
        log_success "Template downloaded"
    else
        log_info "Template already exists, skipping download"
    fi
    
    # Create container
    log_info "Creating Guard container..."
    pct create $GUARD_ID \
        local:vztmpl/$template \
        --hostname guard \
        --cores 2 \
        --memory 2048 \
        --swap 512 \
        --net0 name=eth0,bridge=$BRIDGE,ip=$GUARD_IP_CIDR,gw=$GATEWAY \
        --storage $STORAGE \
        --rootfs $STORAGE:8 \
        --unprivileged 1 \
        --features nesting=1 \
        --onboot 1 \
        --password="oopuo2024"
    
    log_success "Guard container created"
    
    # Start container
    log_info "Starting Guard container..."
    pct start $GUARD_ID
    sleep 5
    
    # Wait for container to be ready
    log_info "Waiting for container to initialize..."
    for i in {1..30}; do
        if pct exec $GUARD_ID -- test -d /root 2>/dev/null; then
            break
        fi
        sleep 2
    done
    
    # Install packages
    log_info "Installing Guard services..."
    pct exec $GUARD_ID -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq curl gnupg lsb-release ca-certificates >/dev/null 2>&1
        
        # Install Cloudflare Tunnel
        curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-archive-keyring.gpg >/dev/null
        echo \"deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared \$(lsb_release -cs) main\" | tee /etc/apt/sources.list.d/cloudflared.list
        apt-get update -qq
        apt-get install -y -qq cloudflared >/dev/null 2>&1
    "
    
    log_success "Guard installation complete"
}

install_brain() {
    log_step "Installing Brain VM (Compute Node)"
    
    # Download cloud image if needed
    local cloud_image="/var/lib/vz/template/iso/ubuntu-24.04-server-cloudimg-amd64.img"
    
    if [ ! -f "$cloud_image" ]; then
        log_info "Downloading Ubuntu 24.04 cloud image..."
        wget -q --show-progress -O "$cloud_image" \
            https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
        log_success "Cloud image downloaded"
    else
        log_info "Cloud image already exists, skipping download"
    fi
    
    # Create VM
    log_info "Creating Brain VM..."
    qm create $BRAIN_ID \
        --name brain \
        --cores 4 \
        --memory 8192 \
        --net0 virtio,bridge=$BRIDGE \
        --scsihw virtio-scsi-pci
    
    # Import and attach disk
    log_info "Importing disk..."
    qm importdisk $BRAIN_ID "$cloud_image" $STORAGE >/dev/null 2>&1
    
    qm set $BRAIN_ID \
        --scsi0 ${STORAGE}:vm-${BRAIN_ID}-disk-0 \
        --boot order=scsi0 \
        --serial0 socket \
        --vga serial0
    
    # Add cloud-init
    qm set $BRAIN_ID --ide2 ${STORAGE}:cloudinit
    
    # Configure cloud-init
    qm set $BRAIN_ID \
        --ciuser ubuntu \
        --cipassword oopuo2024 \
        --ipconfig0 ip=$BRAIN_IP_CIDR,gw=$GATEWAY \
        --nameserver 8.8.8.8 \
        --onboot 1
    
    log_success "Brain VM created"
    
    # Start VM
    log_info "Starting Brain VM (this may take 30-60 seconds)..."
    qm start $BRAIN_ID
    
    # Wait for SSH
    log_info "Waiting for VM to boot and SSH to become available..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if sshpass -p "oopuo2024" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
           ubuntu@$BRAIN_IP "echo ready" &>/dev/null; then
            log_success "Brain VM is ready"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "VM failed to become ready. Check VM console: qm terminal $BRAIN_ID"
        exit 1
    fi
    
    # Install packages
    log_info "Installing Nomad and Docker..."
    sshpass -p "oopuo2024" ssh -o StrictHostKeyChecking=no ubuntu@$BRAIN_IP "
        # Install Nomad
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nomad
        
        # Install Docker
        curl -fsSL https://get.docker.com | sudo bash >/dev/null 2>&1
        sudo usermod -aG docker ubuntu
        
        # Configure Nomad
        sudo mkdir -p /etc/nomad.d
        sudo tee /etc/nomad.d/nomad.hcl >/dev/null <<'EOF'
datacenter = \"oopuo-edge\"
data_dir = \"/opt/nomad/data\"

server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
}

plugin \"docker\" {
  config {
    allow_privileged = true
  }
}
EOF
        
        # Start Nomad
        sudo systemctl enable nomad >/dev/null 2>&1
        sudo systemctl start nomad
    "
    
    log_success "Brain installation complete"
}

install_dashboard() {
    log_step "Installing OOPUO Dashboard"
    
    # Create dashboard directory and files
    sshpass -p "oopuo2024" ssh -o StrictHostKeyChecking=no ubuntu@$BRAIN_IP "
        sudo mkdir -p /opt/oopuo/dashboard
        
        # Create main.py dashboard
        sudo tee /opt/oopuo/dashboard/main.py >/dev/null <<'DASHBOARD_EOF'
#!/usr/bin/env python3
import curses
import subprocess
import time
from datetime import datetime

class Dashboard:
    def __init__(self, stdscr):
        self.stdscr = stdscr
        curses.curs_set(0)
        stdscr.nodelay(1)
        stdscr.timeout(1000)
        curses.start_color()
        curses.init_pair(1, curses.COLOR_CYAN, curses.COLOR_BLACK)
        curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)
        
    def get_metrics(self):
        try:
            cpu = subprocess.check_output(\"top -bn1 | grep 'Cpu(s)' | awk '{print \\$2}' | cut -d'%' -f1\", shell=True).decode().strip()
            mem = subprocess.check_output(\"free | grep Mem | awk '{printf \\\"%.1f\\\", \\$3/\\$2 * 100}'\", shell=True).decode().strip()
            nomad = subprocess.check_output(\"systemctl is-active nomad 2>/dev/null || echo inactive\", shell=True).decode().strip()
            return {'cpu': float(cpu or 0), 'mem': float(mem or 0), 'nomad': nomad, 'time': datetime.now().strftime(\"%H:%M:%S\")}
        except:
            return {'cpu': 0, 'mem': 0, 'nomad': 'error', 'time': datetime.now().strftime(\"%H:%M:%S\")}
    
    def run(self):
        while True:
            try:
                self.stdscr.clear()
                info = self.get_metrics()
                self.stdscr.addstr(0, 2, \"═══ OOPUO DASHBOARD ═══\", curses.color_pair(1) | curses.A_BOLD)
                self.stdscr.addstr(2, 2, f\"Time: {info['time']}\")
                self.stdscr.addstr(3, 2, f\"CPU:  {info['cpu']:.1f}%\", curses.color_pair(2))
                self.stdscr.addstr(4, 2, f\"MEM:  {info['mem']:.1f}%\", curses.color_pair(2))
                self.stdscr.addstr(5, 2, f\"Nomad: {info['nomad']}\", curses.color_pair(2 if info['nomad']=='active' else 1))
                self.stdscr.addstr(7, 2, \"Press 'q' to quit\")
                self.stdscr.refresh()
                if self.stdscr.getch() == ord('q'):
                    break
            except KeyboardInterrupt:
                break

if __name__ == '__main__':
    curses.wrapper(lambda s: Dashboard(s).run())
DASHBOARD_EOF
        
        sudo chmod +x /opt/oopuo/dashboard/main.py
    "
    
    log_success "Dashboard installed at /opt/oopuo/dashboard/main.py"
}

# ============================================================================
# POST-INSTALLATION
# ============================================================================

print_success_message() {
    clear
    echo -e "${GREEN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║              ✓ INSTALLATION COMPLETE!                            ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo ""
    log_success "OOPUO infrastructure is ready!"
    echo ""
    
    echo -e "${CYAN}Access Points:${NC}"
    echo "  Guard container:  pct enter $GUARD_ID"
    echo "  Brain VM (SSH):   ssh ubuntu@$BRAIN_IP"
    echo "  Brain VM (console): qm terminal $BRAIN_ID"
    echo "  Nomad UI:         http://$BRAIN_IP:4646"
    echo ""
    
    echo -e "${CYAN}Default Credentials:${NC}"
    echo "  Brain VM: ubuntu / oopuo2024"
    echo "  Guard:    root / oopuo2024"
    echo ""
    
    echo -e "${CYAN}Try the Dashboard:${NC}"
    echo "  ssh ubuntu@$BRAIN_IP"
    echo "  python3 /opt/oopuo/dashboard/main.py"
    echo ""
    
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Configure Cloudflare Tunnel (see documentation)"
    echo "  2. Deploy your first AI service"
    echo "  3. Change default passwords!"
    echo ""
    
    echo -e "${YELLOW}Documentation:${NC}"
    echo "  GitHub: https://github.com/clubeedg-ship-it/oopuo-nomad-prototype"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header
    
    log_info "Starting OOPUO installation..."
    log_info "Version: $VERSION"
    echo ""
    
    # Pre-flight checks
    detect_environment
    detect_network
    check_existing_vms
    gather_configuration
    
    # Installation
    install_guard
    install_brain  
    install_dashboard
    
    # Success
    print_success_message
}

# Run main function
main

exit 0

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
    ssh -o StrictHostKeyChecking=no ubuntu@$BRAIN_IP_ADDR "
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nomad
    "
    
    # Install Docker
    echo "  Installing Docker..."
    ssh -o StrictHostKeyChecking=no ubuntu@$BRAIN_IP_ADDR "
        curl -fsSL https://get.docker.com | sudo bash
        sudo usermod -aG docker ubuntu
    "
    
    # Create Nomad config
    echo "  Configuring Nomad..."
    ssh -o StrictHostKeyChecking=no ubuntu@$BRAIN_IP_ADDR "sudo mkdir -p /etc/nomad.d"
    
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
    
    scp -o StrictHostKeyChecking=no /tmp/nomad.hcl ubuntu@$BRAIN_IP_ADDR:/tmp/
    ssh -o StrictHostKeyChecking=no ubuntu@$BRAIN_IP_ADDR "sudo mv /tmp/nomad.hcl /etc/nomad.d/nomad.hcl"
    
    # Start Nomad
    ssh -o StrictHostKeyChecking=no ubuntu@$BRAIN_IP_ADDR "
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
    echo "  1. Run ./setup-tunnel.sh to configure Cloudflare Tunnel"
    echo "  2. Deploy OOPUO Dashboard via Nomad"
    echo "  3. Access via tunnel URL"
}

main

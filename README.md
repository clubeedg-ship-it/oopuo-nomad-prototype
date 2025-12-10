# OOPUO-Nomad Prototype

**Privacy-First AI Infrastructure Suite for Proxmox**

## Quick Install (Recommended) 🚀

```bash
wget https://raw.githubusercontent.com/clubeedg-ship-it/oopuo-nomad-prototype/main/oopuo-install.sh
chmod +x oopuo-install.sh
./oopuo-install.sh
```

**That's it!** The installer will:
- ✓ Detect your environment automatically
- ✓ Ask smart questions (3-5 prompts)
- ✓ Install Guard container + Brain VM
- ✓ Configure Nomad + Docker
- ✓ Set up dashboard

**Time**: 15-30 minutes

---

## What You Get

### Architecture

```
┌─────────────────────────────────┐
│     CLOUDFLARE TUNNEL          │
│     (Zero-Trust Gateway)        │
└────────────┬────────────────────┘
             │
┌────────────▼────────────────────┐
│  THE GUARD (LXC 100)           │
│  • Cloudflare Tunnel Client     │
│  • Network Gateway              │
│  • No ports exposed             │
└────────────┬────────────────────┘
             │
┌────────────▼────────────────────┐
│  THE BRAIN (VM 200)            │
│  • Nomad (Orchestration)        │
│  • Docker (Containers)          │
│  • AI Workloads                 │
│  • OOPUO Dashboard              │
└─────────────────────────────────┘
```

### Key Features

- **Zero Open Ports**: All ingress via Cloudflare Tunnel
- **Production-Grade**: HashiCorp Nomad orchestration
- **AI-Ready**: GPU passthrough support
- **Privacy-First**: All data stays on your hardware
- **One-Command Install**: Automated deployment

---

## Requirements

- **Hardware**: 6+ CPU cores, 10GB+ RAM, 50GB+ storage
- **Software**: Proxmox VE 7.x or 8.x
- **Network**: Internet access
- **Account**: Cloudflare (free tier works)

---

## Manual Installation

Prefer step-by-step control? See [docs/QUICKSTART.md](docs/QUICKSTART.md)

Or use the manual scripts:
```bash
cd manual
./install.sh
./setup-tunnel.sh
```

---

## Documentation

- [Installation Comparison](docs/INSTALLER_COMPARISON.md) - Why one installer vs multiple files
- [Complete Guide](docs/PROJECT_PLAN.md) - Comprehensive technical documentation
- [Quick Reference](docs/QUICKSTART.md) - Manual installation steps
- [Dashboard](dashboard/) - TUI and Nomad job definitions

---

## The Vision

This prototype is **Phase 1** of a privacy-preserving AI marketplace:

**Phase 1 (Now)**: Single-node infrastructure management  
**Phase 2**: Add Consul/Vault for privacy primitives  
**Phase 3**: Multi-node federation  
**Phase 4**: Decentralized AI agent marketplace  

**Inspiration**: Charles Hoskinson's [Midnight](https://midnight.network/) blockchain concept of "rational privacy"

### The Problem
Using AI today means surrendering private data (medical records, location, finances) to centralized entities like Google/Amazon - enabling surveillance capitalism and financial front-running.

### The Solution
A marketplace where:
- Users keep data on their devices (iPhone/Mac)
- "Private agents" understand user context locally
- "Public agents" (on OOPUO servers) execute tasks
- Agents receive constraints, never raw data or identity
- Computing distributes across the network

**Think**: AI VPN that separates expertise from personal information

---

## Usage

After installation:

```bash
# Access Guard container
pct enter 100

# SSH to Brain VM
ssh ubuntu@YOUR_BRAIN_IP
# Password: oopuo2024

# Try the dashboard
python3 /opt/oopuo/dashboard/main.py

# Access Nomad UI
http://YOUR_BRAIN_IP:4646

# Deploy AI service
nomad job run /opt/oopuo/dashboard/ollama.nomad
```

---

## Comparison to Alternatives

| Solution | Focus | Complexity | Privacy | GPU Support |
|----------|-------|------------|---------|-------------|
| **OOPUO** | AI Workstations | Medium | ★★★★★ | ★★★★★ |
| Balena | IoT/Edge | Low | ★★★☆☆ | ★☆☆☆☆ |
| Red Hat | Enterprise IT | High | ★★★☆☆ | ★★★☆☆ |
| Kubernetes | General Cloud | High | ★★☆☆☆ | ★★★★☆ |

---

## Troubleshooting

```bash
# Check status
pct status 100    # Guard
qm status 200     # Brain

# View logs
pct exec 100 -- journalctl -u cloudflared -f
ssh ubuntu@BRAIN_IP "journalctl -u nomad -f"

# Restart services
pct exec 100 -- systemctl restart cloudflared
ssh ubuntu@BRAIN_IP "sudo systemctl restart nomad"
```

For detailed troubleshooting, see [docs/QUICKSTART.md](docs/QUICKSTART.md#troubleshooting)

---

## Contributing

This is a prototype. Contributions welcome once foundation stabilizes (Q1 2026).

For now:
- ⭐ Star the repo to stay updated
- 🐛 Report issues
- 💡 Suggest features via Issues

---

## License

MIT License - See [LICENSE](LICENSE) for details

---

## Acknowledgments

- [HashiCorp](https://www.hashicorp.com/) (Nomad, Consul, Vault)
- [Cloudflare](https://www.cloudflare.com/) (Zero Trust networking)
- [Proxmox](https://www.proxmox.com/) (Virtualization)
- [Charles Hoskinson](https://iohk.io/) (Privacy architecture inspiration)

---

**Built for a future where AI serves humans, not surveillance capitalism.** 🔒🤖

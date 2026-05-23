# scan-ir-domains

**Automated Iranian domain accessibility checker** — identifies which .ir domains are accessible from outside Iran using Certificate Transparency logs. Runs on any VPS outside of Iran with daily automated scans.

![Status](https://img.shields.io/badge/status-production--ready-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Python](https://img.shields.io/badge/python-3.8+-blue)

---

## 🎯 What It Does

- **Enumerates** Iranian domains from Certificate Transparency logs (no limit)
- **Tests** each domain for DNS resolution, HTTP connectivity, TLS validity
- **Identifies** censorship type: DNS-blocked, TLS-intercepted, or accessible
- **Saves** results every 10 domains (prevents data loss)
- **Analyzes** results with filtering, exporting, and comparison tools
- **Automates** daily scans via systemd timer on your VPS

---

## ⚡ Quick Start (One Command)

On a fresh Hetzner VPS (Ubuntu/Debian), run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/scan-ir-domains/main/install.sh)
```

**That's it!** The timer runs daily at 02:00 UTC starting tomorrow.

---

## 📋 What Gets Installed

The one-command setup:
- ✅ Python 3.8+ with virtual environment
- ✅ All dependencies (aiohttp, aiofiles, certifi, etc.)
- ✅ Systemd service + daily timer
- ✅ Firewall configuration (UFW)
- ✅ Helper analysis scripts
- ✅ Monitoring and logging

**Total time: ~3 minutes**

---

## 💰 Cost

| VPS Type | Price | Domains/Day | Best For |
|----------|-------|-------------|----------|
| CX11 | €2.49/mo | 500-1K | Testing |
| **CX21** | **€4.90/mo** | **2K-3K** | **Production** ⭐ |
| CX31 | €7.98/mo | 5K-8K | High volume |

**Recommended:** Start with CX21 (€4.90/month)

---

## 📖 Documentation

| File | Purpose |
|------|---------|
| `README.md` (this file) | Quick overview |
| `install.sh` | Automatic setup script |
| `HETZNER_QUICKREF.md` | 5-minute setup guide |
| `HETZNER_DEPLOYMENT.md` | Step-by-step instructions |
| `HETZNER_OPTIMIZATION.md` | VPS sizing & tuning |
| `USAGE_GUIDE.md` | Complete feature reference |
| `INDEX.md` | File navigation guide |

---

## 🚀 Three Ways to Install

### Method 1: One Command (Fastest) ⭐
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/scan-ir-domains/main/install.sh)
```

### Method 2: Step-by-Step (Safest)
See `HETZNER_DEPLOYMENT.md` for detailed instructions.

### Method 3: Manual (Most Control)
See `HETZNER_QUICKREF.md` for individual commands.

---

## 📊 Expected Results

After one week (CX21 VPS):
```
Total domains checked:     19,600 (2,800/day × 7 days)
Accessible:                ~8,500 (43%)
DNS-blocked:               ~6,100 (31%)
Censorship-intercepted:    ~5,000 (26%)

Storage used:              ~10.5 MB
Monthly cost:              €4.90 (VPS only)
Cost per million domains:  €0.49
```

---

## 🔍 What's Inside

### Core Scripts
- **`iran_domain_checker.py`** — Main scanner (500 lines)
  - Streams CT logs continuously
  - 50 parallel workers (configurable)
  - Saves results every 10 domains
  - Tests DNS, HTTP/HTTPS, TLS validity

- **`analyze_results.py`** — Results analyzer (400 lines)
  - Filter by accessibility
  - Export to CSV/JSON
  - Compare scans over time
  - Find specific domains

### Setup & Automation
- **`install.sh`** — One-command automatic setup
- **`deploy_hetzner.sh`** — Manual deployment script
- **Systemd files** — Service and timer configuration

### Documentation
- **8 comprehensive guides** covering all aspects
- **40+ examples** for all use cases
- **VPS sizing recommendations**
- **Performance tuning guide**

---

## 🎯 Basic Commands

Once installed on your VPS:

```bash
# Check timer status
sudo systemctl list-timers domain-checker.timer

# View latest logs
sudo journalctl -u domain-checker.service -f

# Run a manual scan
cd /home/domainchecker/checker
source venv/bin/activate
python3 iran_domain_checker.py --domains "test.ir,example.ir"

# Analyze results
python3 analyze_results.py results/scan_*.jsonl --format summary

# Download to local machine
scp -r root@YOUR_SERVER_IP:/home/domainchecker/checker/results/ ./backups/

# Check status
./status.sh
```

---

## 📈 Performance by VPS Type

| VPS | vCPU | RAM | Config | Speed | Time |
|-----|------|-----|--------|-------|------|
| CX11 | 1 | 1GB | `--workers 10 --timeout 15` | 500-1K/day | 30-60 min |
| **CX21** | **2** | **4GB** | **`--workers 50 --timeout 10`** | **2K-3K/day** | **5-15 min** |
| CX31 | 2 | 8GB | `--workers 100 --timeout 5` | 5K-8K/day | 2-5 min |

---

## 🔐 Security Features

- ✅ Runs as non-root user (domainchecker)
- ✅ Firewall configured (UFW)
- ✅ SSH key authentication only
- ✅ Logs all activity (journalctl)
- ✅ Rate-limited API queries
- ✅ SSL verification disabled (intentional) to detect MITM proxies

---

## 📊 Understanding Results

Each domain gets tested and returns:

```json
{
  "domain": "example.ir",
  "timestamp": "2026-05-23T14:30:45.123456",
  "accessible": true,
  "dns_resolves": true,
  "http_status": 200,
  "tls_valid": true,
  "ip": "185.12.34.56",
  "checked_from": "external"
}
```

**Interpretation:**
- **DNS-blocked** (dns_resolves=false): Use DoH/DoT
- **TLS-intercepted** (dns_resolves=true, accessible=false): Use REALITY/ShadowTLS
- **Fully accessible** (accessible=true): No bypass needed

---

## 🆘 Troubleshooting

### Timer not running?
```bash
sudo systemctl status domain-checker.timer
sudo journalctl -u domain-checker.service -n 20
```

### Out of memory?
Edit `/etc/systemd/system/domain-checker.service` and change:
```
--workers 20 --timeout 15
```

### Disk full?
```bash
cd /home/domainchecker/checker/results
tar -czf old_scans.tar.gz scan_*.jsonl
rm scan_*.jsonl
```

---

## 📝 Configuration

Edit `/etc/systemd/system/domain-checker.service` to customize:

```bash
# Change scan time (default: 02:00 UTC)
sudo nano /etc/systemd/system/domain-checker.timer
# Edit: OnCalendar=*-*-* 14:00:00

# Change workers/timeout
sudo nano /etc/systemd/system/domain-checker.service
# Edit: --workers 50 --timeout 10

# Reload
sudo systemctl daemon-reload
sudo systemctl restart domain-checker.timer
```

---

## 📊 Monitoring Results

### Download results locally
```bash
# Daily
scp -r root@YOUR_SERVER_IP:/home/domainchecker/checker/results/ ./backups/$(date +%Y%m%d)/

# Or as cron job
0 3 * * * scp -r root@YOUR_SERVER_IP:/home/domainchecker/checker/results/ ~/backups/$(date +\%Y\%m\%d)
```

### Compare scans
```bash
python3 analyze_results.py day2.jsonl --compare day1.jsonl
```

### Export to CSV
```bash
python3 analyze_results.py results/scan_*.jsonl --format csv --output results.csv
```

---

## 🚀 Upgrading VPS

If you run out of resources:

1. Hetzner Cloud Console → Server
2. **Resize** → Choose new type (e.g., CX21 → CX31)
3. Select **upgrade** (no downtime)
4. Update workers in service file:
   ```bash
   sudo nano /etc/systemd/system/domain-checker.service
   # Change: --workers 50 --timeout 10 → --workers 100 --timeout 5
   sudo systemctl daemon-reload
   ```

---

## 📄 License

MIT — Use freely, no restrictions.

---

## 🎓 DPI Bypass Context

This tool identifies which censorship technique is needed:

| Result | Block Type | Bypass Method |
|--------|-----------|---------------|
| DNS ✗ | DNS-level | DoH, DoT |
| DNS ✓, TLS ✗ | TLS intercept | REALITY, ShadowTLS, Cloak |
| All ✓ | No block | Direct access |

See [DPI Bypass Landscape](DPI_BYPASS_LANDSCAPE.md) for detailed technique comparison.

---

## 🔗 Related Projects

- [zapret](https://github.com/bol-van/zapret) — Packet-level desync
- [Xray-core](https://github.com/XTLS/Xray-core) — REALITY proxy
- [Hysteria](https://github.com/apernet/hysteria) — QUIC-based tunnel
- [Geneva](https://github.com/Kkevsterrr/geneva) — DPI evasion research

---

## 📞 Support

- **Hetzner Issues**: https://docs.hetzner.cloud
- **Python Issues**: https://docs.python.org/3/
- **Systemd Issues**: `man systemctl`

---

## 🎯 Quick Checklist

- [ ] Create Hetzner VPS (CX21, €4.90/mo)
- [ ] Run one-line install command
- [ ] Check timer: `systemctl list-timers`
- [ ] Wait for 02:00 UTC (or edit timer)
- [ ] Check results: `ls -lh /home/domainchecker/checker/results/`
- [ ] Download: `scp -r ...`

---

**That's it! Automated Iranian domain scanning on your VPS.** 🚀

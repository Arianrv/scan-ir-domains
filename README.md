# scan-ir-domains

Automated Iranian domain accessibility checker. Identifies which .ir domains are accessible from outside Iran using Certificate Transparency logs. Deploy to any Linux VPS in one command.

![Status](https://img.shields.io/badge/status-production--ready-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Python](https://img.shields.io/badge/python-3.8+-blue)

---

## ⚡ Quick Start

On any Linux VPS (Ubuntu/Debian), run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/scan-ir-domains/main/install.sh)
```

That's it! Daily automated scans starting tomorrow at 02:00 UTC.

---

## 🎯 What It Does

- **Enumerates** Iranian domains from Certificate Transparency logs
- **Tests** each domain (DNS resolution, HTTP status, TLS validity)
- **Identifies** censorship type (DNS-blocked, TLS-intercepted, accessible)
- **Saves** results every 10 domains (prevents data loss)
- **Analyzes** with filtering, exporting, comparing tools
- **Automates** daily scans via systemd timer

---

## 📊 Expected Results

Scanning ~2800 unique .ir domains per day:
```
Accessible:                43%
DNS-blocked:              31%
Censorship-intercepted:   26%
```

Results stored as JSONL (one per domain) - easy to parse and analyze.

---

## 📦 What Gets Installed

The one-command installer:
- ✅ Python 3.8+ with venv
- ✅ All dependencies (aiohttp, aiofiles, certifi)
- ✅ Systemd service + daily timer
- ✅ Firewall configuration
- ✅ Analysis scripts
- ✅ Logging and monitoring

**Time:** ~3 minutes

---

## 📖 Documentation

| File | Purpose |
|------|---------|
| `README.md` | This file |
| `install.sh` | Automatic installer |
| `QUICKSTART.md` | Local testing guide |
| `USAGE_GUIDE.md` | Complete reference |
| `INDEX.md` | File navigation |

---

## 🔍 Understanding Results

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

**Result types:**
- **DNS-blocked** (dns_resolves=false): Use DoH or DoT
- **TLS-intercepted** (dns_resolves=true, accessible=false): Use REALITY or ShadowTLS
- **Fully accessible** (accessible=true): No bypass needed

---

## 🎯 Basic Commands

```bash
# Check timer status
sudo systemctl list-timers domain-checker.timer

# View logs
sudo journalctl -u domain-checker.service -f

# Run manual scan
cd /home/domainchecker/checker
source venv/bin/activate
python3 iran_domain_checker.py --domains "test.ir,example.ir"

# Analyze results
python3 analyze_results.py results/scan_*.jsonl --format summary

# Download to local machine
scp -r root@YOUR_SERVER_IP:/home/domainchecker/checker/results/ ./backups/
```

---

## 🔧 Customization

Edit `/etc/systemd/system/domain-checker.service`:

```bash
# Change scan time (default: 02:00 UTC)
sudo nano /etc/systemd/system/domain-checker.timer
# Edit: OnCalendar=*-*-* 02:00:00

# Change workers/timeout (performance tuning)
sudo nano /etc/systemd/system/domain-checker.service
# Edit: --workers 50 --timeout 10

# Reload
sudo systemctl daemon-reload
sudo systemctl restart domain-checker.timer
```

Options:
- **Conservative**: `--workers 20 --timeout 15` (slower, safer)
- **Balanced** (default): `--workers 50 --timeout 10`
- **Aggressive**: `--workers 100 --timeout 5` (faster, more load)

---

## 📊 Performance Tuning

Adjust based on VPS specs:

| VPS Spec | Workers | Timeout | Domains/Day | Time |
|----------|---------|---------|-------------|------|
| 1 vCPU, 1GB RAM | 10 | 15s | 500-1K | 30-60m |
| 2 vCPU, 4GB RAM | 50 | 10s | 2K-3K | 5-15m |
| 4 vCPU, 8GB RAM | 100 | 5s | 5K-8K | 2-5m |

---

## 🚨 Troubleshooting

### Timer not running
```bash
sudo systemctl status domain-checker.timer
sudo journalctl -u domain-checker.service -n 20
```

### Out of memory
Edit service file and set: `--workers 20 --timeout 15`

### Disk full
```bash
cd /home/domainchecker/checker/results
tar -czf old_scans.tar.gz scan_*.jsonl
rm scan_*.jsonl
```

### Manual test
```bash
cd /home/domainchecker/checker
source venv/bin/activate
python3 iran_domain_checker.py --domains "test.ir" --timeout 5
```

---

## 📄 License

MIT - Use freely

---

## 🔗 Related

- [DPI Bypass Landscape](https://github.com/bol-van/zapret) - Censorship evasion techniques
- [Xray-core](https://github.com/XTLS/Xray-core) - REALITY proxy
- [Hysteria](https://github.com/apernet/hysteria) - QUIC tunnel

---

**Deploy to any Linux VPS with one command!**

# Scan-ir-domains

Automated Iranian domain accessibility checker. Identifies which `.ir` domains are accessible from outside Iran using Certificate Transparency logs. Deploy to any Ubuntu/Debian VPS in one command.

![Status](https://img.shields.io/badge/status-production--ready-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Python](https://img.shields.io/badge/python-3.8+-blue)

---

## ⚡ Quick Start

On any Ubuntu/Debian VPS, run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Arianrv/scan-ir-domains/main/install.sh)
```

The installer creates a dedicated user by default, installs Python dependencies, verifies required project files, creates systemd units, and optionally runs the first scan immediately.

---

## 🎯 What It Does

- **Enumerates** Iranian domains from Certificate Transparency logs
- **Tests** each domain with DNS resolution, HTTP status, and TLS validity checks
- **Identifies** accessibility signals such as DNS failure, HTTP response availability, and TLS validity
- **Saves** results every 10 domains by default to reduce data loss risk
- **Analyzes** with filtering, exporting, and summary tooling
- **Automates** daily scans via a systemd timer

---

## 📊 Expected Results

Result counts depend heavily on the VPS network, location, resolver behavior, timeout, and current CT-log availability.

Results are stored as JSONL, one record per domain.

---

## 📦 What Gets Installed

The one-command installer:

- ✅ Python 3.8+ with virtual environment
- ✅ Dependencies: `aiohttp`, `aiofiles`, `certifi`, `requests`
- ✅ Project files verified after clone
- ✅ Systemd service + daily timer
- ✅ Optional first scan
- ✅ Firewall configuration through UFW when available
- ✅ Analysis script and status helper

**Typical install time:** ~3 minutes, depending on VPS package mirrors and network speed.

---

## 📖 Documentation

| File | Purpose |
|------|---------|
| `README.md` | This file |
| `install.sh` | Automatic installer |
| `uninstall.sh` | Safe uninstaller |
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

**Result fields:**

- `dns_resolves=false`: DNS did not resolve from the VPS environment
- `http_status=2xx/3xx`: HTTP/HTTPS request returned a successful or redirect response
- `tls_valid=true`: TLS handshake completed with a valid certificate
- `accessible=true`: DNS resolved and either HTTP returned 2xx/3xx or TLS was valid

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

If you installed with a custom user, replace `/home/domainchecker/checker` with that user's checker directory, for example `/home/irdomains/checker`.

---

## 🔧 Customization

Edit `/etc/systemd/system/domain-checker.service`:

```bash
# Change scan time
sudo nano /etc/systemd/system/domain-checker.timer
# Edit: OnCalendar=*-*-* 02:00:00

# Change workers/timeout
sudo nano /etc/systemd/system/domain-checker.service
# Edit: --workers 50 --timeout 10

# Reload
sudo systemctl daemon-reload
sudo systemctl restart domain-checker.timer
```

Options:

- **Conservative:** `--workers 20 --timeout 15` — slower, safer
- **Balanced:** `--workers 50 --timeout 10` — default
- **Aggressive:** `--workers 100 --timeout 5` — faster, more load

---

## 📊 Performance Tuning

Adjust based on VPS specs:

| VPS Spec | Workers | Timeout | Notes |
|----------|---------|---------|-------|
| 1 vCPU, 1GB RAM | 10-20 | 15s | Safer on small machines |
| 2 vCPU, 4GB RAM | 50 | 10s | Balanced default |
| 4 vCPU, 8GB RAM | 100 | 5s | Higher load, faster checks |

---

## 🚨 Troubleshooting

### Required file missing after install

The installer now verifies required files after cloning. If this fails, the install stops instead of creating a broken systemd service.

```bash
ls -la /home/domainchecker/checker
```

### Timer not running

```bash
sudo systemctl status domain-checker.timer
sudo journalctl -u domain-checker.service -n 20
```

### Out of memory

Edit service file and set lower concurrency:

```bash
--workers 20 --timeout 15
```

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

## 🧹 Uninstall

Automatic safe uninstall:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Arianrv/scan-ir-domains/main/uninstall.sh)
```

The uninstaller stops and removes the systemd units. It asks before deleting the checker directory, results, logs, or Linux user.

Manual uninstall:

```bash
sudo systemctl stop domain-checker.timer
sudo systemctl disable domain-checker.timer
sudo systemctl disable domain-checker.service
sudo rm -f /etc/systemd/system/domain-checker.service
sudo rm -f /etc/systemd/system/domain-checker.timer
sudo systemctl daemon-reload
```

Then remove the checker directory and dedicated user only if you no longer need the results.

---

## 📄 License

MIT - Use freely

---

## 🔗 Related

- [DPI Bypass Landscape](https://github.com/bol-van/zapret) - Censorship evasion techniques
- [Xray-core](https://github.com/XTLS/Xray-core) - REALITY proxy
- [Hysteria](https://github.com/apernet/hysteria) - QUIC tunnel

---

**Deploy to any Ubuntu/Debian VPS with one command.**

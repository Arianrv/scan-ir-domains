#!/bin/bash
# scan-ir-domains - Universal installer
# Works on any Linux VPS (Ubuntu/Debian)
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/Arianrv/scan-ir-domains/main/install.sh)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_URL="https://github.com/Arianrv/scan-ir-domains.git"
REQUIRED_FILES=("iran_domain_checker.py" "analyze_results.py" "install.sh")
TMP_DIR=""

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

fail() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

validate_integer() {
    local value="$1"
    local name="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
        fail "$name must be a positive integer"
    fi
}

validate_username() {
    local value="$1"
    if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
        fail "Invalid Linux username: $value"
    fi
}

print_banner() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   scan-ir-domains - Automatic Setup    ║${NC}"
    echo -e "${BLUE}║                 by                     ║${NC}"
    echo -e "${BLUE}║  github.com/Arianrv/scan-ir-domains/   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_banner

if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root. Try: sudo bash install.sh"
fi

print_section "Installation Mode"
echo "1) Create new dedicated user (recommended)"
echo "2) Install for current root user"
echo ""
read -p "Choose option (1 or 2): " INSTALL_MODE

if [ "$INSTALL_MODE" = "1" ]; then
    read -p "Enter username for new user (default: domainchecker): " CHECKER_USER
    CHECKER_USER=${CHECKER_USER:-domainchecker}
    validate_username "$CHECKER_USER"
    INSTALL_AS_ROOT=false
elif [ "$INSTALL_MODE" = "2" ]; then
    CHECKER_USER="root"
    INSTALL_AS_ROOT=true
else
    fail "Invalid option"
fi

CHECKER_HOME="/home/$CHECKER_USER"
if [ "$INSTALL_AS_ROOT" = true ]; then
    CHECKER_HOME="/root"
fi
CHECKER_DIR="$CHECKER_HOME/checker"

echo ""
print_section "Performance Configuration"
echo ""
echo "Workers (parallel connections):"
echo "  1-20:   Conservative (slower, safer)"
echo "  50:     Balanced (default, recommended)"
echo "  100+:   Aggressive (faster, more load)"
echo ""
read -p "Enter number of workers (default: 50): " WORKERS_INPUT
WORKERS=${WORKERS_INPUT:-50}
validate_integer "$WORKERS" "Workers"

echo ""
echo "Timeout per domain (in seconds):"
echo "  5-10:   Fast (quick failure detection)"
echo "  10-15:  Balanced (default, recommended)"
echo "  15-30:  Patient (slow servers, fewer timeouts)"
echo ""
read -p "Enter timeout in seconds (default: 10): " TIMEOUT_INPUT
TIMEOUT=${TIMEOUT_INPUT:-10}
validate_integer "$TIMEOUT" "Timeout"

echo ""
print_section "Scan Schedule Configuration"
echo ""
echo "Daily scan time (24-hour format, UTC):"
echo "  02:00 = 2 AM (default, recommended)"
echo "  14:00 = 2 PM"
echo "  00:00 = Midnight"
echo "  12:00 = Noon"
echo ""
read -p "Enter scan time (HH:MM format, default: 02:00): " SCAN_TIME_INPUT
SCAN_TIME=${SCAN_TIME_INPUT:-02:00}

if ! [[ $SCAN_TIME =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo -e "${RED}Invalid time format. Using default: 02:00${NC}"
    SCAN_TIME="02:00"
fi

echo ""
print_section "First Scan"
echo ""
echo "Run first full scan immediately after installation?"
echo "  This will query Certificate Transparency logs and scan all discovered .ir domains."
echo "  If CT logs are temporarily unavailable, installation still succeeds and the scan is skipped."
echo ""
read -p "Run first full scan? (y/n, default: y): " RUN_FIRST_SCAN_INPUT
RUN_FIRST_SCAN=${RUN_FIRST_SCAN_INPUT:-y}

echo ""
print_section "Installation Summary"
echo "  User: $CHECKER_USER"
echo "  Home: $CHECKER_DIR"
echo "  Workers: $WORKERS"
echo "  Timeout: ${TIMEOUT}s"
echo "  Daily scan time: ${SCAN_TIME} UTC"
echo "  Run first full scan: $([ "$RUN_FIRST_SCAN" = "y" ] && echo "Yes" || echo "No")"
echo ""
read -p "Continue with installation? (y/n): " CONTINUE
if [ "$CONTINUE" != "y" ]; then
    echo -e "${YELLOW}Installation cancelled${NC}"
    exit 0
fi

echo ""
print_section "Starting Installation..."
echo ""

echo -e "${BLUE}[1/9]${NC} ${YELLOW}Updating system packages${NC} (this may take a minute)..."
apt update > /dev/null 2>&1 && echo "  └─ Running apt update"
apt upgrade -y > /dev/null 2>&1 && echo "  └─ Upgrading packages"
apt install -y python3 python3-pip python3-venv git curl ca-certificates sudo > /dev/null 2>&1 && echo "  └─ Installing dependencies"
echo -e "${GREEN}✓ System updated${NC}"
echo ""

echo -e "${BLUE}[2/9]${NC} ${YELLOW}Setting up user account${NC}..."
if [ "$INSTALL_AS_ROOT" = false ]; then
    if id "$CHECKER_USER" &>/dev/null; then
        echo "  └─ User $CHECKER_USER already exists"
    else
        useradd -m -s /bin/bash "$CHECKER_USER" && echo "  └─ Created user: $CHECKER_USER"
    fi
else
    echo "  └─ Using root user"
fi
echo -e "${GREEN}✓ User setup complete${NC}"
echo ""

echo -e "${BLUE}[3/9]${NC} ${YELLOW}Preparing installation directory${NC}..."
mkdir -p "$CHECKER_DIR"
chown -R "$CHECKER_USER:$CHECKER_USER" "$CHECKER_HOME"
chmod 755 "$CHECKER_HOME"
chmod 755 "$CHECKER_DIR"
echo "  └─ Prepared: $CHECKER_DIR"
echo -e "${GREEN}✓ Directory ready${NC}"
echo ""

echo -e "${BLUE}[4/9]${NC} ${YELLOW}Cloning repository from GitHub${NC} (downloading files)..."
TMP_DIR=$(mktemp -d)
REPO_DIR="$TMP_DIR/repo"
CLONE_LOG="$TMP_DIR/git-clone.log"

if ! git clone --depth 1 "$REPO_URL" "$REPO_DIR" > "$CLONE_LOG" 2>&1; then
    echo -e "${RED}Git clone output:${NC}"
    sed 's/^/  │ /' "$CLONE_LOG" || true
    fail "Repository clone failed from $REPO_URL"
fi

cp -a "$REPO_DIR"/. "$CHECKER_DIR"/
mkdir -p "$CHECKER_DIR"/{data,logs,results}
chown -R "$CHECKER_USER:$CHECKER_USER" "$CHECKER_DIR"
chmod -R u+rwX,go+rX "$CHECKER_DIR"

for required_file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$CHECKER_DIR/$required_file" ]; then
        fail "Missing required file after clone: $required_file"
    fi
    echo "  └─ Downloaded: $required_file"
done

echo "  └─ Created: $CHECKER_DIR/data"
echo "  └─ Created: $CHECKER_DIR/logs"
echo "  └─ Created: $CHECKER_DIR/results"
echo -e "${GREEN}✓ Repository cloned and verified${NC}"
echo ""

echo -e "${BLUE}[5/9]${NC} ${YELLOW}Setting up Python virtual environment${NC} (this may take 30 seconds)..."
echo "  └─ Creating venv..."
sudo -u "$CHECKER_USER" python3 -m venv "$CHECKER_DIR/venv" > /dev/null 2>&1
echo "  └─ Installing pip packages..."
sudo -u "$CHECKER_USER" "$CHECKER_DIR/venv/bin/pip" install --upgrade pip > /dev/null 2>&1
sudo -u "$CHECKER_USER" "$CHECKER_DIR/venv/bin/pip" install aiohttp aiofiles certifi requests > /dev/null 2>&1 && echo "  └─ Installed: aiohttp, aiofiles, certifi, requests"
echo -e "${GREEN}✓ Python environment ready${NC}"
echo ""

echo -e "${BLUE}[6/9]${NC} ${YELLOW}Testing installation${NC} (verifying files and packages)..."
for required_file in "${REQUIRED_FILES[@]}"; do
    [ -f "$CHECKER_DIR/$required_file" ] || fail "Required file missing: $required_file"
done
TEST=$($CHECKER_DIR/venv/bin/python3 -c "import aiohttp, aiofiles, certifi, requests; print('ok')" 2>/dev/null)
if [ "$TEST" != "ok" ]; then
    fail "Installation test failed"
fi
echo "  └─ Required files verified"
echo "  └─ Python packages verified"
echo -e "${GREEN}✓ Installation test passed${NC}"
echo ""

echo -e "${BLUE}[7/9]${NC} ${YELLOW}Creating systemd service and timer${NC} (daily scheduler)..."
cat > "/etc/systemd/system/domain-checker.service" <<SVCEOF
[Unit]
Description=scan-ir-domains - Iranian Domain Checker
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$CHECKER_USER
WorkingDirectory=$CHECKER_DIR
Environment="PATH=$CHECKER_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=/bin/bash -lc 'cd "$CHECKER_DIR" && "$CHECKER_DIR/venv/bin/python3" "$CHECKER_DIR/iran_domain_checker.py" --output "$CHECKER_DIR/results/scan_\$(date +%%Y%%m%%d_%%H%%M%%S).jsonl" --workers $WORKERS --timeout $TIMEOUT --batch 10'
StandardOutput=journal
StandardError=journal
SyslogIdentifier=domain-checker

[Install]
WantedBy=multi-user.target
SVCEOF

cat > "/etc/systemd/system/domain-checker.timer" <<TMREOF
[Unit]
Description=Run scan-ir-domains daily at $SCAN_TIME UTC
Requires=domain-checker.service

[Timer]
OnCalendar=*-*-* $SCAN_TIME:00
Persistent=false
AccuracySec=1s
Unit=domain-checker.service

[Install]
WantedBy=timers.target
TMREOF

if command -v systemd-analyze > /dev/null 2>&1; then
    systemd-analyze verify /etc/systemd/system/domain-checker.service /etc/systemd/system/domain-checker.timer
fi
systemctl daemon-reload
systemctl enable domain-checker.timer > /dev/null 2>&1
systemctl restart domain-checker.timer > /dev/null 2>&1
echo "  └─ Created systemd service"
echo "  └─ Created daily timer (runs at ${SCAN_TIME} UTC)"
echo "  └─ Timer enabled and started"
echo -e "${GREEN}✓ Systemd service created${NC}"
echo ""

echo -e "${BLUE}[8/9]${NC} ${YELLOW}Creating helper scripts${NC}..."
cat > "$CHECKER_DIR/status.sh" <<'SCRIPTEOF'
#!/bin/bash
set -euo pipefail

echo "=== scan-ir-domains Status ==="
echo "Time: $(date)"
echo ""

LATEST=$(ls -t results/scan_*.jsonl 2>/dev/null | head -1 || true)
if [ -n "$LATEST" ]; then
    echo "Latest scan: $(basename "$LATEST")"
    echo "Size: $(du -h "$LATEST" | cut -f1)"
    echo "Lines (domains): $(wc -l < "$LATEST")"
    echo "Age: $(date -r "$LATEST" '+%Y-%m-%d %H:%M:%S')"
else
    echo "Status: No scans yet"
fi

echo ""
echo "Disk usage:"
du -sh results/ logs/ data/ 2>/dev/null || echo "  N/A"
echo ""
echo "Next scheduled scan:"
systemctl list-timers domain-checker.timer 2>/dev/null | grep domain-checker || echo "  Timer info unavailable"
SCRIPTEOF
chmod +x "$CHECKER_DIR/status.sh"
chown "$CHECKER_USER:$CHECKER_USER" "$CHECKER_DIR/status.sh"
echo "  └─ Created: status.sh"
echo -e "${GREEN}✓ Helper scripts created${NC}"
echo ""

echo -e "${BLUE}[9/9]${NC} ${YELLOW}Configuring firewall${NC} (UFW - if available)..."
if command -v ufw &> /dev/null; then
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow ssh > /dev/null 2>&1
    ufw allow out to any port 53 > /dev/null 2>&1
    ufw allow out to any port 80 > /dev/null 2>&1
    ufw allow out to any port 443 > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1
    echo "  └─ UFW firewall configured"
else
    echo "  └─ UFW not available (skipped)"
fi
echo -e "${GREEN}✓ Firewall configured${NC}"
echo ""

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ Installation Complete!             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

if [ "$RUN_FIRST_SCAN" = "y" ]; then
    print_section "Running First Full Scan..."
    echo ""
    echo "Scanning .ir domains from Certificate Transparency logs..."
    echo "This may take several minutes depending on CT log availability and network speed."
    echo ""

    cd "$CHECKER_DIR"
    if sudo -u "$CHECKER_USER" "$CHECKER_DIR/venv/bin/python3" "$CHECKER_DIR/iran_domain_checker.py" \
        --output "$CHECKER_DIR/results/scan_$(date +%Y%m%d_%H%M%S).jsonl" \
        --workers "$WORKERS" \
        --timeout "$TIMEOUT" \
        --batch 10; then
        echo ""
        echo -e "${GREEN}✓ First full scan complete!${NC}"
    else
        echo ""
        echo -e "${YELLOW}⚠ First full scan did not complete.${NC}"
        echo "  Certificate Transparency discovery may be temporarily unavailable."
        echo "  No fallback test scan was saved as a real result."
        echo "  Retry manually:"
        echo "   cd $CHECKER_DIR"
        echo "   sudo -u $CHECKER_USER $CHECKER_DIR/venv/bin/python3 iran_domain_checker.py --output $CHECKER_DIR/results/scan_\$(date +%Y%m%d_%H%M%S).jsonl --workers $WORKERS --timeout $TIMEOUT --batch 10"
    fi
    echo ""
fi

print_section "Next Steps - How to Use"
echo ""
echo -e "${GREEN}1. Check Status${NC}"
echo "   sudo -u $CHECKER_USER $CHECKER_DIR/status.sh"
echo ""
echo -e "${GREEN}2. View Live Logs${NC}"
echo "   sudo journalctl -u domain-checker.service -f"
echo ""
echo -e "${GREEN}3. Manual Full Scan${NC}"
echo "   cd $CHECKER_DIR"
echo "   sudo -u $CHECKER_USER $CHECKER_DIR/venv/bin/python3 iran_domain_checker.py --output $CHECKER_DIR/results/scan_\$(date +%Y%m%d_%H%M%S).jsonl --workers $WORKERS --timeout $TIMEOUT --batch 10"
echo ""
echo -e "${GREEN}4. Manual Test Scan${NC}"
echo "   cd $CHECKER_DIR"
echo "   source venv/bin/activate"
echo "   python3 iran_domain_checker.py --domains 'test.ir,example.ir' --timeout 5"
echo ""
echo -e "${GREEN}5. View Results${NC}"
echo "   ls -lh $CHECKER_DIR/results/"
echo ""
echo -e "${GREEN}6. Analyze Results${NC}"
echo "   cd $CHECKER_DIR"
echo "   source venv/bin/activate"
echo "   python3 analyze_results.py results/scan_*.jsonl --format summary"
echo ""
echo -e "${GREEN}7. Download Results to Local Machine${NC}"
echo "   scp -r root@YOUR_SERVER_IP:$CHECKER_DIR/results/ ./local_backups/"
echo ""

print_section "Timer Configuration"
echo ""
echo -e "${YELLOW}✓ Daily scans are scheduled to run at${NC} ${GREEN}${SCAN_TIME} UTC${NC}"
echo "  Check next run: sudo systemctl list-timers domain-checker.timer"
echo ""
echo -e "${YELLOW}To change scan time:${NC}"
echo "  sudo nano /etc/systemd/system/domain-checker.timer"
echo "  Edit the line: OnCalendar=*-*-* ${SCAN_TIME}:00"
echo "  Example for 14:00 UTC: OnCalendar=*-*-* 14:00:00"
echo "  Then: sudo systemctl daemon-reload && sudo systemctl restart domain-checker.timer"
echo ""

print_section "Uninstallation"
echo ""
echo -e "${GREEN}Easy way (Automatic):${NC}"
echo "   bash <(curl -fsSL https://raw.githubusercontent.com/Arianrv/scan-ir-domains/main/uninstall.sh)"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✓ All done! Automated scanning is now configured.${NC}"
echo ""

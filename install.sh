#!/bin/bash
# Universal installer for scan-ir-domains
# Works on any Linux VPS (Ubuntu/Debian)
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/scan-ir-domains/main/install.sh)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Scan-ir-domains - Automatic Setup    ║${NC}"
echo -e "${BLUE}║                 by                     ║${NC}"
echo -e "${BLUE}║  github.com/Arianrv/scan-ir-domains/   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

GITHUB_USERNAME="${GITHUB_USERNAME:-YOUR_USERNAME}"
REPO_URL="https://github.com/$GITHUB_USERNAME/scan-ir-domains.git"
CHECKER_USER="domainchecker"
CHECKER_HOME="/home/$CHECKER_USER"
CHECKER_DIR="$CHECKER_HOME/checker"
WORKERS="${WORKERS:-50}"
TIMEOUT="${TIMEOUT:-10}"

echo -e "${YELLOW}Configuration:${NC}"
echo "  User: $CHECKER_USER"
echo "  Home: $CHECKER_DIR"
echo "  Workers: $WORKERS"
echo "  Timeout: ${TIMEOUT}s"
echo ""

# Step 1: Update system
echo -e "${BLUE}[1/9]${NC} ${YELLOW}Updating system...${NC}"
apt update > /dev/null 2>&1
apt upgrade -y > /dev/null 2>&1
apt install -y python3 python3-pip python3-venv git curl > /dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# Step 2: Create user
echo -e "${BLUE}[2/9]${NC} ${YELLOW}Setting up user...${NC}"
if ! id "$CHECKER_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$CHECKER_USER"
fi
echo -e "${GREEN}✓${NC}"

# Step 3: Create directories
echo -e "${BLUE}[3/9]${NC} ${YELLOW}Creating directories...${NC}"
mkdir -p "$CHECKER_DIR"/{data,logs,results}
chown -R "$CHECKER_USER:$CHECKER_USER" "$CHECKER_HOME"
chmod -R 755 "$CHECKER_HOME"
echo -e "${GREEN}✓${NC}"

# Step 4: Clone repository
echo -e "${BLUE}[4/9]${NC} ${YELLOW}Cloning repository...${NC}"
cd "$CHECKER_DIR"
if [ ! -d ".git" ]; then
    sudo -u "$CHECKER_USER" git clone "$REPO_URL" . > /dev/null 2>&1
fi
echo -e "${GREEN}✓${NC}"

# Step 5: Setup Python venv
echo -e "${BLUE}[5/9]${NC} ${YELLOW}Setting up Python environment...${NC}"
sudo -u "$CHECKER_USER" python3 -m venv "$CHECKER_DIR/venv" > /dev/null 2>&1
sudo -u "$CHECKER_USER" "$CHECKER_DIR/venv/bin/pip" install --upgrade pip > /dev/null 2>&1
sudo -u "$CHECKER_USER" "$CHECKER_DIR/venv/bin/pip" install aiohttp aiofiles certifi requests > /dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# Step 6: Test installation
echo -e "${BLUE}[6/9]${NC} ${YELLOW}Testing installation...${NC}"
TEST=$($CHECKER_DIR/venv/bin/python3 -c "import aiohttp; print('ok')" 2>/dev/null)
if [ "$TEST" != "ok" ]; then
    echo -e "${RED}✗ Installation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC}"

# Step 7: Create systemd service
echo -e "${BLUE}[7/9]${NC} ${YELLOW}Creating systemd service...${NC}"
cat > "/etc/systemd/system/domain-checker.service" <<SVCEOF
[Unit]
Description=Iranian Domain Checker
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$CHECKER_USER
WorkingDirectory=$CHECKER_DIR
Environment="PATH=$CHECKER_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=$CHECKER_DIR/venv/bin/python3 iran_domain_checker.py \\
    --output results/scan_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).jsonl \\
    --workers $WORKERS \\
    --timeout $TIMEOUT \\
    --batch 10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=domain-checker

[Install]
WantedBy=multi-user.target
SVCEOF

cat > "/etc/systemd/system/domain-checker.timer" <<TMREOF
[Unit]
Description=Run Iranian Domain Checker daily
Requires=domain-checker.service

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
TMREOF

systemctl daemon-reload
systemctl enable domain-checker.timer > /dev/null 2>&1
systemctl start domain-checker.timer > /dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# Step 8: Create helper script
echo -e "${BLUE}[8/9]${NC} ${YELLOW}Creating helper scripts...${NC}"
cat > "$CHECKER_DIR/status.sh" <<'SCRIPTEOF'
#!/bin/bash
echo "=== Domain Checker Status ==="
echo "Time: $(date)"
LATEST=$(ls -t results/scan_*.jsonl 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
    echo "Latest: $(basename $LATEST)"
    echo "Size: $(du -h $LATEST | cut -f1)"
    echo "Lines: $(wc -l < $LATEST)"
else
    echo "No scans yet"
fi
echo "Disk: $(du -sh results/ 2>/dev/null || echo 'N/A')"
SCRIPTEOF
chmod +x "$CHECKER_DIR/status.sh"
chown "$CHECKER_USER:$CHECKER_USER" "$CHECKER_DIR/status.sh"
echo -e "${GREEN}✓${NC}"

# Step 9: Firewall
echo -e "${BLUE}[9/9]${NC} ${YELLOW}Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw --force enable > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow ssh > /dev/null 2>&1
    ufw allow out to any port 53 > /dev/null 2>&1
    ufw allow out to any port 80 > /dev/null 2>&1
    ufw allow out to any port 443 > /dev/null 2>&1
fi
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✓ Setup Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next:${NC}"
echo "  Check timer: sudo systemctl list-timers domain-checker.timer"
echo "  View logs: sudo journalctl -u domain-checker.service -f"
echo "  Test: cd $CHECKER_DIR && source venv/bin/activate && python3 iran_domain_checker.py --domains 'test.ir'"
echo ""
echo -e "${YELLOW}Timer runs daily at 02:00 UTC${NC}"

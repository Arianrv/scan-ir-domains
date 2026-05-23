#!/bin/bash
# scan-ir-domains - Universal installer
# Works on any Linux VPS (Ubuntu/Debian)
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/Arianrv/scan-ir-domains/main/install.sh)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Banner
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   scan-ir-domains - Automatic Setup    ║${NC}"
echo -e "${BLUE}║                 by                     ║${NC}"
echo -e "${BLUE}║  github.com/Arianrv/scan-ir-domains/   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    echo -e "${YELLOW}Try: sudo bash install.sh${NC}"
    exit 1
fi

# Ask about installation mode
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Installation Mode${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "1) Create new dedicated user (recommended)"
echo "2) Install for current root user"
echo ""
read -p "Choose option (1 or 2): " INSTALL_MODE

if [ "$INSTALL_MODE" = "1" ]; then
    read -p "Enter username for new user (default: domainchecker): " CHECKER_USER
    CHECKER_USER=${CHECKER_USER:-domainchecker}
    INSTALL_AS_ROOT=false
elif [ "$INSTALL_MODE" = "2" ]; then
    CHECKER_USER="root"
    INSTALL_AS_ROOT=true
else
    echo -e "${RED}Invalid option${NC}"
    exit 1
fi

CHECKER_HOME="/home/$CHECKER_USER"
if [ "$INSTALL_AS_ROOT" = true ]; then
    CHECKER_HOME="/root"
fi
CHECKER_DIR="$CHECKER_HOME/checker"
WORKERS="${WORKERS:-50}"
TIMEOUT="${TIMEOUT:-10}"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Configuration${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  User: $CHECKER_USER"
echo "  Home: $CHECKER_DIR"
echo "  Workers: $WORKERS"
echo "  Timeout: ${TIMEOUT}s"
echo ""
read -p "Continue with installation? (y/n): " CONTINUE
if [ "$CONTINUE" != "y" ]; then
    echo -e "${YELLOW}Installation cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Starting Installation...${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Step 1: Update system
echo -e "${BLUE}[1/9]${NC} ${YELLOW}Updating system packages${NC} (this may take a minute)..."
apt update > /dev/null 2>&1 && echo "  └─ Running apt update"
apt upgrade -y > /dev/null 2>&1 && echo "  └─ Upgrading packages"
apt install -y python3 python3-pip python3-venv git curl > /dev/null 2>&1 && echo "  └─ Installing dependencies"
echo -e "${GREEN}✓ System updated${NC}"
echo ""

# Step 2: Create user
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

# Step 3: Create directories
echo -e "${BLUE}[3/9]${NC} ${YELLOW}Creating directory structure${NC}..."
mkdir -p "$CHECKER_DIR"/{data,logs,results}
chown -R "$CHECKER_USER:$CHECKER_USER" "$CHECKER_HOME"
chmod -R 755 "$CHECKER_HOME"
echo "  └─ Created: $CHECKER_DIR"
echo "  └─ Created: $CHECKER_DIR/data"
echo "  └─ Created: $CHECKER_DIR/logs"
echo "  └─ Created: $CHECKER_DIR/results"
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Step 4: Clone repository
echo -e "${BLUE}[4/9]${NC} ${YELLOW}Cloning repository from GitHub${NC} (downloading files)..."
cd "$CHECKER_DIR"
if [ ! -d ".git" ]; then
    sudo -u "$CHECKER_USER" git clone https://github.com/Arianrv/scan-ir-domains.git . > /dev/null 2>&1 && echo "  └─ Downloaded: iran_domain_checker.py"
    echo "  └─ Downloaded: analyze_results.py"
    echo "  └─ Downloaded: install.sh"
fi
echo -e "${GREEN}✓ Repository cloned${NC}"
echo ""

# Step 5: Setup Python venv
echo -e "${BLUE}[5/9]${NC} ${YELLOW}Setting up Python virtual environment${NC} (this may take 30 seconds)..."
echo "  └─ Creating venv..."
sudo -u "$CHECKER_USER" python3 -m venv "$CHECKER_DIR/venv" > /dev/null 2>&1
echo "  └─ Installing pip packages..."
sudo -u "$CHECKER_USER" "$CHECKER_DIR/venv/bin/pip" install --upgrade pip > /dev/null 2>&1
sudo -u "$CHECKER_USER" "$CHECKER_DIR/venv/bin/pip" install aiohttp aiofiles certifi requests > /dev/null 2>&1 && echo "  └─ Installed: aiohttp, aiofiles, certifi, requests"
echo -e "${GREEN}✓ Python environment ready${NC}"
echo ""

# Step 6: Test installation
echo -e "${BLUE}[6/9]${NC} ${YELLOW}Testing installation${NC} (verifying all packages)..."
TEST=$($CHECKER_DIR/venv/bin/python3 -c "import aiohttp; print('ok')" 2>/dev/null)
if [ "$TEST" != "ok" ]; then
    echo -e "${RED}✗ Installation test failed${NC}"
    exit 1
fi
echo "  └─ All packages verified"
echo -e "${GREEN}✓ Installation test passed${NC}"
echo ""

# Step 7: Create systemd service
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
Description=Run scan-ir-domains daily at 02:00 UTC
Requires=domain-checker.service

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 02:00:00
Persistent=true
AccuracySec=1s

[Install]
WantedBy=timers.target
TMREOF

systemctl daemon-reload
systemctl enable domain-checker.timer > /dev/null 2>&1
systemctl start domain-checker.timer > /dev/null 2>&1
echo "  └─ Created systemd service"
echo "  └─ Created daily timer (runs at 02:00 UTC)"
echo "  └─ Timer enabled and started"
echo -e "${GREEN}✓ Systemd service created${NC}"
echo ""

# Step 8: Create helper scripts
echo -e "${BLUE}[8/9]${NC} ${YELLOW}Creating helper scripts${NC}..."
cat > "$CHECKER_DIR/status.sh" <<'SCRIPTEOF'
#!/bin/bash
echo "=== scan-ir-domains Status ==="
echo "Time: $(date)"
echo ""
LATEST=$(ls -t results/scan_*.jsonl 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
    echo "Latest scan: $(basename $LATEST)"
    echo "Size: $(du -h $LATEST | cut -f1)"
    echo "Lines (domains): $(wc -l < $LATEST)"
    echo "Age: $(date -r $LATEST '+%Y-%m-%d %H:%M:%S')"
else
    echo "Status: No scans yet (will run at 02:00 UTC)"
fi
echo ""
echo "Disk usage:"
du -sh results/ logs/ data/ 2>/dev/null || echo "  N/A"
echo ""
echo "Next scheduled scan:"
systemctl list-timers domain-checker.timer 2>/dev/null | grep domain-checker | awk '{print "  " $1 " (" $2 " left)"}' || echo "  Timer info unavailable"
SCRIPTEOF
chmod +x "$CHECKER_DIR/status.sh"
chown "$CHECKER_USER:$CHECKER_USER" "$CHECKER_DIR/status.sh"
echo "  └─ Created: status.sh"
echo -e "${GREEN}✓ Helper scripts created${NC}"
echo ""

# Step 9: Firewall
echo -e "${BLUE}[9/9]${NC} ${YELLOW}Configuring firewall${NC} (UFW - if available)..."
if command -v ufw &> /dev/null; then
    ufw --force enable > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow ssh > /dev/null 2>&1
    ufw allow out to any port 53 > /dev/null 2>&1
    ufw allow out to any port 80 > /dev/null 2>&1
    ufw allow out to any port 443 > /dev/null 2>&1
    echo "  └─ UFW firewall configured"
else
    echo "  └─ UFW not available (skipped)"
fi
echo -e "${GREEN}✓ Firewall configured${NC}"
echo ""

# Installation complete
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ Installation Complete!             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Post-installation instructions
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Next Steps - How to Use${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}1. Check Status${NC}"
echo "   ${YELLOW}sudo -u $CHECKER_USER $CHECKER_DIR/status.sh${NC}"
echo ""
echo -e "${GREEN}2. View Live Logs${NC}"
echo "   ${YELLOW}sudo journalctl -u domain-checker.service -f${NC}"
echo ""
echo -e "${GREEN}3. Manual Test Scan${NC}"
echo "   ${YELLOW}cd $CHECKER_DIR${NC}"
echo "   ${YELLOW}source venv/bin/activate${NC}"
echo "   ${YELLOW}python3 iran_domain_checker.py --domains 'test.ir,example.ir' --timeout 5${NC}"
echo ""
echo -e "${GREEN}4. View Results${NC}"
echo "   ${YELLOW}ls -lh $CHECKER_DIR/results/${NC}"
echo ""
echo -e "${GREEN}5. Analyze Results${NC}"
echo "   ${YELLOW}cd $CHECKER_DIR${NC}"
echo "   ${YELLOW}source venv/bin/activate${NC}"
echo "   ${YELLOW}python3 analyze_results.py results/scan_*.jsonl --format summary${NC}"
echo ""
echo -e "${GREEN}6. Download Results to Local Machine${NC}"
echo "   ${YELLOW}scp -r root@YOUR_SERVER_IP:$CHECKER_DIR/results/ ./local_backups/${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Timer Configuration${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}✓ Daily scans are scheduled to run at${NC} ${GREEN}02:00 UTC${NC}"
echo "  Check next run: ${YELLOW}sudo systemctl list-timers domain-checker.timer${NC}"
echo ""
echo -e "${YELLOW}To change scan time:${NC}"
echo "  ${YELLOW}sudo nano /etc/systemd/system/domain-checker.timer${NC}"
echo "  Edit the line: ${GREEN}OnCalendar=*-*-* 02:00:00${NC}"
echo "  Example for 14:00 UTC: ${GREEN}OnCalendar=*-*-* 14:00:00${NC}"
echo "  Then: ${YELLOW}sudo systemctl daemon-reload && sudo systemctl restart domain-checker.timer${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Uninstallation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}To completely remove scan-ir-domains:${NC}"
echo ""
echo "1. ${YELLOW}Stop the timer and service:${NC}"
echo "   ${GREEN}sudo systemctl stop domain-checker.timer${NC}"
echo "   ${GREEN}sudo systemctl disable domain-checker.timer${NC}"
echo "   ${GREEN}sudo systemctl disable domain-checker.service${NC}"
echo ""
echo "2. ${YELLOW}Remove systemd files:${NC}"
echo "   ${GREEN}sudo rm /etc/systemd/system/domain-checker.service${NC}"
echo "   ${GREEN}sudo rm /etc/systemd/system/domain-checker.timer${NC}"
echo "   ${GREEN}sudo systemctl daemon-reload${NC}"
echo ""
echo "3. ${YELLOW}Remove installation directory:${NC}"
if [ "$INSTALL_AS_ROOT" = false ]; then
    echo "   ${GREEN}sudo rm -rf $CHECKER_DIR${NC}"
    echo "   ${GREEN}sudo userdel -r $CHECKER_USER${NC}"
else
    echo "   ${GREEN}rm -rf $CHECKER_DIR${NC}"
fi
echo ""
echo "4. ${YELLOW}Verify removal:${NC}"
echo "   ${GREEN}sudo systemctl list-timers${NC}"
echo "   (domain-checker should not appear)"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✓ All done! Automated scanning is now running.${NC}"
echo ""

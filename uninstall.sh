#!/bin/bash
# scan-ir-domains - Safe uninstaller
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/Arianrv/scan-ir-domains/main/uninstall.sh)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

fail() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root. Try: sudo bash uninstall.sh"
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   scan-ir-domains - Safe Uninstall     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

read -p "Installed username (default: domainchecker, use root if installed as root): " CHECKER_USER
CHECKER_USER=${CHECKER_USER:-domainchecker}

if [ "$CHECKER_USER" = "root" ]; then
    CHECKER_HOME="/root"
else
    CHECKER_HOME="/home/$CHECKER_USER"
fi
CHECKER_DIR="$CHECKER_HOME/checker"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Uninstall Summary${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  User: $CHECKER_USER"
echo "  Directory: $CHECKER_DIR"
echo "  Service: domain-checker.service"
echo "  Timer: domain-checker.timer"
echo ""
read -p "Continue with uninstall? (y/n): " CONTINUE
if [ "$CONTINUE" != "y" ]; then
    echo -e "${YELLOW}Uninstall cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}[1/5]${NC} ${YELLOW}Stopping systemd units${NC}..."
systemctl stop domain-checker.timer 2>/dev/null || true
systemctl stop domain-checker.service 2>/dev/null || true
systemctl disable domain-checker.timer 2>/dev/null || true
systemctl disable domain-checker.service 2>/dev/null || true
echo -e "${GREEN}✓ Units stopped and disabled${NC}"

echo ""
echo -e "${BLUE}[2/5]${NC} ${YELLOW}Removing systemd files${NC}..."
rm -f /etc/systemd/system/domain-checker.service
rm -f /etc/systemd/system/domain-checker.timer
systemctl daemon-reload
systemctl reset-failed domain-checker.service domain-checker.timer 2>/dev/null || true
echo -e "${GREEN}✓ Systemd files removed${NC}"

echo ""
echo -e "${BLUE}[3/5]${NC} ${YELLOW}Handling installed files${NC}..."
if [ -d "$CHECKER_DIR" ]; then
    read -p "Delete $CHECKER_DIR including results/logs? (y/n, default: n): " DELETE_FILES
    DELETE_FILES=${DELETE_FILES:-n}
    if [ "$DELETE_FILES" = "y" ]; then
        rm -rf "$CHECKER_DIR"
        echo "  └─ Removed: $CHECKER_DIR"
    else
        echo "  └─ Kept: $CHECKER_DIR"
    fi
else
    echo "  └─ Directory not found: $CHECKER_DIR"
fi
echo -e "${GREEN}✓ File step complete${NC}"

echo ""
echo -e "${BLUE}[4/5]${NC} ${YELLOW}Handling user account${NC}..."
if [ "$CHECKER_USER" != "root" ] && id "$CHECKER_USER" >/dev/null 2>&1; then
    read -p "Delete Linux user $CHECKER_USER? (y/n, default: n): " DELETE_USER
    DELETE_USER=${DELETE_USER:-n}
    if [ "$DELETE_USER" = "y" ]; then
        userdel -r "$CHECKER_USER" 2>/dev/null || userdel "$CHECKER_USER"
        echo "  └─ Removed user: $CHECKER_USER"
    else
        echo "  └─ Kept user: $CHECKER_USER"
    fi
else
    echo "  └─ No dedicated user to remove"
fi
echo -e "${GREEN}✓ User step complete${NC}"

echo ""
echo -e "${BLUE}[5/5]${NC} ${YELLOW}Verification${NC}..."
if systemctl list-timers --all 2>/dev/null | grep -q domain-checker; then
    fail "domain-checker timer still appears in systemctl list-timers"
fi
if systemctl list-unit-files 2>/dev/null | grep -q domain-checker; then
    fail "domain-checker unit file still appears in systemctl list-unit-files"
fi
echo -e "${GREEN}✓ Verification passed${NC}"

echo ""
echo -e "${GREEN}✓ scan-ir-domains uninstall complete${NC}"
echo ""

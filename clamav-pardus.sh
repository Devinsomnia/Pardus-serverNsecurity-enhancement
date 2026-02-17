#!/bin/bash
# Improved ClamAV installer for Debian-based systems (including 1Panel/Pardus)
# Fixes duplicate LocalSocket / DatabaseDirectory lines that break clamd startup
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=${ID:-unknown}
    else
        OS="unknown"
    fi
}

prepare_directories() {
    echo -e "${GREEN}Preparing directories...${NC}"
    sudo mkdir -p /var/lib/clamav /var/log/clamav /run/clamav
    sudo chown -R clamav:clamav /var/lib/clamav /var/log/clamav /run/clamav
    sudo chmod -R 0755 /var/lib/clamav /var/log/clamav
    sudo chmod 0775 /run/clamav
}

install_clamav() {
    echo -e "${GREEN}Installing ClamAV...${NC}"
    if [[ "$OS" =~ ^(ubuntu|debian|pardus|linuxmint|pop|neon|kali)$ ]]; then
        sudo apt update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt install -y clamav clamav-daemon clamav-freshclam
    else
        echo -e "${RED}This script is optimized for Debian-based systems (including 1Panel).${NC}"
        exit 1
    fi
}

find_clamd_conf() {
    for path in "/etc/clamd.d/scan.conf" "/etc/clamav/clamd.conf"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    echo -e "${RED}clamd config not found in standard locations!${NC}"
    exit 1
}

clean_and_configure_clamd() {
    local conf=$(find_clamd_conf)
    echo -e "${GREEN}Cleaning & configuring $conf ...${NC}"

    sudo cp "$conf" "${conf}.bak-$(date +%F-%H%M%S)" 2>/dev/null || true

    # Remove all previous (possibly duplicated) critical lines
    sudo sed -i '/^[[:space:]]*\(#*\(LocalSocket\|DatabaseDirectory\|PidFile\|LogFile\|LogFileMaxSize\|LogTime\|LogRotate\)\b\)/d' "$conf"

    # Append clean block **once**
    {
        echo ""
        echo "# Cleaned & fixed by install script - $(date +%F)"
        echo "PidFile /run/clamav/clamd.pid"
        echo "DatabaseDirectory /var/lib/clamav"
        echo "LocalSocket /run/clamav/clamd.ctl"
        echo "FixStaleSocket true"
        echo "LocalSocketGroup clamav"
        echo "LocalSocketMode 666"
        echo "User clamav"
        echo "LogFile /var/log/clamav/clamd.log"
        echo "LogFileMaxSize 2M"
        echo "LogTime true"
        echo "LogRotate true"
        echo "LogSyslog false"
    } | sudo tee -a "$conf" >/dev/null

    echo -e "${GREEN}→ $conf cleaned and re-configured (no duplicates)${NC}"
}

configure_freshclam() {
    local conf=""
    for path in "/etc/freshclam.conf" "/etc/clamav/freshclam.conf"; do
        [ -f "$path" ] && conf="$path" && break
    done
    if [ -z "$conf" ]; then
        echo -e "${RED}freshclam.conf not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}Configuring $conf ...${NC}"
    sudo cp "$conf" "${conf}.bak-$(date +%F-%H%M%S)" 2>/dev/null || true

    sudo sed -i '/^[[:space:]]*#*DatabaseDirectory/d' "$conf"
    sudo sed -i '/^[[:space:]]*#*PidFile/d' "$conf"
    sudo sed -i '/^DatabaseMirror/d' "$conf"

    {
        echo "DatabaseDirectory /var/lib/clamav"
        echo "PidFile /run/clamav/freshclam.pid"
        echo "DatabaseMirror database.clamav.net"
    } | sudo tee -a "$conf" >/dev/null

    # Set Checks if needed
    if ! grep -q '^Checks' "$conf"; then
        echo "Checks 12" | sudo tee -a "$conf" >/dev/null
    fi

    echo -e "${GREEN}freshclam configured${NC}"
}

download_database() {
    echo -e "${GREEN}Downloading freshclam database...${NC}"
    sudo systemctl stop clamav-freshclam 2>/dev/null || true

    local max=4
    for ((i=1; i<=max; i++)); do
        echo "Attempt $i/$max..."
        if sudo -u clamav freshclam --quiet; then
            sudo chown -R clamav:clamav /var/lib/clamav
            echo -e "${GREEN}Database OK${NC}"
            return 0
        fi
        sleep 30
    done
    echo -e "${RED}freshclam failed after $max attempts — check logs${NC}"
    exit 1
}

start_and_check() {
    echo -e "${GREEN}Starting & checking services...${NC}"
    sudo systemctl daemon-reload

    sudo systemctl enable --now clamav-freshclam 2>/dev/null || true
    sudo systemctl restart clamav-daemon || sudo systemctl restart clamd@scan 2>/dev/null || true

    sleep 4

    if sudo systemctl is-active --quiet clamav-daemon 2>/dev/null || sudo systemctl is-active --quiet clamd@scan 2>/dev/null; then
        echo -e "${GREEN}ClamAV is running!${NC}"
    else
        echo -e "${RED}Still failed to start — showing logs:${NC}"
        sudo systemctl status clamav-daemon -l --no-pager 2>/dev/null || sudo systemctl status clamd@scan -l --no-pager
        echo ""
        sudo tail -n 40 /var/log/clamav/clamd.log 2>/dev/null || sudo tail -n 40 /var/log/clamav/clamav.log 2>/dev/null
        exit 1
    fi

    echo ""
    echo "Quick test:"
    echo "  sudo systemctl status clamav-daemon"
    echo "  sudo clamscan --version"
    echo "  sudo freshclam   # manual update if needed"
}

# ────────────────────────────────────────────────
main() {
    detect_os
    install_clamav
    prepare_directories
    clean_and_configure_clamd
    configure_freshclam
    download_database
    start_and_check

    echo -e "${GREEN}Installation & fix completed successfully.${NC}"
}

main
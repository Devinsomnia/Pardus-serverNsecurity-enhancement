#!/bin/bash
# Install ClamAV on various Linux distributions (including Pardus)
# Fixed: safe config handling, directory prep, service management
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=${ID:-unknown}
        VERSION=${VERSION_ID:-unknown}
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi
}

prepare_database_dir() {
    echo -e "${GREEN}Preparing database directory...${NC}"
    sudo mkdir -p /var/lib/clamav
    sudo chown -R clamav:clamav /var/lib/clamav 2>/dev/null || sudo chown -R clamav:clamav /var/lib/clamav
    sudo chmod -R 0755 /var/lib/clamav
    sudo mkdir -p /run/clamav
    sudo chown -R clamav:clamav /run/clamav 2>/dev/null || true
}

install_clamav() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"
    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo apt update
            sudo apt install -y clamav clamav-daemon clamav-freshclam
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if [[ "$OS" == "fedora" || ("$OS" == "rhel" && "${VERSION%%.*}" -ge 8) || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
                sudo dnf install -y epel-release
                sudo dnf install -y clamav clamd clamav-update
            else
                sudo yum install -y epel-release
                sudo yum install -y clamav clamd clamav-update
            fi
            ;;
        alpine)
            sudo apk add --no-cache clamav clamav-libunrar clamav-daemon clamav-freshclam
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm clamav
            ;;
        *)
            echo -e "${RED}Unsupported system: $OS${NC}"
            echo "Try for Debian-based (Pardus etc.): sudo apt install clamav clamav-daemon clamav-freshclam"
            exit 1
            ;;
    esac
}

configure_clamd() {
    echo -e "${GREEN}Configuring clamd...${NC}"
  
    local CLAMD_CONF=""
    if [ -f "/etc/clamd.d/scan.conf" ]; then
        CLAMD_CONF="/etc/clamd.d/scan.conf"
    elif [ -f "/etc/clamav/clamd.conf" ]; then
        CLAMD_CONF="/etc/clamav/clamd.conf"
    else
        echo -e "${RED}clamd configuration file not found — please configure manually${NC}"
        exit 1
    fi
  
    sudo cp "$CLAMD_CONF" "${CLAMD_CONF}.bak-$(date +%F-%H%M%S)" 2>/dev/null || true
  
    sudo sed -i '/^#*LogFileMaxSize/ s/^#*/LogFileMaxSize 2M/' "$CLAMD_CONF"
    sudo sed -i '/^#*PidFile/ s/^#*/PidFile \/run\/clamav\/clamd.pid/' "$CLAMD_CONF"
    sudo sed -i '/^#*DatabaseDirectory/ s/^#*/DatabaseDirectory \/var\/lib\/clamav/' "$CLAMD_CONF"
    sudo sed -i '/^#*LocalSocket/ s/^#*/LocalSocket \/run\/clamav\/clamd.ctl/' "$CLAMD_CONF"
  
    echo -e "${GREEN}clamd.conf updated (backup created)${NC}"
}

configure_freshclam() {
    echo -e "${GREEN}Configuring freshclam...${NC}"
  
    local FRESHCLAM_CONF=""
    if [ -f "/etc/freshclam.conf" ]; then
        FRESHCLAM_CONF="/etc/freshclam.conf"
    elif [ -f "/etc/clamav/freshclam.conf" ]; then
        FRESHCLAM_CONF="/etc/clamav/freshclam.conf"
    else
        echo -e "${RED}freshclam configuration file not found — please configure manually${NC}"
        exit 1
    fi
  
    sudo cp "$FRESHCLAM_CONF" "${FRESHCLAM_CONF}.bak-$(date +%F-%H%M%S)" 2>/dev/null || true
  
    # === Safely set DatabaseDirectory (remove all old lines first) ===
    sudo sed -i '/^[[:space:]]*#*DatabaseDirectory/d' "$FRESHCLAM_CONF"
    echo "DatabaseDirectory /var/lib/clamav" | sudo tee -a "$FRESHCLAM_CONF" >/dev/null
  
    # PidFile — same safe approach
    sudo sed -i '/^[[:space:]]*#*PidFile/d' "$FRESHCLAM_CONF"
    echo "PidFile /run/clamav/freshclam.pid" | sudo tee -a "$FRESHCLAM_CONF" >/dev/null
  
    # Remove any existing DatabaseMirror lines and add official one
    sudo sed -i '/^DatabaseMirror/d' "$FRESHCLAM_CONF"
    echo "DatabaseMirror database.clamav.net" | sudo tee -a "$FRESHCLAM_CONF" >/dev/null
  
    # Safely set Checks
    if grep -qi '^Checks' "$FRESHCLAM_CONF"; then
        sudo sed -i '/^[[:space:]]*Checks/ s/.*$/Checks 12/' "$FRESHCLAM_CONF"
    elif grep -qi '^#.*Checks' "$FRESHCLAM_CONF"; then
        sudo sed -i '/^[[:space:]]*#.*Checks/ s/.*Checks.*/Checks 12/' "$FRESHCLAM_CONF"
    else
        echo "Checks 12" | sudo tee -a "$FRESHCLAM_CONF" >/dev/null
    fi
  
    echo -e "${GREEN}freshclam.conf updated safely (backup created)${NC}"
}

download_database() {
    echo -e "${GREEN}Downloading virus database...${NC}"
  
    # Stop & disable any auto-running freshclam to avoid lock/conflicts
    sudo systemctl stop clamav-freshclam 2>/dev/null || true
    sudo systemctl disable clamav-freshclam.timer 2>/dev/null || true
    sudo systemctl disable clamav-freshclam 2>/dev/null || true
  
    local MAX_RETRIES=5
    local RETRY_DELAY=60
    local ATTEMPT=1
  
    while [ $ATTEMPT -le $MAX_RETRIES ]; do
        echo -e "${YELLOW}Attempt $ATTEMPT/$MAX_RETRIES: running freshclam...${NC}"
      
        if sudo -u clamav freshclam --verbose; then
            echo -e "${GREEN}Database downloaded successfully${NC}"
            # Quick post-download ownership fix (manual run sometimes sets root)
            sudo chown -R clamav:clamav /var/lib/clamav 2>/dev/null || true
            return 0
        fi
      
        if [ $ATTEMPT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}Failed — waiting $RETRY_DELAY seconds...${NC}"
            sleep $RETRY_DELAY
        fi
      
        ATTEMPT=$((ATTEMPT + 1))
    done
  
    echo -e "${RED}Failed to download database after $MAX_RETRIES attempts${NC}" >&2
    exit 1
}

verify_database() {
    if [[ ! -f "/var/lib/clamav/main.cvd" && ! -f "/var/lib/clamav/main.cld" ]]; then
        echo -e "${RED}No main database file found after download — something went wrong${NC}"
        echo "Check logs: journalctl -u clamav-freshclam or /var/log/clamav/freshclam.log"
        exit 1
    fi
    echo -e "${GREEN}Database appears present:$(ls -lh /var/lib/clamav/*.c?? 2>/dev/null | head -n 3 || echo ' (files found but ls failed)')${NC}"
}

start_services() {
    echo -e "${GREEN}Starting ClamAV services...${NC}"
  
    # Re-enable freshclam service/timer (we disabled it temporarily)
    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo systemctl enable --now clamav-freshclam
            sudo systemctl enable --now clamav-daemon
            ;;
        centos|rhel|fedora|almalinux|rocky)
            sudo systemctl enable --now clamd@scan
            sudo systemctl enable --now clamav-freshclam
            ;;
        alpine)
            sudo rc-update add clamd boot
            sudo rc-update add freshclam boot
            sudo rc-service clamd start
            sudo rc-service freshclam start
            ;;
        arch|manjaro)
            sudo systemctl enable --now clamav-freshclam
            sudo systemctl enable --now clamav-daemon
            ;;
        *)
            echo -e "${YELLOW}Cannot auto-start services — please do it manually${NC}"
            ;;
    esac
  
    if ! command -v clamscan >/dev/null 2>&1; then
        echo -e "${RED}ClamAV installation appears to have failed (clamscan missing)${NC}"
        exit 1
    fi
  
    echo -e "${GREEN}ClamAV installed and services started${NC}"
    echo ""
    echo "Useful commands:"
    echo "  sudo systemctl status clamav-daemon clamav-freshclam"
    echo "  sudo clamscan -r --bell -i /home          # Example scan"
    echo "  sudo freshclam                            # Manual update"
    echo "  journalctl -u clamav-freshclam -f        # Watch live logs"
}

main() {
    detect_os
    install_clamav
    prepare_database_dir
    configure_clamd
    configure_freshclam
    download_database
    verify_database
    start_services
}

main "$@"
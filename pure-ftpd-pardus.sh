#!/bin/bash
# Install Pure-FTPd
# Supports Ubuntu/Debian/Pardus/CentOS/RHEL/Fedora/Alpine/Arch/Manjaro
# Special support for latest Pardus 25 (Debian 13 trixie based)
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

install_pureftpd() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"
    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo apt update
            sudo apt install -y pure-ftpd pure-ftpd-common
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if [[ "$OS" == "fedora" || ("$OS" == "rhel" && "${VERSION%%.*}" -ge 8) || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
                sudo dnf install -y epel-release
                sudo dnf install -y pure-ftpd
            else
                sudo yum install -y epel-release
                sudo yum install -y pure-ftpd
            fi
            ;;
        alpine)
            sudo apk add --no-cache pure-ftpd
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm pure-ftpd
            ;;
        *)
            echo -e "${RED}Unsupported system: $OS${NC}"
            echo "If Pardus/Debian-based, try: sudo apt install pure-ftpd pure-ftpd-common"
            exit 1
            ;;
    esac

    if ! command -v pure-ftpd >/dev/null 2>&1; then
        echo -e "${RED}Pure-FTPd installation failed (binary not found)${NC}"
        exit 1
    fi
}

configure_pureftpd() {
    echo -e "${GREEN}Configuring Pure-FTPd...${NC}"

    # Create necessary directories
    sudo mkdir -p /etc/pure-ftpd/conf /etc/pure-ftpd/auth /var/log/pure-ftpd

    if [ -d "/etc/pure-ftpd/conf" ]; then
        echo "→ Using Debian/Pardus-style configuration (recommended)"

        # Database file
        sudo touch /etc/pure-ftpd/pureftpd.pdb
        sudo chmod 640 /etc/pure-ftpd/pureftpd.pdb
        sudo chown root:root /etc/pure-ftpd/pureftpd.pdb 2>/dev/null || true  # or pure-ftpd if group exists

        # Config files (one value per file)
        echo '/etc/pure-ftpd/pureftpd.pdb' | sudo tee /etc/pure-ftpd/conf/PureDB >/dev/null
        echo 'yes'                          | sudo tee /etc/pure-ftpd/conf/NoAnonymous >/dev/null
        echo 'no'                           | sudo tee /etc/pure-ftpd/conf/PAMAuthentication >/dev/null
        echo 'no'                           | sudo tee /etc/pure-ftpd/conf/UnixAuthentication >/dev/null
        echo 'yes'                          | sudo tee /etc/pure-ftpd/conf/VerboseLog >/dev/null
        echo '39000 40000'                  | sudo tee /etc/pure-ftpd/conf/PassivePortRange >/dev/null
        echo 'clf:/var/log/pure-ftpd/transfer.log' | sudo tee /etc/pure-ftpd/conf/AltLog >/dev/null

        # Auth link (priority 50 = medium)
        sudo ln -sf ../conf/PureDB /etc/pure-ftpd/auth/50puredb 2>/dev/null || true

    else
        # Fallback: legacy single config file (unlikely on Pardus 25)
        echo "→ Using legacy single config file style"
        local CONF="/etc/pure-ftpd/pure-ftpd.conf"
        if [ -f "$CONF" ]; then
            sudo cp "$CONF" "${CONF}.bak-$(date +%F)"
            sudo sed -i 's/^NoAnonymous[[:space:]]\+no$/NoAnonymous yes/' "$CONF"
            sudo sed -i 's/^PAMAuthentication[[:space:]]\+yes$/PAMAuthentication no/' "$CONF"
            sudo sed -i 's/^# PassivePortRange[[:space:]]\+30000 50000$/PassivePortRange 39000 40000/' "$CONF"
            sudo sed -i 's/^VerboseLog[[:space:]]\+no$/VerboseLog yes/' "$CONF"
            sudo sed -i 's/^# PureDB[[:space:]]\+.*$/PureDB \/etc\/pure-ftpd\/pureftpd.pdb/' "$CONF"
        else
            echo -e "${YELLOW}Warning: No config directory or file found — manual config needed${NC}"
        fi
    fi
}

start_service() {
    echo -e "${GREEN}Starting Pure-FTPd service...${NC}"

    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo systemctl enable pure-ftpd
            sudo systemctl restart pure-ftpd || {
                echo -e "${YELLOW}Restart failed — trying socket activation style...${NC}"
                sudo systemctl restart pure-ftpd.socket 2>/dev/null || true
            }
            ;;
        centos|rhel|fedora|almalinux|rocky)
            sudo systemctl enable pure-ftpd
            sudo systemctl restart pure-ftpd
            ;;
        alpine)
            sudo rc-update add pure-ftpd default
            sudo rc-service pure-ftpd start
            ;;
        arch|manjaro)
            sudo systemctl enable pure-ftpd
            sudo systemctl restart pure-ftpd
            ;;
        *)
            echo -e "${YELLOW}Cannot auto-start service — do it manually${NC}"
            ;;
    esac

    # Show status
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl status pure-ftpd --no-pager || true
    elif command -v rc-service >/dev/null 2>&1; then
        sudo rc-service pure-ftpd status || true
    fi

    echo -e "${GREEN}Pure-FTPd installed & configured${NC}"
    echo ""
    echo "Next steps:"
    echo "  • Add users:   sudo pure-pw useradd username -u $(whoami) -d /home/username"
    echo "  • Then update DB: sudo pure-pw mkdb"
    echo "  • Firewall (if using ufw): sudo ufw allow 21/tcp && sudo ufw allow 39000:40000/tcp"
    echo "  • Logs: tail -f /var/log/pure-ftpd/transfer.log"
}

main() {
    detect_os
    install_pureftpd
    configure_pureftpd
    start_service
}

main "$@"
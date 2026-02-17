#!/bin/bash
# Install Supervisor (process control system)
# Supports Ubuntu/Debian/Pardus/CentOS/RHEL/Fedora/Alpine/Arch/Manjaro
# Pardus 25 (Debian 13 trixie-based) fully supported
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

install_supervisor() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"
    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo apt update
            sudo apt install -y supervisor
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if [[ "$OS" == "fedora" || ("$OS" == "rhel" && "${VERSION%%.*}" -ge 8) || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
                sudo dnf install -y supervisor
            else
                sudo yum install -y epel-release
                sudo yum install -y supervisor
            fi
            ;;
        alpine)
            sudo apk add --no-cache supervisor
            sudo mkdir -p /etc/supervisor.d
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm supervisor
            ;;
        *)
            echo -e "${RED}Unsupported system: $OS${NC}"
            echo "If this is Pardus/Debian-based, try:"
            echo "  sudo apt update && sudo apt install supervisor"
            exit 1
            ;;
    esac

    if ! command -v supervisord >/dev/null 2>&1; then
        echo -e "${RED}Supervisor installation failed (supervisord binary not found)${NC}"
        exit 1
    fi

    # Ensure conf.d directory exists (good practice)
    sudo mkdir -p /etc/supervisor/conf.d
}

start_service() {
    echo -e "${GREEN}Starting Supervisor service...${NC}"

    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo systemctl enable supervisor
            sudo systemctl restart supervisor || {
                echo -e "${YELLOW}Restart failed — check logs with: journalctl -u supervisor${NC}"
            }
            ;;
        centos|rhel|fedora|almalinux|rocky)
            sudo systemctl enable supervisord
            sudo systemctl restart supervisord
            ;;
        alpine)
            sudo rc-update add supervisor default
            sudo rc-service supervisor start
            ;;
        arch|manjaro)
            sudo systemctl enable supervisor
            sudo systemctl restart supervisor
            ;;
        *)
            echo -e "${YELLOW}Cannot auto-start service — start manually (e.g. sudo supervisord)${NC}"
            ;;
    esac

    # Show status
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl status supervisor --no-pager || true
    elif command -v rc-service >/dev/null 2>&1; then
        sudo rc-service supervisor status || true
    fi

    echo -e "${GREEN}Supervisor installed & running${NC}"
    echo ""
    echo "Next steps:"
    echo "  • Config dir:     /etc/supervisor/conf.d/"
    echo "  • Main config:    /etc/supervisor/supervisord.conf"
    echo "  • Add programs:   Create .ini files in conf.d/ (e.g. [program:myapp])"
    echo "  • Reload config:  sudo supervisorctl reload"
    echo "  • Status:         sudo supervisorctl status"
    echo "  • Web interface:  Enable [inet_http_server] in supervisord.conf if needed"
}

main() {
    detect_os
    install_supervisor
    start_service
}

main "$@"
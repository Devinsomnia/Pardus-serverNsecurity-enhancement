#!/bin/bash
# Install and Configure Rsync
# Support: Ubuntu/Debian/Pardus, CentOS/RHEL/Fedora/AlmaLinux, Alpine, Arch
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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
        VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi
}

install_rsync() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"
   
    # Check if rsync is already installed
    if command -v rsync >/dev/null 2>&1; then
        echo -e "${YELLOW}Rsync is already installed: $(rsync --version | head -n1)${NC}"
        return 0
    fi
    echo -e "${BLUE}Installing rsync...${NC}"
   
    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)  # ← Pardus + common Debian derivatives added
            sudo apt update
            sudo apt install -y rsync
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if [[ "$OS" == "fedora" || ("$OS" == "rhel" && "${VERSION%%.*}" -ge 8) || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
                sudo dnf install -y rsync
            else
                sudo yum install -y rsync
            fi
            ;;
        alpine)
            sudo apk add --no-cache rsync
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm rsync
            ;;
        *)
            echo -e "${RED}Unsupported system: $OS${NC}"
            echo "If this is Debian-based (like Pardus), try: sudo apt install rsync"
            exit 1
            ;;
    esac
   
    echo -e "${GREEN}Rsync installed successfully!${NC}"
}

configure_rsync() {
    echo -e "${GREEN}Configuring rsync...${NC}"
   
    RSYNCD_CONF="/etc/rsyncd.conf"
    RSYNCD_SECRETS="/etc/rsyncd.secrets"
    RSYNCD_MOTD="/etc/rsyncd.motd"
   
    # Create basic rsyncd.conf if it doesn't exist
    if [ ! -f "$RSYNCD_CONF" ]; then
        echo -e "${BLUE}Creating basic rsyncd.conf...${NC}"
        sudo bash -c "cat > $RSYNCD_CONF" <<EOF
# Rsync daemon configuration
uid = nobody
gid = nogroup
use chroot = yes
max connections = 4
pid file = /var/run/rsyncd.pid
log file = /var/log/rsyncd.log
exclude = lost+found/
transfer logging = yes
timeout = 600
ignore nonreadable = yes
dont compress = *.gz *.tgz *.zip *.z *.Z *.rpm *.deb *.bz2

# Example module (uncomment and customize)
#[backup]
#    path = /srv/backup
#    comment = Backup share
#    read only = false
#    auth users = backupuser
#    secrets file = $RSYNCD_SECRETS
EOF
        echo -e "${GREEN}Basic rsyncd.conf created at $RSYNCD_CONF${NC}"
    else
        echo -e "${YELLOW}rsyncd.conf already exists → skipping creation${NC}"
    fi
   
    # MOTD
    [ -f "$RSYNCD_MOTD" ] || echo "Welcome to rsync server" | sudo tee "$RSYNCD_MOTD" >/dev/null
   
    # Secrets file example (permissions 600)
    if [ ! -f "$RSYNCD_SECRETS" ]; then
        sudo bash -c "echo '# username:password' > $RSYNCD_SECRETS"
        sudo bash -c "echo '# Example: backupuser:MyStrongPass123' >> $RSYNCD_SECRETS"
        sudo chmod 600 "$RSYNCD_SECRETS"
        echo -e "${GREEN}Example secrets file created → edit $RSYNCD_SECRETS${NC}"
    fi
}

setup_systemd_service() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return 1
    fi

    echo -e "${BLUE}Setting up systemd rsync service...${NC}"
   
    local service_name="rsync"
    if systemctl list-unit-files | grep -q "rsyncd.service"; then
        service_name="rsyncd"
    fi

    if ! systemctl list-unit-files | grep -q "^$service_name\.service"; then
        local SERVICE_FILE="/etc/systemd/system/$service_name.service"
        sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=rsync daemon
After=network.target

[Service]
ExecStart=/usr/bin/rsync --daemon --no-detach --config=/etc/rsyncd.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}Created $service_name.service${NC}"
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    echo -e "${GREEN}rsync service enabled via systemd${NC}"
}

setup_xinetd_service() {
    echo -e "${BLUE}Falling back to xinetd setup...${NC}"
   
    # Install xinetd if missing
    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo apt install -y xinetd
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if [[ "$OS" == "fedora" || ("$OS" == "rhel" && "${VERSION%%.*}" -ge 8) ]]; then
                sudo dnf install -y xinetd
            else
                sudo yum install -y xinetd
            fi
            ;;
        alpine)
            sudo apk add --no-cache xinetd
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm xinetd
            ;;
    esac

    local XINETD_FILE="/etc/xinetd.d/rsync"
    if [ ! -f "$XINETD_FILE" ]; then
        sudo bash -c "cat > $XINETD_FILE" <<EOF
service rsync
{
    disable     = no
    socket_type = stream
    wait        = no
    user        = root
    server      = /usr/bin/rsync
    server_args = --daemon --config=/etc/rsyncd.conf
    log_on_failure += USERID
}
EOF
        echo -e "${GREEN}xinetd rsync config created${NC}"
    fi
}

start_service() {
    echo -e "${GREEN}Starting rsync daemon...${NC}"
   
    local started=false

    if command -v systemctl >/dev/null 2>&1; then
        local service_name="rsync"
        systemctl list-unit-files | grep -q "rsyncd.service" && service_name="rsyncd"

        if sudo systemctl start "$service_name" 2>/dev/null; then
            started=true
        else
            echo -e "${YELLOW}systemd start failed → trying xinetd fallback${NC}"
        fi
    fi

    if [ "$started" = false ]; then
        setup_xinetd_service
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl enable xinetd
            sudo systemctl restart xinetd
        elif command -v rc-service >/dev/null; then
            sudo rc-update add xinetd default
            sudo rc-service xinetd restart
        else
            echo -e "${YELLOW}Please start xinetd or rsync manually${NC}"
        fi
    fi
}

check_status() {
    echo -e "${BLUE}Checking rsync status...${NC}"
   
    if command -v rsync >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Rsync version: $(rsync --version | head -n1)${NC}"
    else
        echo -e "${RED}✗ Rsync not installed${NC}"
        return 1
    fi
   
    if pgrep -x rsync >/dev/null; then
        echo -e "${GREEN}✓ rsync process running${NC}"
    else
        echo -e "${YELLOW}! No rsync daemon process found${NC}"
    fi
   
    if command -v ss >/dev/null 2>&1 && ss -tlnp | grep -q ":873"; then
        echo -e "${GREEN}✓ Listening on TCP/873${NC}"
    elif command -v netstat >/dev/null 2>&1 && netstat -tlnp | grep -q ":873"; then
        echo -e "${GREEN}✓ Listening on TCP/873${NC}"
    else
        echo -e "${YELLOW}! Not listening on port 873 (daemon may not be active)${NC}"
    fi
}

main() {
    detect_os
    install_rsync
   
    if [ "$client_only" = false ]; then
        configure_rsync
        if ! setup_systemd_service; then
            setup_xinetd_service
        fi
        start_service
    fi
   
    check_status
   
    echo -e "${GREEN}Script finished.${NC}"
    if pgrep -x rsync >/dev/null; then
        echo "Next steps:"
        echo "  - Edit /etc/rsyncd.conf to add your modules"
        echo "  - Set real users/passwords in /etc/rsyncd.secrets"
        echo "  - Open firewall port: sudo ufw allow 873/tcp   (if using ufw)"
        echo "  - Test: rsync rsync://localhost/"
    fi
}

# Argument parsing (unchanged)
daemon_only=false
client_only=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --daemon-only) daemon_only=true; shift ;;
        --client-only) client_only=true; shift ;;
        --help|-h) show_usage; exit 0 ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_usage; exit 1 ;;
    esac
done

if [ "$daemon_only" = true ]; then
    client_only=false
fi

main "$@"
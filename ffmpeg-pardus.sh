#!/bin/bash
# Install FFmpeg (multimedia framework)
# Supports Ubuntu/Debian/Pardus/CentOS/RHEL/Fedora/Alpine/Arch/Manjaro
# Pardus 25 (Debian 13 trixie-based) fully supported via apt
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

OS=""
VERSION=""

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=${ID:-unknown}
        VERSION=${VERSION_ID:-unknown}
        if [ -n "$ID_LIKE" ]; then
            OS_LIKE=$ID_LIKE
        fi
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        OS_LIKE="rhel"
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi
}

install_ffmpeg() {
    echo -e "${GREEN}Detected system: $OS $VERSION${NC}"
    case "$OS" in
        ubuntu|debian|pardus|linuxmint|pop|neon|kali)
            sudo apt update
            sudo apt install -y ffmpeg
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if [[ "$OS" == "fedora" || ("$OS" == "rhel" && "${VERSION%%.*}" -ge 8) || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
                sudo dnf install -y epel-release
                sudo dnf install -y --nogpgcheck https://download1.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm
                sudo dnf install -y ffmpeg ffmpeg-devel
            else
                # Older RHEL/CentOS (e.g. 7)
                sudo yum install -y epel-release
                sudo yum install -y --nogpgcheck https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm
                sudo yum install -y ffmpeg ffmpeg-devel || {
                    echo -e "${YELLOW}Fallback to Nux Dextop repo...${NC}"
                    sudo rpm --import http://li.nux.ro/download/nux/RPM-GPG-KEY-nux.ro
                    sudo rpm -Uvh http://li.nux.ro/download/nux/dextop/el7/x86_64/nux-dextop-release-0-1.el7.nux.noarch.rpm
                    sudo yum install -y ffmpeg ffmpeg-devel
                }
            fi
            ;;
        alpine)
            sudo apk update
            sudo apk add ffmpeg
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm ffmpeg
            ;;
        *)
            echo -e "${RED}Unsupported system: $OS $VERSION${NC}"
            echo "If this is Pardus/Debian-based, try manually:"
            echo "  sudo apt update && sudo apt install ffmpeg"
            exit 1
            ;;
    esac
}

check_ffmpeg_install() {
    if command -v ffmpeg >/dev/null 2>&1; then
        local FF_VER
        FF_VER=$(ffmpeg -version 2>/dev/null | head -n 1 || echo "version unknown")
        echo -e "${GREEN}FFmpeg installed successfully!${NC}"
        echo "  → $FF_VER"
        echo "  → ffprobe: $(ffprobe -version 2>/dev/null | head -n 1 || echo 'not found')"
        echo ""
        echo "Quick test: ffmpeg -i sample.mp4 -f null -  # (replace with real file)"
    else
        echo -e "${RED}FFmpeg not found after installation.${NC}"
        echo "Check logs or try: sudo apt install ffmpeg (on Pardus/Debian)"
        exit 1
    fi
}

main() {
    detect_os
    install_ffmpeg
    check_ffmpeg_install
}

main "$@"
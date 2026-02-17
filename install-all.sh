```bash
#!/usr/bin/env bash
# install-all.sh – runs all Pardus enhancement scripts sequentially

set -euo pipefail

echo -e "\n\033[1;32m=== Starting Pardus Server & Security Enhancement ===\033[0m\n"

scripts=(
    "clamav-pardus.sh"
    "fail2ban-pardus.sh"
    "ffmpeg-pardus.sh"
    "pure-ftpd-pardus.sh"
    "rsync-pardus.sh"
    "supervisor-pardus.sh"
)

for script in "${scripts[@]}"; do
    if [[ -f "$script" ]]; then
        echo -e "\n\033[1;34mRunning → $script\033[0m"
        echo "----------------------------------------"
        sudo bash "./$script" || {
            echo -e "\033[1;31mError in $script – stopping.\033[0m"
            exit 1
        }
        echo -e "\033[1;32m→ $script finished successfully\033[0m"
        echo ""
        sleep 2   # small pause so user can read output
    else
        echo -e "\033[1;33mWarning: $script not found – skipping\033[0m"
    fi
done

echo -e "\n\033[1;32mAll scripts completed!\033[0m"
echo "Check individual tool statuses / logs if needed."
echo "Thank you for using Pardus-serverNsecurity-enhancement!"
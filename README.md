# Pardus-serverNsecurity-enhancement
Pardus-serverNsecurity-enhancement that solves mainly non-available operating systems issues. 

# Pardus Server & Security Enhancement

Collection of **Pardus-tailored installation scripts** for common server + security tools that are sometimes missing, outdated or tricky to configure on Pardus (especially Pardus 21/23/25 – Debian-based).

Currently includes:

- ClamAV (antivirus)
- Fail2Ban (intrusion prevention)
- FFmpeg (multimedia processing)
- Pure-FTPd (FTP server with virtual users)
- rsync (file synchronization)
- Supervisor (process control system)

All scripts are designed to be **idempotent** where possible and include color output + error handling.

## One-line installation (recommended)

This command downloads the repo temporarily and runs **all scripts one after another** (as root):

```bash
curl -fsSL https://raw.githubusercontent.com/Devinsomnia/Pardus-serverNsecurity-enhancement/main/install-all.sh | sudo bash
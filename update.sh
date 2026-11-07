#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL LINUX UPDATER
# Debian / Ubuntu / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/universal_update.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ROOT CHECK
if [[ $EUID -ne 0 ]]; then
    echo "Administrator privileges required."
    echo "Run: sudo bash Universal_Update.sh"
    exit 1
fi

# DISTRIBUTION DETECTION
if [[ ! -f /etc/os-release ]]; then
    echo "Cannot identify Linux distribution."
    exit 1
fi

source /etc/os-release

DISTRO="${ID,,}"
FAMILY="${ID_LIKE:-}"

echo "=========================================="
echo "       CYBERPATRIOT UNIVERSAL UPDATER"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo

log "Update started: $PRETTY_NAME"

# ==========================================
# DEBIAN / UBUNTU FAMILY
# ==========================================

if [[ "$DISTRO" == "debian" ||
      "$DISTRO" == "ubuntu" ||
      "$DISTRO" == "linuxmint" ||
      "$DISTRO" == "pop" ||
      "$FAMILY" == *debian* ]]; then

    echo "[INFO] Debian-based distribution detected."

    echo
    echo "[INFO] Refreshing package repositories..."

    if ! apt-get update; then
        log "APT repository update failed."
        exit 1
    fi

    echo
    echo "[INFO] Installing available updates..."

    if ! apt-get upgrade -y; then
        log "APT package upgrade failed."
        exit 1
    fi

    echo
    echo "[INFO] Installing automatic update manager..."

    if ! apt-get install -y unattended-upgrades; then
        log "Could not install unattended-upgrades."
        exit 1
    fi

    # Enable periodic package updates.
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Enable automatic update timers.
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now apt-daily.timer
        systemctl enable --now apt-daily-upgrade.timer
    fi

    log "APT updates completed."
    log "Automatic unattended updates configured."

# ==========================================
# FEDORA / RHEL FAMILY
# ==========================================

elif [[ "$DISTRO" == "fedora" ||
        "$DISTRO" == "rhel" ||
        "$DISTRO" == "rocky" ||
        "$DISTRO" == "almalinux" ||
        "$DISTRO" == "ol" ||
        "$FAMILY" == *rhel* ||
        "$FAMILY" == *fedora* ]]; then

    echo "[INFO] DNF-based distribution detected."

    if ! command -v dnf >/dev/null 2>&1; then
        echo "DNF package manager not found."
        exit 1
    fi

    echo
    echo "[INFO] Installing available updates..."

    if ! dnf upgrade -y; then
        log "DNF upgrade failed."
        exit 1
    fi

    echo
    echo "[INFO] Installing automatic update manager..."

    if ! dnf install -y dnf-automatic; then
        log "Could not install dnf-automatic."
        exit 1
    fi

    CONFIG="/etc/dnf/automatic.conf"

    # Configure automatic package installation.
    set_dnf_option() {
        local KEY="$1"
        local VALUE="$2"

        if grep -Eq "^[[:space:]#]*${KEY}[[:space:]]*=" "$CONFIG"; then
            sed -i -E \
                "s/^[[:space:]#]*${KEY}[[:space:]]*=.*/${KEY} = ${VALUE}/" \
                "$CONFIG"
        else
            echo "${KEY} = ${VALUE}" >> "$CONFIG"
        fi
    }

    set_dnf_option "upgrade_type" "default"
    set_dnf_option "apply_updates" "yes"

    if ! systemctl enable --now dnf-automatic.timer; then
        log "Could not enable DNF automatic update timer."
        exit 1
    fi

    log "DNF updates completed."
    log "Automatic package updates enabled."

# ==========================================
# UNSUPPORTED DISTRIBUTION
# ==========================================

else

    echo "Unsupported Linux distribution:"
    echo "$PRETTY_NAME"

    echo
    echo "Supported families:"
    echo "- Debian"
    echo "- Ubuntu"
    echo "- Linux Mint"
    echo "- Pop!_OS"
    echo "- Fedora"
    echo "- Rocky Linux"
    echo "- AlmaLinux"
    echo "- RHEL"

    log "Unsupported distribution: $DISTRO"

    exit 1

fi

# ==========================================
# REBOOT CHECK
# ==========================================

echo
echo "=========================================="
echo "             UPDATE SUMMARY"
echo "=========================================="

echo "Distribution: $PRETTY_NAME"
echo "Package updates: Completed"
echo "Automatic updates: Configured"
echo "OS release upgrade: Not requested"

if [[ -f /var/run/reboot-required ]]; then
    echo
    echo "[WARNING] System reboot recommended."
elif command -v needs-restarting >/dev/null 2>&1; then
    if needs-restarting -r >/dev/null 2>&1; then
        echo "Reboot status: No reboot indicated."
    else
        echo "[WARNING] System reboot recommended."
    fi
else
    echo "Reboot status: Not determined."
fi

echo
echo "Log file: $LOG_FILE"

log "Universal update process completed."

echo
read -rp "Press Enter to return to launcher..."

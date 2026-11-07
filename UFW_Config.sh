
#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL FIREWALL MANAGER
# Debian / Ubuntu / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================

# ==========================================
# DIRECTORY CONFIGURATION
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG_FILE="$LOG_DIR/firewall_config.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ==========================================
# ROOT CHECK
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "Administrator privileges required."
    echo "Run: sudo bash Firewall_Config.sh"
    exit 1
fi

# ==========================================
# DISTRIBUTION DETECTION
# ==========================================

if [[ ! -f /etc/os-release ]]; then
    echo "Cannot identify Linux distribution."
    exit 1
fi

source /etc/os-release

DISTRO="${ID,,}"
FAMILY="${ID_LIKE:-}"

# ==========================================
# FIREWALL BACKEND SELECTION
# ==========================================

if [[ "$DISTRO" == "ubuntu" ||
      "$DISTRO" == "debian" ||
      "$DISTRO" == "linuxmint" ||
      "$DISTRO" == "pop" ||
      "$FAMILY" == *debian* ]]; then

    FIREWALL="ufw"
    PACKAGE_MANAGER="apt"

elif [[ "$DISTRO" == "fedora" ||
        "$DISTRO" == "rhel" ||
        "$DISTRO" == "rocky" ||
        "$DISTRO" == "almalinux" ||
        "$DISTRO" == "ol" ||
        "$FAMILY" == *rhel* ||
        "$FAMILY" == *fedora* ]]; then

    FIREWALL="firewalld"
    PACKAGE_MANAGER="dnf"

elif [[ "$DISTRO" == "arch" ||
        "$DISTRO" == "manjaro" ||
        "$DISTRO" == "endeavouros" ||
        "$FAMILY" == *arch* ]]; then

    FIREWALL="firewalld"
    PACKAGE_MANAGER="pacman"

elif [[ "$DISTRO" == *opensuse* ||
        "$FAMILY" == *suse* ]]; then

    FIREWALL="firewalld"
    PACKAGE_MANAGER="zypper"

else
    echo "Unsupported distribution: $PRETTY_NAME"
    exit 1
fi

# ==========================================
# HEADER
# ==========================================

clear

echo "=========================================="
echo "       CYBERPATRIOT FIREWALL MANAGER"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo "Firewall:     $FIREWALL"
echo "=========================================="

log "Firewall configuration started: $PRETTY_NAME"

# ==========================================
# INSTALL FIREWALL IF NECESSARY
# ==========================================

if ! command -v "$FIREWALL" >/dev/null 2>&1; then

    echo
    echo "$FIREWALL is not installed."

    read -rp "Install $FIREWALL? (yes/no): " INSTALL

    if [[ "$INSTALL" != "yes" ]]; then
        log "Firewall installation declined."
        exit 0
    fi

    case "$PACKAGE_MANAGER" in

        apt)
            apt-get update &&
            apt-get install -y ufw
            ;;

        dnf)
            dnf install -y firewalld
            ;;

        pacman)
            pacman -S --needed firewalld
            ;;

        zypper)
            zypper --non-interactive install firewalld
            ;;

    esac

    if [[ $? -ne 0 ]]; then
        echo "Firewall installation failed."
        log "Firewall installation failed."
        exit 1
    fi
fi

# ==========================================
# BACKUP CONFIGURATION
# ==========================================

BACKUP="$BACKUP_DIR/firewall_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP"

if [[ "$FIREWALL" == "ufw" ]]; then

    if [[ -d /etc/ufw ]]; then
        cp -a /etc/ufw "$BACKUP/"
    fi

    if [[ -f /etc/default/ufw ]]; then
        cp -a /etc/default/ufw "$BACKUP/"
    fi

else

    if [[ -d /etc/firewalld ]]; then
        cp -a /etc/firewalld "$BACKUP/"
    fi

fi

log "Firewall backup created: $BACKUP"

# ==========================================
# UFW CONFIGURATION
# ==========================================

configure_ufw() {

    echo
    echo "=========================================="
    echo "          CURRENT UFW STATUS"
    echo "=========================================="

    ufw status verbose
    echo
    ufw status numbered

    echo
    echo "Existing firewall rules will be preserved."
    echo "Review existing ALLOW rules carefully."

    read -rp "Continue? (yes/no): " CONTINUE

    if [[ "$CONTINUE" != "yes" ]]; then
        log "UFW configuration cancelled."
        return
    fi

    # SSH DETECTION

    SSH_PORT=""

    if [[ -n "${SSH_CONNECTION:-}" ]]; then

        SSH_PORT=$(awk '{print $4}' <<< "$SSH_CONNECTION")

        echo
        echo "SSH connection detected."
        echo "Server port: $SSH_PORT"

        read -rp "Allow and rate-limit this SSH port? (yes/no): " SSH_ALLOW

    elif command -v ss >/dev/null 2>&1 &&
         ss -lntp 2>/dev/null | grep -q sshd; then

        echo
        echo "SSH service appears to be listening."

        read -rp "Allow and rate-limit SSH on port 22? (yes/no): " SSH_ALLOW

        [[ "$SSH_ALLOW" == "yes" ]] && SSH_PORT=22

    else

        SSH_ALLOW="no"
        echo "No SSH listener detected."

    fi

    if [[ "$SSH_ALLOW" == "yes" ]]; then

        if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] ||
           (( SSH_PORT < 1 || SSH_PORT > 65535 )); then

            echo "Invalid SSH port."
            return

        fi

    fi

    echo
    echo "=========================================="
    echo "          PROPOSED UFW POLICY"
    echo "=========================================="

    echo "Incoming: DENY"
    echo "Outgoing: ALLOW"
    echo "Routed:   DENY"
    echo "Logging:  ON"

    if [[ "$SSH_ALLOW" == "yes" ]]; then
        echo "SSH: Rate limited on port $SSH_PORT"
    else
        echo "SSH: No new allow rule"
    fi

    echo
    echo "WARNING: Existing allow rules remain."
    echo "This may affect network services."

    read -rp "Apply firewall defaults? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "UFW changes declined."
        return
    fi

    FAILED=0

    ufw default deny incoming || FAILED=1
    ufw default allow outgoing || FAILED=1
    ufw default deny routed || FAILED=1

    if [[ "$SSH_ALLOW" == "yes" ]]; then
        ufw limit "$SSH_PORT/tcp" || FAILED=1
    fi

    ufw logging on || FAILED=1

    if [[ "$FAILED" -ne 0 ]]; then
        echo "Firewall configuration encountered errors."
        log "UFW configuration failed."
        return
    fi

    echo
    read -rp "Enable UFW now? (yes/no): " ENABLE

    if [[ "$ENABLE" == "yes" ]]; then

        if ufw --force enable; then
            echo "UFW enabled successfully."
            log "UFW enabled."
        else
            echo "UFW activation failed."
            log "UFW activation failed."
            return
        fi

    else

        echo "UFW rules configured but not enabled."
        log "UFW activation deferred."

    fi

    echo
    ufw status verbose
}

# ==========================================
# FIREWALLD CONFIGURATION
# ==========================================

configure_firewalld() {

    echo
    echo "=========================================="
    echo "         CURRENT FIREWALLD STATUS"
    echo "=========================================="

    systemctl status firewalld --no-pager 2>/dev/null || true

    echo
    echo "Default zone:"
    firewall-cmd --get-default-zone

    echo
    echo "Active zones:"
    firewall-cmd --get-active-zones

    echo
    echo "Current firewall configuration:"

    firewall-cmd --list-all

    echo
    echo "Existing zones, services and rules will be preserved."
    echo "No firewall zone will be replaced."

    read -rp "Continue? (yes/no): " CONTINUE

    if [[ "$CONTINUE" != "yes" ]]; then
        log "Firewalld configuration cancelled."
        return
    fi

    # SSH PROTECTION

    echo
    echo "Does this machine need incoming SSH access?"
    read -rp "Allow the standard SSH service (port 22)? (yes/no): " SSH_ALLOW

    if [[ "$SSH_ALLOW" == "yes" ]]; then

        echo
        echo "SSH will be added to the current default zone."
        echo "This uses the standard SSH service definition."

        read -rp "Confirm SSH access? (yes/no): " SSH_CONFIRM

    else

        SSH_CONFIRM="no"

    fi

    echo
    echo "=========================================="
    echo "       PROPOSED FIREWALL POLICY"
    echo "=========================================="

    echo "Existing firewalld zone: preserved"
    echo "Existing allowed services: preserved"
    echo "Unsolicited incoming traffic: default zone policy"
    echo "Outgoing traffic: unchanged"
    echo "Existing forwarding policies: unchanged"

    if [[ "$SSH_CONFIRM" == "yes" ]]; then
        echo "SSH service: Allow port 22"
    else
        echo "SSH service: No new SSH rule"
    fi

    echo
    echo "WARNING: Firewall activation may interrupt"
    echo "incoming network services."

    read -rp "Apply this configuration? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "Firewalld changes declined."
        return
    fi

    if ! systemctl enable --now firewalld; then
        echo "Could not start firewalld."
        log "Firewalld activation failed."
        return
    fi

    if [[ "$SSH_CONFIRM" == "yes" ]]; then

        if ! firewall-cmd --add-service=ssh --permanent; then
            echo "Could not add SSH service."
            log "SSH service configuration failed."
            return
        fi

    fi

    if ! firewall-cmd --reload; then
        echo "Firewall reload failed."
        log "Firewalld reload failed."
        return
    fi

    echo
    echo "Firewalld is running."

    firewall-cmd --list-all

    log "Firewalld configuration completed."
}

# ==========================================
# MAIN FIREWALL MENU
# ==========================================

echo
echo "Detected firewall backend: $FIREWALL"

case "$FIREWALL" in

    ufw)
        configure_ufw
        ;;

    firewalld)
        configure_firewalld
        ;;

esac

# ==========================================
# FINAL STATUS
# ==========================================

echo
echo "=========================================="
echo "         FINAL FIREWALL STATUS"
echo "=========================================="

if [[ "$FIREWALL" == "ufw" ]]; then

    ufw status verbose

else

    firewall-cmd --state
    firewall-cmd --list-all

fi

echo
echo "Backup: $BACKUP"
echo "Log: $LOG_FILE"

log "Firewall management finished."

echo
read -rp "Press Enter to return to launcher..."

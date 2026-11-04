
#!/bin/bash

# ==========================================
# CYBERPATRIOT UFW FIREWALL CONFIGURATION
# Debian / Ubuntu / APT distributions
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG_FILE="$LOG_DIR/ufw_config.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ------------------------------------------
# ROOT CHECK
# ------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Administrator privileges are required."
    echo "Run through sudo:"
    echo "sudo bash UFW_Config.sh"
    exit 1
fi

# ------------------------------------------
# DISTRIBUTION CHECK
# ------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "Cannot identify Linux distribution."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" && "$ID" != "debian" &&
      "$ID" != "linuxmint" && "$ID" != "pop" &&
      " ${ID_LIKE:-} " != *" debian "* ]]; then
    echo "This script is designed for Debian-based distributions."
    exit 1
fi

# ------------------------------------------
# HEADER
# ------------------------------------------

clear

echo "=========================================="
echo "       CYBERPATRIOT UFW CONFIGURATION"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo

log "UFW configuration started on $PRETTY_NAME"

# ------------------------------------------
# CHECK INSTALLATION
# ------------------------------------------

if ! command -v ufw >/dev/null 2>&1; then

    echo "UFW is not installed."
    read -rp "Install UFW using APT? (yes/no): " INSTALL

    if [[ "$INSTALL" != "yes" ]]; then
        log "UFW installation declined."
        exit 0
    fi

    apt-get update &&
        apt-get install ufw || {
        echo "UFW installation failed."
        log "UFW installation failed."
        exit 1
    }
fi

# ------------------------------------------
# SHOW CURRENT RULES
# ------------------------------------------

echo
echo "=========================================="
echo "       CURRENT FIREWALL STATUS"
echo "=========================================="

ufw status verbose

echo
echo "Current numbered rules:"
ufw status numbered

echo
echo "WARNING:"
echo "Existing firewall rules will NOT be deleted."
echo "Review existing ALLOW rules before proceeding."
echo "Existing explicit allow rules can override"
echo "the intended default-deny incoming policy."

read -rp "Continue with firewall configuration? (yes/no): " CONTINUE

if [[ "$CONTINUE" != "yes" ]]; then
    log "Firewall configuration cancelled."
    exit 0
fi

# ------------------------------------------
# BACKUP
# ------------------------------------------

BACKUP="$BACKUP_DIR/ufw_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP"

if [[ -d /etc/ufw ]]; then
    cp -a /etc/ufw "$BACKUP/"
fi

ufw status verbose > "$BACKUP/status.txt" 2>&1

log "Firewall backup created: $BACKUP"

# ------------------------------------------
# SSH PROTECTION
# ------------------------------------------

SSH_PORT=""

if [[ -n "${SSH_CONNECTION:-}" ]]; then

    SSH_PORT=$(awk '{print $4}' <<< "$SSH_CONNECTION")

    echo
    echo "Active SSH connection detected."
    echo "Current SSH server port: $SSH_PORT"

    read -rp "Protect this SSH connection with a UFW rate-limit rule? (yes/no): " SSH_ALLOW

elif systemctl is-active --quiet ssh 2>/dev/null ||
     systemctl is-active --quiet sshd 2>/dev/null; then

    echo
    echo "SSH service appears to be running."

    read -rp "Allow SSH on the default port 22? (yes/no): " SSH_ALLOW

    if [[ "$SSH_ALLOW" == "yes" ]]; then
        SSH_PORT=22
    fi

else
    SSH_ALLOW="no"
    echo
    echo "No active SSH connection or running SSH service detected."
fi

if [[ "$SSH_ALLOW" == "yes" ]]; then

    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] ||
       (( SSH_PORT < 1 || SSH_PORT > 65535 )); then

        echo "Invalid SSH port."
        exit 1
    fi

fi

# ------------------------------------------
# APPLY FIREWALL DEFAULTS
# ------------------------------------------

echo
echo "=========================================="
echo "       PROPOSED FIREWALL POLICY"
echo "=========================================="

echo "Incoming: DENY"
echo "Outgoing: ALLOW"
echo "Routed:   DENY"
echo "Logging:  ON"

if [[ "$SSH_ALLOW" == "yes" ]]; then
    echo "SSH: Rate limited on TCP port $SSH_PORT"
else
    echo "SSH: No new SSH allow rule"
fi

echo
echo "WARNING: Enabling UFW may interrupt network"
echo "services that depend on incoming connections."

read -rp "Apply these firewall defaults? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    log "Firewall changes declined."
    exit 0
fi

# ------------------------------------------
# APPLY RULES
# ------------------------------------------

FAILED=0

ufw default deny incoming || FAILED=1
ufw default allow outgoing || FAILED=1
ufw default deny routed || FAILED=1

if [[ "$SSH_ALLOW" == "yes" ]]; then

    ufw limit "$SSH_PORT/tcp" || FAILED=1

fi

ufw logging on || FAILED=1

if [[ "$FAILED" -ne 0 ]]; then
    echo
    echo "One or more firewall rules failed."
    echo "Review UFW status before enabling."
    log "Firewall configuration encountered errors."
    exit 1
fi

# ------------------------------------------
# ENABLE FIREWALL
# ------------------------------------------

echo
echo "=========================================="
echo "       FIREWALL ACTIVATION"
echo "=========================================="

echo "Review the proposed configuration."
read -rp "Enable UFW now? (yes/no): " ENABLE

if [[ "$ENABLE" == "yes" ]]; then

    if ufw enable; then
        echo "UFW enabled successfully."
        log "UFW successfully enabled."
    else
        echo "UFW activation failed."
        log "UFW activation failed."
        exit 1
    fi

else
    echo "Rules configured but firewall not enabled."
    log "UFW activation deferred."
fi

# ------------------------------------------
# FINAL STATUS
# ------------------------------------------

echo
echo "=========================================="
echo "       FINAL FIREWALL STATUS"
echo "=========================================="

ufw status verbose

log "UFW configuration finished."

echo
echo "Log saved to:"
echo "$LOG_FILE"

echo
echo "Backup saved to:"
echo "$BACKUP"

echo
read -rp "Press Enter to return to launcher..."

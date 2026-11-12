
#!/bin/bash

# ==========================================
# CYBERPATRIOT SSH SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/ssh_audit.log"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

PASS=0
WARN=0
INFO=0

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

check() {
    local description="$1"
    local result="$2"

    case "$result" in
        PASS)
            ((PASS+=1))
            log "[PASS] $description"
            ;;
        WARNING)
            ((WARN+=1))
            log "[WARNING] $description"
            ;;
        INFO)
            ((INFO+=1))
            log "[INFO] $description"
            ;;
    esac
}

echo "=========================================="
echo "    CYBERPATRIOT SSH SECURITY AUDIT"
echo "=========================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Running as: $(whoami)"
echo

# ==========================================
# SERVICE DETECTION
# ==========================================

SERVICE=""

for s in ssh sshd; do
    if systemctl list-unit-files "${s}.service" 2>/dev/null |
        grep -q "${s}.service"; then
        SERVICE="$s"
        break
    fi
done

if [[ -z "$SERVICE" ]]; then
    echo "[WARNING] SSH service was not found."
    echo "OpenSSH server may not be installed."
    exit 1
fi

echo "Detected SSH service: $SERVICE"

if systemctl is-active --quiet "$SERVICE"; then
    check "SSH service is running" PASS
else
    check "SSH service is not running" WARNING
fi

# ==========================================
# SSH CONFIGURATION DETECTION
# ==========================================

CONFIG="/etc/ssh/sshd_config"

if [[ ! -f "$CONFIG" ]]; then
    echo "[ERROR] SSH server configuration not found."
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
    echo "[ERROR] sshd command not found."
    exit 1
fi

echo
echo "=========================================="
echo "       CONFIGURATION AUDIT"
echo "=========================================="

# Use sshd's effective configuration when possible.
EFFECTIVE=$(sshd -T 2>/dev/null || true)

if [[ -z "$EFFECTIVE" ]]; then
    check "Could not read effective SSH configuration" WARNING
else
    check "Effective SSH configuration readable" PASS
fi

get_setting() {
    local key="$1"

    echo "$EFFECTIVE" |
        awk -v key="$key" '$1 == key {print $2; exit}'
}

audit_setting() {
    local key="$1"
    local expected="$2"
    local actual

    actual="$(get_setting "$key")"

    if [[ "$actual" == "$expected" ]]; then
        check "$key is $expected" PASS
    else
        check "$key is $actual (recommended: $expected)" WARNING
    fi
}

audit_setting "permitemptypasswords" "no"
audit_setting "x11forwarding" "no"

# Root login requires consideration of competition
# requirements and administrative access.
ROOT_LOGIN="$(get_setting permitrootlogin)"

case "$ROOT_LOGIN" in
    no)
        check "Root SSH login disabled" PASS
        ;;
    prohibit-password)
        check "Root SSH login restricted to key authentication" PASS
        ;;
    yes)
        check "Root SSH login enabled" WARNING
        ;;
    *)
        check "Root login setting could not be determined" WARNING
        ;;
esac

# Password authentication is audited, not automatically
# disabled because it could lock out administrators.

PASSWORD_AUTH="$(get_setting passwordauthentication)"

case "$PASSWORD_AUTH" in
    no)
        check "Password authentication disabled" PASS
        ;;
    yes)
        check "Password authentication enabled" INFO
        ;;
    *)
        check "Password authentication setting unknown" WARNING
        ;;
esac

PROTOCOL="$(get_setting protocol)"

if [[ -z "$PROTOCOL" || "$PROTOCOL" == "2" ]]; then
    check "SSH protocol configuration" PASS
else
    check "Unexpected SSH protocol configuration: $PROTOCOL" WARNING
fi

# ==========================================
# FILE PERMISSION AUDIT
# ==========================================

echo
echo "=========================================="
echo "         FILE PERMISSION AUDIT"
echo "=========================================="

CONFIG_OWNER="$(stat -c '%U' "$CONFIG" 2>/dev/null)"
CONFIG_MODE="$(stat -c '%a' "$CONFIG" 2>/dev/null)"

if [[ "$CONFIG_OWNER" == "root" ]]; then
    check "SSH configuration owned by root" PASS
else
    check "SSH configuration not owned by root" WARNING
fi

if [[ "$CONFIG_MODE" =~ ^[0-7]+$ ]] &&
   (( (8#$CONFIG_MODE & 8#022) == 0 )); then
    check "SSH configuration not writable by group or others" PASS
else
    check "SSH configuration has unsafe write permissions" WARNING
fi

SSH_DIR_MODE="$(stat -c '%a' /etc/ssh 2>/dev/null)"

if [[ "$SSH_DIR_MODE" =~ ^[0-7]+$ ]] &&
   (( (8#$SSH_DIR_MODE & 8#022) == 0 )); then
    check "/etc/ssh directory permissions" PASS
else
    check "/etc/ssh directory permissions need review" WARNING
fi

# ==========================================
# AUTHORIZED KEYS AUDIT
# ==========================================

echo
echo "=========================================="
echo "        AUTHORIZED KEYS AUDIT"
echo "=========================================="

if find /root/.ssh -name authorized_keys -type f \
    -print -quit 2>/dev/null | grep -q .; then
    check "Root authorized_keys file exists" INFO
else
    check "No root authorized_keys file found" INFO
fi

# ==========================================
# AUDIT SUMMARY
# ==========================================

echo
echo "=========================================="
echo "             AUDIT SUMMARY"
echo "=========================================="

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Info:     $INFO"
echo "Log:      $LOG"

echo
read -rp "Would you like to review SSH hardening options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

# ==========================================
# INTERACTIVE HARDENING
# ==========================================

echo
echo "=========================================="
echo "       SSH HARDENING OPTIONS"
echo "=========================================="

echo "These options require careful consideration."
echo "Keep your current SSH session open."
echo

read -rp "Disable empty passwords? (Y/n): " EMPTY
read -rp "Disable X11 forwarding? (Y/n): " X11
read -rp "Disable root SSH login? (y/N): " ROOT
read -rp "Disable password authentication? (y/N): " PASSWORD

echo
echo "Requested changes:"
echo "Empty passwords: ${EMPTY:-Y}"
echo "X11 forwarding: ${X11:-Y}"
echo "Root login: ${ROOT:-N}"
echo "Password authentication: ${PASSWORD:-N}"

echo
read -rp "Apply these changes? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled. No changes made."
    exit 0
fi

# ==========================================
# BACKUP
# ==========================================

BACKUP="$CONFIG.cyberpatriot.backup.$(date +%Y%m%d%H%M%S)"

if ! cp -a "$CONFIG" "$BACKUP"; then
    echo "[ERROR] Could not back up SSH configuration."
    exit 1
fi

echo "Backup created: $BACKUP"

# ==========================================
# CONFIGURATION CHANGES
# ==========================================

# For safety, this script does not automatically
# overwrite existing SSH directives or Match blocks.
# Changes are applied through a dedicated drop-in
# only when the main configuration includes it.

DROPIN_DIR="/etc/ssh/sshd_config.d"
DROPIN="$DROPIN_DIR/99-cyberpatriot-hardening.conf"

if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*\.conf' "$CONFIG"; then
    echo
    echo "[WARNING] Main configuration does not include the standard drop-in directory."
    echo "No changes were applied."
    echo "Backup: $BACKUP"
    exit 0
fi

mkdir -p "$DROPIN_DIR"

DROPIN_BACKUP=""

if [[ -f "$DROPIN" ]]; then
    DROPIN_BACKUP="$DROPIN.backup.$(date +%Y%m%d%H%M%S)"
    cp -a "$DROPIN" "$DROPIN_BACKUP" || exit 1
fi

TEMP="$(mktemp)"

{
    echo "# CyberPatriot SSH hardening configuration"
    [[ "${EMPTY:-Y}" =~ ^[Yy]$ ]] && echo "PermitEmptyPasswords no"
    [[ "${X11:-Y}" =~ ^[Yy]$ ]] && echo "X11Forwarding no"
    [[ "${ROOT:-N}" =~ ^[Yy]$ ]] && echo "PermitRootLogin no"
    [[ "${PASSWORD:-N}" =~ ^[Yy]$ ]] && echo "PasswordAuthentication no"
} > "$TEMP"

install -o root -g root -m 600 "$TEMP" "$DROPIN"
rm -f "$TEMP"

# ==========================================
# CONFIGURATION VALIDATION
# ==========================================

echo
echo "Testing SSH configuration..."

if sshd -t; then
    echo "[PASS] SSH configuration syntax valid."
else
    echo "[ERROR] SSH configuration test failed."

    if [[ -n "$DROPIN_BACKUP" ]]; then
        cp -a "$DROPIN_BACKUP" "$DROPIN"
    else
        rm -f "$DROPIN"
    fi

    echo "Restored previous drop-in configuration."
    exit 1
fi

# ==========================================
# RELOAD SERVICE
# ==========================================

echo
echo "Reloading SSH service..."

if systemctl reload "$SERVICE"; then
    echo "[SUCCESS] SSH service reloaded."
    log "SSH hardening configuration applied successfully."
else
    echo "[WARNING] SSH reload failed."
    echo "Previous configuration backup: $BACKUP"
    log "SSH reload failed."
    exit 1
fi

# ==========================================
# FINAL VERIFICATION
# ==========================================

echo
echo "=========================================="
echo "       FINAL SSH VERIFICATION"
echo "=========================================="

if sshd -t; then
    echo "[PASS] SSH configuration remains valid."
else
    echo "[WARNING] SSH configuration verification failed."
fi

if systemctl is-active --quiet "$SERVICE"; then
    echo "[PASS] SSH service is active."
else
    echo "[WARNING] SSH service is not active."
fi

echo
echo "SSH security audit and hardening complete."
echo "Backup: $BACKUP"
echo "Log: $LOG"

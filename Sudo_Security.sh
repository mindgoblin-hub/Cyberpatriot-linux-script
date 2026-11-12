
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL SUDO SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/sudo_security.log"
BACKUP_DIR="$LOG_DIR/sudo_backups"

mkdir -p "$BACKUP_DIR"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

PASS=0
WARN=0
CRITICAL=0
INFO=0

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

check() {
    local LEVEL="$1"
    local MESSAGE="$2"

    case "$LEVEL" in
        PASS) ((PASS+=1)) ;;
        WARNING) ((WARN+=1)) ;;
        CRITICAL) ((CRITICAL+=1)) ;;
        INFO) ((INFO+=1)) ;;
    esac

    log "[$LEVEL] $MESSAGE"
}

# ==================================================
# BACKUP FUNCTION
# ==================================================

backup_file() {
    local FILE="$1"

    [[ -f "$FILE" ]] || return 1

    local NAME
    NAME="$(echo "$FILE" | sed 's#/#_#g')"

    cp -a "$FILE" \
        "$BACKUP_DIR/${NAME}.$(date +%Y%m%d_%H%M%S)"
}

# ==================================================
# HEADER
# ==================================================

echo "=============================================="
echo "        CYBERPATRIOT SUDO SECURITY AUDIT"
echo "=============================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"
echo

# ==================================================
# SUDO INSTALLATION AUDIT
# ==================================================

echo "[1] SUDO INSTALLATION"
echo "----------------------------------------------"

if command -v sudo >/dev/null 2>&1; then
    check PASS "sudo is installed."
    sudo --version | head -n 1
else
    check CRITICAL "sudo is not installed."
fi

echo

# ==================================================
# SUDO GROUP AUDIT
# ==================================================

echo "[2] ADMINISTRATIVE GROUP AUDIT"
echo "----------------------------------------------"

ADMIN_GROUPS=(
    sudo
    wheel
    admin
)

for GROUP in "${ADMIN_GROUPS[@]}"; do

    if getent group "$GROUP" >/dev/null 2>&1; then

        MEMBERS="$(getent group "$GROUP" | cut -d: -f4)"

        echo
        echo "Group: $GROUP"
        echo "Members: ${MEMBERS:-None}"

        check INFO "Administrative group $GROUP exists."

    fi

done

echo

# ==================================================
# UID 0 AUDIT
# ==================================================

echo "[3] UID 0 ACCOUNT AUDIT"
echo "----------------------------------------------"

UID_ZERO_USERS="$(awk -F: '$3 == 0 {print $1}' /etc/passwd)"

echo "$UID_ZERO_USERS"

UID_ZERO_COUNT="$(echo "$UID_ZERO_USERS" | grep -c . || true)"

if [[ "$UID_ZERO_COUNT" -eq 1 && "$UID_ZERO_USERS" == "root" ]]; then
    check PASS "Only root has UID 0."
else
    check CRITICAL "Additional UID 0 accounts detected."
fi

echo

# ==================================================
# SUDOERS FILE AUDIT
# ==================================================

echo "[4] SUDOERS CONFIGURATION"
echo "----------------------------------------------"

SUDOERS="/etc/sudoers"

if [[ -f "$SUDOERS" ]]; then

    stat -c '%A %U:%G %n' "$SUDOERS"

    OWNER="$(stat -c '%U' "$SUDOERS")"
    MODE="$(stat -c '%a' "$SUDOERS")"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "/etc/sudoers owned by root."
    else
        check CRITICAL "/etc/sudoers not owned by root."
    fi

    if [[ "$MODE" == "440" ]]; then
        check PASS "/etc/sudoers has permissions 440."
    else
        check WARNING "/etc/sudoers permissions are $MODE; review against policy."
    fi

    if visudo -c -f "$SUDOERS" >/dev/null 2>&1; then
        check PASS "Sudoers syntax is valid."
    else
        check CRITICAL "Sudoers syntax validation failed."
    fi

else
    check CRITICAL "/etc/sudoers is missing."
fi

echo

# ==================================================
# SUDOERS DIRECTORY AUDIT
# ==================================================

echo "[5] SUDOERS.D AUDIT"
echo "----------------------------------------------"

if [[ -d /etc/sudoers.d ]]; then

    find /etc/sudoers.d -maxdepth 1 -type f -print

    while IFS= read -r -d '' FILE; do

        echo
        echo "File: $FILE"

        OWNER="$(stat -c '%U' "$FILE")"
        MODE="$(stat -c '%a' "$FILE")"

        if [[ "$OWNER" == "root" ]]; then
            check PASS "$FILE owned by root."
        else
            check CRITICAL "$FILE owned by $OWNER."
        fi

        if [[ "$MODE" == "440" ]]; then
            check PASS "$FILE has permissions 440."
        else
            check WARNING "$FILE permissions are $MODE."
        fi

        if visudo -c -f "$FILE" >/dev/null 2>&1; then
            check PASS "$FILE syntax is valid."
        else
            check CRITICAL "$FILE contains invalid sudoers syntax."
        fi

    done < <(find /etc/sudoers.d -maxdepth 1 -type f -print0)

else
    check INFO "/etc/sudoers.d does not exist."
fi

echo

# ==================================================
# NOPASSWD AUDIT
# ==================================================

echo "[6] NOPASSWD CONFIGURATION"
echo "----------------------------------------------"

NOPASSWD_FILES=()

if [[ -f /etc/sudoers ]]; then
    NOPASSWD_FILES+=(/etc/sudoers)
fi

if [[ -d /etc/sudoers.d ]]; then

    while IFS= read -r -d '' FILE; do
        NOPASSWD_FILES+=("$FILE")
    done < <(find /etc/sudoers.d -maxdepth 1 -type f -print0)

fi

NOPASSWD_FOUND=0

for FILE in "${NOPASSWD_FILES[@]}"; do

    MATCHES="$(grep -nEi 'NOPASSWD' "$FILE" 2>/dev/null || true)"

    if [[ -n "$MATCHES" ]]; then

        echo
        echo "$FILE"
        echo "$MATCHES"

        ((NOPASSWD_FOUND+=1))

        check WARNING "NOPASSWD configuration found in $FILE."

    fi

done

if ((NOPASSWD_FOUND == 0)); then
    check PASS "No NOPASSWD directives found."
fi

echo

# ==================================================
# SUDO LOGGING AUDIT
# ==================================================

echo "[7] SUDO LOGGING AUDIT"
echo "----------------------------------------------"

if grep -RniE '^[[:space:]]*Defaults.*logfile=' \
    /etc/sudoers /etc/sudoers.d 2>/dev/null; then

    check PASS "Explicit sudo logfile configuration found."

else

    check INFO "No explicit sudo logfile directive found."
    echo "Sudo activity may still be recorded through system authentication logs."

fi

echo

# ==================================================
# SUDO PRIVILEGE AUDIT
# ==================================================

echo "[8] SUDO PRIVILEGE REVIEW"
echo "----------------------------------------------"

if command -v sudo >/dev/null 2>&1; then

    while IFS=: read -r USERNAME PASSWORD UID GID COMMENT HOME SHELL; do

        [[ -n "$USERNAME" ]] || continue

        PRIVILEGES="$(sudo -l -U "$USERNAME" 2>/dev/null || true)"

        if [[ -n "$PRIVILEGES" ]]; then

            if grep -qE 'ALL[[:space:]]*=[[:space:]]*\(ALL(:ALL)?\)[[:space:]]*ALL' \
                <<< "$PRIVILEGES"; then

                echo "Administrative privileges detected: $USERNAME"
                check INFO "$USERNAME has unrestricted sudo privileges."

            fi

        fi

    done < /etc/passwd

fi

echo

# ==================================================
# SUDO SECURE PATH AUDIT
# ==================================================

echo "[9] SUDO SECURE PATH AUDIT"
echo "----------------------------------------------"

if grep -RniE '^[[:space:]]*Defaults.*secure_path=' \
    /etc/sudoers /etc/sudoers.d 2>/dev/null; then

    check INFO "Explicit secure_path configuration found."

else

    check WARNING "No explicit secure_path configuration found."

fi

echo

# ==================================================
# SUDO VERSION AUDIT
# ==================================================

echo "[10] SUDO VERSION"
echo "----------------------------------------------"

if command -v sudo >/dev/null 2>&1; then

    sudo --version | head -n 3

    check INFO "Sudo version collected. Compare against supported security updates."

fi

echo

# ==================================================
# SUMMARY
# ==================================================

echo "=============================================="
echo "             AUDIT SUMMARY"
echo "=============================================="

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Critical: $CRITICAL"
echo "Info:     $INFO"

echo
echo "Log: $LOG"

log "Sudo audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE HARDENING
# ==================================================

echo
read -rp "Would you like to review sudo hardening options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "           SUDO SECURITY MENU"
echo "=============================================="
echo
echo "1. Review administrative group members."
echo "2. Validate sudoers configuration."
echo "3. Review NOPASSWD directives."
echo "4. Review sudo logging."
echo "5. Review sudo privileges for a user."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)
        for GROUP in "${ADMIN_GROUPS[@]}"; do
            getent group "$GROUP" 2>/dev/null || true
        done
        ;;

    2)
        visudo -c
        ;;

    3)
        grep -RniE 'NOPASSWD' \
            /etc/sudoers /etc/sudoers.d 2>/dev/null || \
            echo "No NOPASSWD directives found."
        ;;

    4)
        echo "Reviewing recent sudo activity..."

        if command -v journalctl >/dev/null 2>&1; then

            journalctl --since "24 hours ago" \
                --no-pager 2>/dev/null |
                grep -i sudo |
                tail -n 30 || true

        elif [[ -f /var/log/auth.log ]]; then

            grep -i sudo /var/log/auth.log | tail -n 30

        elif [[ -f /var/log/secure ]]; then

            grep -i sudo /var/log/secure | tail -n 30

        else

            echo "No standard sudo log source found."

        fi
        ;;

    5)
        read -rp "Enter username: " USERNAME

        if getent passwd "$USERNAME" >/dev/null 2>&1; then
            sudo -l -U "$USERNAME"
        else
            echo "User does not exist."
        fi
        ;;

    0)
        exit 0
        ;;

    *)
        echo "Invalid selection."
        exit 1
        ;;

esac

# ==================================================
# FINAL VERIFICATION
# ==================================================

echo
echo "=============================================="
echo "       FINAL SUDO VERIFICATION"
echo "=============================================="

if [[ -f /etc/sudoers ]]; then

    stat -c '%A %U:%G %n' /etc/sudoers

    if visudo -c >/dev/null 2>&1; then
        echo "[PASS] Sudoers configuration valid."
    else
        echo "[CRITICAL] Sudoers configuration invalid."
    fi

fi

echo
echo "Sudo security session completed."
echo "Log: $LOG"

log "Sudo security session completed."

exit 0

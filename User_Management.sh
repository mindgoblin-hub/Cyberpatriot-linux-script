
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL USER MANAGEMENT SECURITY
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

# ==================================================
# DIRECTORY AND LOGGING
# ==================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG="$LOG_DIR/user_management.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

PASS=0
WARN=0
CRITICAL=0
INFO=0

check() {
    local level="$1"
    local message="$2"

    case "$level" in
        PASS) ((PASS+=1)) ;;
        WARNING) ((WARN+=1)) ;;
        CRITICAL) ((CRITICAL+=1)) ;;
        INFO) ((INFO+=1)) ;;
    esac

    log "[$level] $message"
}

# ==================================================
# ROOT CHECK
# ==================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

# ==================================================
# DISTRIBUTION DETECTION
# ==================================================

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
else
    ID="unknown"
    PRETTY_NAME="Unknown Linux"
fi

echo "=============================================="
echo "     CYBERPATRIOT USER MANAGEMENT AUDIT"
echo "=============================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Current User: $(logname 2>/dev/null || echo Unknown)"
echo "=============================================="
echo

# ==================================================
# BACKUP FUNCTION
# ==================================================

backup_accounts() {

    BACKUP_DIR="$LOG_DIR/account_backups_$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$BACKUP_DIR"

    local failed=0

    for file in /etc/passwd /etc/shadow /etc/group /etc/gshadow; do
        if [[ -f "$file" ]]; then
            if ! cp -a "$file" "$BACKUP_DIR/"; then
                echo "ERROR: Could not back up $file"
                failed=1
            fi
        fi
    done

    if ((failed == 0)); then
        echo "Account backups created: $BACKUP_DIR"
        log "Account configuration backed up."
        return 0
    fi

    echo "Backup incomplete. No account changes should be made."
    log "ERROR: Account backup incomplete."
    return 1
}

# ==================================================
# ACCOUNT DISCOVERY
# ==================================================

echo "[1] USER ACCOUNT AUDIT"
echo "----------------------------------------------"

if [[ ! -r /etc/passwd ]]; then
    check CRITICAL "/etc/passwd is not readable."
    exit 1
fi

awk -F: '$3 >= 1000 && $3 != 65534 {
    printf "%-20s UID: %-8s HOME: %s\n", $1, $3, $6
}' /etc/passwd

echo

# ==================================================
# UID 0 AUDIT
# ==================================================

echo "[2] ROOT PRIVILEGE AUDIT"
echo "----------------------------------------------"

ROOT_USERS=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)

ROOT_COUNT=$(echo "$ROOT_USERS" | grep -c . || true)

if [[ "$ROOT_USERS" == "root" ]]; then
    check PASS "Only root has UID 0."
else
    check CRITICAL "Additional UID 0 accounts detected:"
    echo "$ROOT_USERS"
fi

echo

# ==================================================
# EMPTY PASSWORD AUDIT
# ==================================================

echo "[3] EMPTY PASSWORD AUDIT"
echo "----------------------------------------------"

if [[ -r /etc/shadow ]]; then

    EMPTY_USERS=$(awk -F: '
        $2 == "" {print $1}
    ' /etc/shadow)

    if [[ -z "$EMPTY_USERS" ]]; then
        check PASS "No empty password fields detected."
    else
        check CRITICAL "Accounts with empty password fields detected:"
        echo "$EMPTY_USERS"
    fi

else
    check WARNING "Cannot read /etc/shadow."
fi

echo

# ==================================================
# SUDO GROUP AUDIT
# ==================================================

echo "[4] ADMINISTRATIVE GROUP AUDIT"
echo "----------------------------------------------"

ADMIN_GROUPS=("sudo" "wheel" "admin")

for group in "${ADMIN_GROUPS[@]}"; do

    if getent group "$group" >/dev/null 2>&1; then

        MEMBERS=$(getent group "$group" | awk -F: '{print $4}')

        if [[ -n "$MEMBERS" ]]; then
            check INFO "Members of administrative group $group:"
            echo "$MEMBERS"
        else
            check PASS "No supplementary members in $group."
        fi
    fi

done

echo

# ==================================================
# LOGIN SHELL AUDIT
# ==================================================

echo "[5] LOGIN SHELL AUDIT"
echo "----------------------------------------------"

VALID_SHELLS=()

if [[ -r /etc/shells ]]; then
    while IFS= read -r shell; do
        [[ "$shell" == /* ]] && VALID_SHELLS+=("$shell")
    done < /etc/shells
fi

if ((${#VALID_SHELLS[@]} == 0)); then
    check WARNING "Could not identify valid login shells."
else

    while IFS=: read -r username _ uid gid comment home shell; do

        [[ "$uid" =~ ^[0-9]+$ ]] || continue

        if ((uid >= 1000 && uid != 65534)); then

            if [[ "$shell" == */nologin || "$shell" == */false ]]; then
                check INFO "$username has a non-login shell."
                continue
            fi

            VALID=0

            for allowed in "${VALID_SHELLS[@]}"; do
                [[ "$shell" == "$allowed" ]] && VALID=1
            done

            if ((VALID == 0)); then
                check WARNING "$username has an unusual login shell: $shell"
            fi
        fi

    done < /etc/passwd
fi

echo

# ==================================================
# PASSWORD AGING AUDIT
# ==================================================

echo "[6] PASSWORD AGING AUDIT"
echo "----------------------------------------------"

if command -v chage >/dev/null 2>&1; then

    while IFS=: read -r username _ uid gid comment home shell; do

        [[ "$uid" =~ ^[0-9]+$ ]] || continue

        if ((uid >= 1000 && uid != 65534)); then

            LAST_CHANGE=$(chage -l "$username" 2>/dev/null |
                awk -F: '/Last password change/ {
                    sub(/^[[:space:]]+/, "", $2); print $2
                }')

            EXPIRY=$(chage -l "$username" 2>/dev/null |
                awk -F: '/Password expires/ {
                    sub(/^[[:space:]]+/, "", $2); print $2
                }')

            INACTIVE=$(chage -l "$username" 2>/dev/null |
                awk -F: '/Account inactive/ {
                    sub(/^[[:space:]]+/, "", $2); print $2
                }')

            if [[ "$EXPIRY" == "never" ]]; then
                check WARNING "$username password does not expire."
            elif [[ -n "$EXPIRY" ]]; then
                check INFO "$username password expiration: $EXPIRY"
            fi

            if [[ "$INACTIVE" != "never" && -n "$INACTIVE" ]]; then
                check WARNING "$username has an inactivity expiration: $INACTIVE"
            fi

        fi

    done < /etc/passwd

else
    check WARNING "chage command is unavailable."
fi

echo

# ==================================================
# LOCKED ACCOUNT AUDIT
# ==================================================

echo "[7] ACCOUNT STATUS AUDIT"
echo "----------------------------------------------"

while IFS=: read -r username _ uid gid comment home shell; do

    [[ "$uid" =~ ^[0-9]+$ ]] || continue

    if ((uid >= 1000 && uid != 65534)); then

        STATUS=$(passwd -S "$username" 2>/dev/null |
            awk '{print $2}')

        case "$STATUS" in
            L)
                check INFO "$username has a locked password."
                ;;
            NP)
                check CRITICAL "$username has no password."
                ;;
            P)
                check PASS "$username has a password set."
                ;;
            *)
                check WARNING "Could not determine password status for $username."
                ;;
        esac
    fi

done < /etc/passwd

echo

# ==================================================
# INACTIVE ACCOUNT AUDIT
# ==================================================

echo "[8] INACTIVE ACCOUNT AUDIT"
echo "----------------------------------------------"

if command -v lastlog >/dev/null 2>&1; then
    lastlog 2>/dev/null | head -n 20
    check INFO "Last login information displayed (first 20 lines)."
else
    check INFO "lastlog command unavailable."
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
echo "Full report: $LOG"
echo "=============================================="

log "Audit finished. PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE HARDENING
# ==================================================

echo
read -rp "Would you like to review account remediation options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "       USER MANAGEMENT HARDENING"
echo "=============================================="

echo "Available remediation options:"
echo
echo "1. Lock an account."
echo "2. Unlock an account."
echo "3. Set a password for an account."
echo "4. Set password expiration policy."
echo "5. Review an account."
echo "0. Return without changes."
echo

read -rp "Select an option: " OPTION

if [[ "$OPTION" == "0" ]]; then
    exit 0
fi

# ==================================================
# ACCOUNT VALIDATION
# ==================================================

validate_user() {

    local username="$1"

    if [[ ! "$username" =~ ^[a-zA-Z0-9_.-]+[$]?$ ]]; then
        echo "Invalid username format."
        return 1
    fi

    if ! getent passwd "$username" >/dev/null 2>&1; then
        echo "User does not exist."
        return 1
    fi

    if [[ "$username" == "root" ]]; then
        echo "Direct changes to root are not allowed by this script."
        return 1
    fi

    return 0
}

# ==================================================
# BACKUP BEFORE CHANGES
# ==================================================

if ! backup_accounts; then
    exit 1
fi

# ==================================================
# REMEDIATION
# ==================================================

case "$OPTION" in

    1)
        read -rp "Enter account to lock: " USERNAME

        if validate_user "$USERNAME"; then

            echo
            echo "WARNING: Locking an account can affect:"
            echo "- SSH access"
            echo "- Scheduled tasks"
            echo "- Required applications"
            echo

            read -rp "Confirm locking $USERNAME? (y/n): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                if usermod -L "$USERNAME"; then
                    check PASS "Account $USERNAME locked."
                else
                    check CRITICAL "Failed to lock $USERNAME."
                fi
            fi
        fi
        ;;

    2)
        read -rp "Enter account to unlock: " USERNAME

        if validate_user "$USERNAME"; then

            echo "Only unlock accounts you have verified are authorized."

            read -rp "Confirm unlocking $USERNAME? (y/n): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                if usermod -U "$USERNAME"; then
                    check PASS "Account $USERNAME unlocked."
                else
                    check WARNING "Failed to unlock $USERNAME."
                fi
            fi
        fi
        ;;

    3)
        read -rp "Enter account to update: " USERNAME

        if validate_user "$USERNAME"; then
            echo "Use a strong, unique password."
            if passwd "$USERNAME"; then
                check PASS "Password updated for $USERNAME."
            else
                check WARNING "Password update failed."
            fi
        fi
        ;;

    4)
        read -rp "Enter account to update: " USERNAME

        if validate_user "$USERNAME"; then

            echo
            echo "Password aging settings:"
            echo "Maximum password age: 90 days"
            echo "Minimum password age: 1 day"
            echo "Warning period: 7 days"
            echo

            read -rp "Apply these settings to $USERNAME? (y/n): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then

                if chage -m 1 -M 90 -W 7 "$USERNAME"; then
                    check PASS "Password aging updated for $USERNAME."
                else
                    check WARNING "Could not update password aging."
                fi
            fi
        fi
        ;;

    5)
        read -rp "Enter account to review: " USERNAME

        if validate_user "$USERNAME"; then
            echo
            getent passwd "$USERNAME"
            echo
            passwd -S "$USERNAME"
            echo
            chage -l "$USERNAME" 2>/dev/null || true
            echo
            id "$USERNAME"
        fi
        ;;

    *)
        echo "Invalid option."
        exit 1
        ;;
esac

echo
echo "=============================================="
echo "       REMEDIATION COMPLETE"
echo "=============================================="

echo "Recheck account configurations before competition."
echo "Backup directory: ${BACKUP_DIR:-Not created}"
echo "Log: $LOG"

log "User management remediation session completed."

exit 0

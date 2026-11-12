
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL FILE PERMISSIONS AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/file_permissions.log"

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

echo "=============================================="
echo "   CYBERPATRIOT FILE PERMISSIONS AUDIT"
echo "=============================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo

# ==================================================
# BACKUP FUNCTION
# ==================================================

backup_file() {
    local file="$1"

    if [[ ! -e "$file" ]]; then
        return 1
    fi

    local backup_dir="$LOG_DIR/permission_backups"
    mkdir -p "$backup_dir"

    local backup_name
    backup_name="$(echo "$file" | sed 's#/#_#g')"

    cp -a "$file" "$backup_dir/${backup_name}.$(date +%Y%m%d_%H%M%S)"
}

# ==================================================
# FILE OWNERSHIP AND PERMISSION CHECK
# ==================================================

audit_file() {
    local file="$1"
    local expected_owner="${2:-root}"
    local expected_mode="${3:-}"

    if [[ ! -e "$file" ]]; then
        check INFO "File does not exist: $file"
        return
    fi

    local owner mode

    owner="$(stat -c '%U' "$file" 2>/dev/null)"
    mode="$(stat -c '%a' "$file" 2>/dev/null)"

    if [[ "$owner" == "$expected_owner" ]]; then
        check PASS "$file ownership is $expected_owner"
    else
        check CRITICAL "$file ownership is $owner (expected $expected_owner)"
    fi

    if [[ -n "$expected_mode" ]]; then
        if [[ "$mode" == "$expected_mode" ]]; then
            check PASS "$file permissions are $mode"
        else
            check WARNING "$file permissions are $mode (expected $expected_mode)"
        fi
    fi
}

# ==================================================
# CRITICAL SYSTEM FILES
# ==================================================

echo "[1] CRITICAL SYSTEM FILES"
echo "----------------------------------------------"

audit_file "/etc/passwd" root 644
audit_file "/etc/group" root 644
audit_file "/etc/shadow" root 640
audit_file "/etc/gshadow" root 640

if [[ -f /etc/sudoers ]]; then
    audit_file "/etc/sudoers" root 440
fi

if [[ -d /etc/sudoers.d ]]; then
    audit_file "/etc/sudoers.d" root 750
fi

echo

# ==================================================
# SSH PERMISSIONS
# ==================================================

echo "[2] SSH PERMISSIONS"
echo "----------------------------------------------"

if [[ -d /etc/ssh ]]; then

    audit_file "/etc/ssh" root

    if [[ -f /etc/ssh/sshd_config ]]; then
        audit_file "/etc/ssh/sshd_config" root
    fi

else
    check INFO "SSH configuration directory not found."
fi

echo

# ==================================================
# HOME DIRECTORY AUDIT
# ==================================================

echo "[3] USER HOME DIRECTORIES"
echo "----------------------------------------------"

while IFS=: read -r username password uid gid comment home shell; do

    [[ -n "$home" ]] || continue

    if [[ -d "$home" ]]; then

        owner="$(stat -c '%U' "$home" 2>/dev/null)"
        mode="$(stat -c '%a' "$home" 2>/dev/null)"

        if [[ "$owner" == "$username" ]]; then
            check PASS "$home owned by $username"
        else
            check WARNING "$home owned by $owner instead of $username"
        fi

        # World-writable home directories need review.
        if [[ "$mode" =~ ^[0-7]+$ ]] &&
           (( (8#$mode & 8#002) != 0 )); then
            check WARNING "$home is world-writable."
        fi

    fi

done < /etc/passwd

echo

# ==================================================
# WORLD-WRITABLE FILE AUDIT
# ==================================================

echo "[4] WORLD-WRITABLE FILES"
echo "----------------------------------------------"

echo "Searching important system locations..."

WW_COUNT=0

for directory in /etc /usr/local/bin /usr/local/sbin /opt; do

    [[ -d "$directory" ]] || continue

    while IFS= read -r -d '' file; do

        ((WW_COUNT+=1))

        check WARNING "World-writable file or directory: $file"

        if ((WW_COUNT >= 100)); then
            check INFO "World-writable scan limited to first 100 findings."
            break
        fi

    done < <(find "$directory" -xdev \
        -perm -0002 -print0 2>/dev/null)

    ((WW_COUNT >= 100)) && break

done

if ((WW_COUNT == 0)); then
    check PASS "No world-writable objects found in scanned locations."
fi

echo

# ==================================================
# SUID / SGID AUDIT
# ==================================================

echo "[5] SUID / SGID EXECUTABLE AUDIT"
echo "----------------------------------------------"

SUID_COUNT=0
SGID_COUNT=0

for directory in /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /bin /sbin; do

    [[ -d "$directory" ]] || continue

    while IFS= read -r -d '' file; do

        ((SUID_COUNT+=1))
        check INFO "SUID file: $file"

    done < <(find "$directory" -xdev -type f -perm -4000 -print0 2>/dev/null)

    while IFS= read -r -d '' file; do

        ((SGID_COUNT+=1))
        check INFO "SGID file: $file"

    done < <(find "$directory" -xdev -type f -perm -2000 -print0 2>/dev/null)

done

echo "SUID files found: $SUID_COUNT"
echo "SGID files found: $SGID_COUNT"

if ((SUID_COUNT == 0 && SGID_COUNT == 0)); then
    check INFO "No SUID or SGID files found."
fi

echo

# ==================================================
# SYSTEM DIRECTORY OWNERSHIP
# ==================================================

echo "[6] SYSTEM DIRECTORY OWNERSHIP"
echo "----------------------------------------------"

for directory in /etc /usr /bin /sbin /usr/bin /usr/sbin; do

    [[ -d "$directory" ]] || continue

    owner="$(stat -c '%U' "$directory" 2>/dev/null)"

    if [[ "$owner" == "root" ]]; then
        check PASS "$directory is owned by root."
    else
        check CRITICAL "$directory is owned by $owner."
    fi

done

echo

# ==================================================
# IMPORTANT CONFIGURATION AUDIT
# ==================================================

echo "[7] IMPORTANT CONFIGURATION FILES"
echo "----------------------------------------------"

for file in /etc/hosts /etc/hostname /etc/fstab /etc/crontab; do

    [[ -f "$file" ]] || continue

    owner="$(stat -c '%U' "$file" 2>/dev/null)"

    if [[ "$owner" == "root" ]]; then
        check PASS "$file owned by root."
    else
        check WARNING "$file owned by $owner."
    fi

done

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

log "Audit complete: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE REMEDIATION
# ==================================================

echo
read -rp "Would you like to review permission remediation? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "       PERMISSION HARDENING MENU"
echo "=============================================="
echo
echo "1. Repair /etc/passwd permissions."
echo "2. Repair /etc/group permissions."
echo "3. Repair /etc/shadow permissions."
echo "4. Repair /etc/gshadow permissions."
echo "5. Repair /etc/sudoers permissions."
echo "6. Repair SSH configuration permissions."
echo "7. Repair a specific file."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)
        TARGET="/etc/passwd"
        MODE="644"
        ;;

    2)
        TARGET="/etc/group"
        MODE="644"
        ;;

    3)
        TARGET="/etc/shadow"
        MODE="640"
        ;;

    4)
        TARGET="/etc/gshadow"
        MODE="640"
        ;;

    5)
        TARGET="/etc/sudoers"
        MODE="440"
        ;;

    6)
        TARGET="/etc/ssh/sshd_config"
        MODE="600"
        ;;

    7)
        read -rp "Enter full path to file: " TARGET

        if [[ "$TARGET" != /* || ! -f "$TARGET" ]]; then
            echo "Invalid file path."
            exit 1
        fi

        read -rp "Enter desired octal permissions (example 600): " MODE

        if [[ ! "$MODE" =~ ^[0-7]{3,4}$ ]]; then
            echo "Invalid permission format."
            exit 1
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

if [[ ! -f "$TARGET" ]]; then
    echo "Target file does not exist."
    exit 1
fi

echo
echo "Target: $TARGET"
echo "Requested permissions: $MODE"
echo

read -rp "Apply this permission change? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

if ! backup_file "$TARGET"; then
    echo "ERROR: Backup failed. No changes made."
    exit 1
fi

if chmod "$MODE" "$TARGET"; then

    if [[ "$(stat -c '%a' "$TARGET")" == "$MODE" ]]; then
        check PASS "Permissions successfully updated on $TARGET."
    else
        check WARNING "Permission verification failed."
        exit 1
    fi

else
    check CRITICAL "Could not change permissions on $TARGET."
    exit 1
fi

echo
echo "=============================================="
echo "       REMEDIATION COMPLETE"
echo "=============================================="

echo "Updated file: $TARGET"
echo "Permissions: $MODE"
echo "Backup: $LOG_DIR/permission_backups"
echo "Log: $LOG"

log "Permission remediation completed."

exit 0

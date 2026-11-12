
#!/bin/bash

# ==========================================================
# CYBERPATRIOT UNIVERSAL SYSTEM INTEGRITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$LOG_DIR/integrity_backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG="$LOG_DIR/system_integrity.log"
REPORT="$LOG_DIR/system_integrity_$(date +%Y%m%d_%H%M%S).txt"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

PASS=0
WARN=0
CRITICAL=0
INFO=0

# ==========================================================
# LOGGING
# ==========================================================

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

check() {
    case "$1" in
        PASS) ((PASS+=1)) ;;
        WARNING) ((WARN+=1)) ;;
        CRITICAL) ((CRITICAL+=1)) ;;
        INFO) ((INFO+=1)) ;;
    esac

    log "[$1] $2"
}

section() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

# ==========================================================
# HEADER
# ==========================================================

clear

echo "=================================================="
echo "       CYBERPATRIOT SYSTEM INTEGRITY AUDIT"
echo "=================================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"

# ==========================================================
# CRITICAL SYSTEM FILE AUDIT
# ==========================================================

section "[1] CRITICAL SYSTEM FILES"

CRITICAL_FILES=(
    /etc/passwd
    /etc/shadow
    /etc/group
    /etc/gshadow
    /etc/sudoers
    /etc/ssh/sshd_config
    /etc/fstab
    /etc/hosts
    /etc/hostname
    /etc/crontab
    /etc/login.defs
)

for FILE in "${CRITICAL_FILES[@]}"; do

    [[ -e "$FILE" ]] || continue

    echo
    stat -c '%A %a %U:%G %n' "$FILE"

    OWNER="$(stat -c '%U' "$FILE")"
    MODE="$(stat -c '%a' "$FILE")"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "$FILE is owned by root."
    else
        check WARNING "$FILE is not owned by root."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) != 0 )); then

        check WARNING "$FILE is group/other writable."

    else

        check PASS "$FILE is not group/other writable."

    fi

done

# ==========================================================
# SYSTEM BINARY AUDIT
# ==========================================================

section "[2] SYSTEM BINARY AUDIT"

SYSTEM_BINARIES=(
    /bin/bash
    /bin/sh
    /usr/bin/sudo
    /usr/bin/passwd
    /usr/bin/su
    /usr/bin/ssh
    /usr/bin/sshd
    /usr/bin/systemctl
    /usr/bin/login
    /usr/bin/mount
    /usr/bin/umount
)

for FILE in "${SYSTEM_BINARIES[@]}"; do

    [[ -e "$FILE" ]] || continue

    echo
    stat -c '%A %a %U:%G %n' "$FILE"

    OWNER="$(stat -c '%U' "$FILE")"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "System binary owned by root: $FILE"
    else
        check WARNING "System binary not owned by root: $FILE"
    fi

done

# ==========================================================
# SUID / SGID AUDIT
# ==========================================================

section "[3] SUID / SGID FILE AUDIT"

echo "Searching common system directories."

SUID_REPORT="$LOG_DIR/suid_inventory_$(date +%Y%m%d_%H%M%S).txt"

find /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin \
    -xdev -type f \( -perm -4000 -o -perm -2000 \) \
    -print 2>/dev/null | sort -u > "$SUID_REPORT"

while IFS= read -r FILE; do

    [[ -n "$FILE" ]] || continue

    stat -c '%A %U:%G %n' "$FILE"

    OWNER="$(stat -c '%U' "$FILE")"

    if [[ "$OWNER" != "root" ]]; then
        check WARNING "SUID/SGID file not owned by root: $FILE"
    else
        check INFO "SUID/SGID file found: $FILE"
    fi

done < "$SUID_REPORT"

echo
echo "SUID/SGID inventory: $SUID_REPORT"

# ==========================================================
# WORLD WRITABLE AUDIT
# ==========================================================

section "[4] WORLD-WRITABLE SYSTEM FILES"

WORLD_REPORT="$LOG_DIR/world_writable_$(date +%Y%m%d_%H%M%S).txt"

find /etc /usr/local /opt \
    -xdev -type f -perm -0002 \
    -print 2>/dev/null | sort -u > "$WORLD_REPORT"

if [[ -s "$WORLD_REPORT" ]]; then

    cat "$WORLD_REPORT"

    check WARNING "World-writable files detected."

else

    check PASS "No world-writable files found in audited directories."

fi

# ==========================================================
# ROOT OWNERSHIP AUDIT
# ==========================================================

section "[5] ROOT OWNERSHIP AUDIT"

for DIR in /etc /root /usr/local; do

    [[ -d "$DIR" ]] || continue

    echo
    echo "Checking: $DIR"

    NONROOT_COUNT="$(find "$DIR" -xdev -type f ! -user root \
        2>/dev/null | wc -l)"

    echo "Files not owned by root: $NONROOT_COUNT"

    if (( NONROOT_COUNT > 0 )); then
        check INFO "Non-root-owned files found under $DIR. Review expected ownership."
    else
        check INFO "No non-root-owned regular files found under $DIR."
    fi

done

# ==========================================================
# TEMPORARY DIRECTORY AUDIT
# ==========================================================

section "[6] TEMPORARY DIRECTORY AUDIT"

for DIR in /tmp /var/tmp /dev/shm; do

    [[ -d "$DIR" ]] || continue

    echo
    echo "Directory: $DIR"

    stat -c '%A %a %U:%G %n' "$DIR"

    MODE="$(stat -c '%a' "$DIR")"

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#1000) != 0 )); then

        check PASS "$DIR has the sticky bit set."

    else

        check WARNING "$DIR does not have the sticky bit set."

    fi

    echo "Recently modified files:"

    find "$DIR" -xdev -type f -mmin -1440 \
        -printf '%TY-%Tm-%Td %TH:%TM %u %p\n' \
        2>/dev/null | head -n 30

done

# ==========================================================
# CONFIGURATION FILE PERMISSIONS
# ==========================================================

section "[7] CONFIGURATION DIRECTORY AUDIT"

CONFIG_DIRS=(
    /etc/ssh
    /etc/sudoers.d
    /etc/security
    /etc/pam.d
    /etc/cron.d
    /etc/systemd/system
)

for DIR in "${CONFIG_DIRS[@]}"; do

    [[ -d "$DIR" ]] || continue

    echo
    echo "Directory: $DIR"

    stat -c '%A %a %U:%G %n' "$DIR"

    find "$DIR" -maxdepth 1 -type f \
        -perm -0002 -print 2>/dev/null |
        while IFS= read -r FILE; do
            echo "[WARNING] World-writable: $FILE"
        done

    check INFO "Configuration directory reviewed: $DIR"

done

# ==========================================================
# PACKAGE INTEGRITY AUDIT
# ==========================================================

section "[8] PACKAGE INTEGRITY AUDIT"

if command -v dpkg >/dev/null 2>&1; then

    echo "Running Debian package verification."

    dpkg --verify 2>&1 | tee "$LOG_DIR/dpkg_verify_$(date +%Y%m%d_%H%M%S).txt"

    check INFO "Debian package verification completed. Review reported differences."

elif command -v rpm >/dev/null 2>&1; then

    echo "Running RPM package verification."

    echo "Note: Full RPM verification can take time."

    rpm -Va 2>&1 | tee "$LOG_DIR/rpm_verify_$(date +%Y%m%d_%H%M%S).txt"

    check INFO "RPM package verification completed. Review reported differences."

elif command -v pacman >/dev/null 2>&1; then

    echo "Running Arch package database verification."

    pacman -Qk 2>&1 | tee "$LOG_DIR/pacman_verify_$(date +%Y%m%d_%H%M%S).txt"

    check INFO "Pacman package verification completed."

else

    check WARNING "No supported package verification tool found."

fi

# ==========================================================
# INTEGRITY TOOL DETECTION
# ==========================================================

section "[9] SYSTEM INTEGRITY TOOLS"

TOOLS=(
    aide
    debsums
    rkhunter
    chkrootkit
    tripwire
    lynis
)

for TOOL in "${TOOLS[@]}"; do

    if command -v "$TOOL" >/dev/null 2>&1; then

        echo "[INSTALLED] $TOOL"

        check INFO "Integrity tool available: $TOOL"

    else

        echo "[NOT FOUND] $TOOL"

    fi

done

# ==========================================================
# FILESYSTEM AUDIT
# ==========================================================

section "[10] FILESYSTEM AUDIT"

if command -v findmnt >/dev/null 2>&1; then

    findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS

    echo
    echo "Reviewing mounted filesystems."

    check INFO "Filesystem mount configuration reviewed."

else

    check WARNING "findmnt unavailable."

fi

# ==========================================================
# SYSTEM FILE HASH INVENTORY
# ==========================================================

section "[11] SYSTEM BINARY HASH INVENTORY"

HASH_REPORT="$LOG_DIR/system_hashes_$(date +%Y%m%d_%H%M%S).txt"

for FILE in \
    /bin/bash \
    /usr/bin/sudo \
    /usr/bin/passwd \
    /usr/bin/su \
    /usr/bin/ssh \
    /usr/bin/systemctl
do

    [[ -f "$FILE" ]] || continue

    sha256sum "$FILE" >> "$HASH_REPORT" 2>/dev/null

done

if [[ -s "$HASH_REPORT" ]]; then

    cat "$HASH_REPORT"

    check INFO "System binary SHA256 inventory generated."

fi

# ==========================================================
# REPORT GENERATION
# ==========================================================

section "[12] GENERATING REPORT"

{
    echo "CYBERPATRIOT SYSTEM INTEGRITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Date: $(date)"

    echo
    echo "CRITICAL FILE PERMISSIONS"

    for FILE in "${CRITICAL_FILES[@]}"; do
        [[ -e "$FILE" ]] &&
            stat -c '%A %a %U:%G %n' "$FILE"
    done

    echo
    echo "SUID/SGID INVENTORY"

    cat "$SUID_REPORT" 2>/dev/null || true

    echo
    echo "WORLD WRITABLE FILES"

    cat "$WORLD_REPORT" 2>/dev/null || true

    echo
    echo "SYSTEM HASHES"

    cat "$HASH_REPORT" 2>/dev/null || true

    echo
    echo "FILESYSTEMS"

    findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true

    echo
    echo "AUDIT LOG"

    cat "$LOG"

} > "$REPORT"

check PASS "System integrity report generated."

# ==========================================================
# AUDIT SUMMARY
# ==========================================================

section "[13] AUDIT SUMMARY"

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Critical: $CRITICAL"
echo "Info:     $INFO"

echo
echo "Log: $LOG"
echo "Report: $REPORT"

log "System integrity audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==========================================================
# INTERACTIVE MENU
# ==========================================================

section "[14] SYSTEM INTEGRITY MENU"

echo "1. Review critical system files."
echo "2. Review SUID/SGID inventory."
echo "3. Review world-writable files."
echo "4. Review root ownership findings."
echo "5. Review temporary directories."
echo "6. Review package verification results."
echo "7. Review system hashes."
echo "8. View complete audit report."
echo "9. Back up integrity reports."
echo "0. Exit."

echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)

        for FILE in "${CRITICAL_FILES[@]}"; do
            [[ -e "$FILE" ]] &&
                stat -c '%A %a %U:%G %n' "$FILE"
        done

        ;;

    2)

        cat "$SUID_REPORT"

        ;;

    3)

        cat "$WORLD_REPORT"

        ;;

    4)

        for DIR in /etc /root /usr/local; do

            [[ -d "$DIR" ]] || continue

            find "$DIR" -xdev -type f ! -user root \
                -printf '%u %g %p\n' 2>/dev/null |
                head -n 50

        done

        ;;

    5)

        for DIR in /tmp /var/tmp /dev/shm; do

            [[ -d "$DIR" ]] || continue

            stat -c '%A %a %U:%G %n' "$DIR"

        done

        ;;

    6)

        ls -lt "$LOG_DIR"/*verify* 2>/dev/null ||
            echo "No package verification reports found."

        ;;

    7)

        cat "$HASH_REPORT" 2>/dev/null ||
            echo "No hash inventory found."

        ;;

    8)

        cat "$REPORT"

        ;;

    9)

        tar -czf "$BACKUP_DIR/integrity_reports_$(date +%Y%m%d_%H%M%S).tar.gz" \
            -C "$LOG_DIR" \
            "$(basename "$REPORT")" \
            "$(basename "$LOG")" \
            "$(basename "$SUID_REPORT")" \
            "$(basename "$WORLD_REPORT")"

        echo "Integrity reports backed up."

        ;;

    0)

        echo "Exiting."
        exit 0

        ;;

    *)

        echo "Invalid selection."
        exit 1

        ;;

esac

# ==========================================================
# FINISH
# ==========================================================

echo
echo "=================================================="
echo "       SYSTEM INTEGRITY AUDIT COMPLETED"
echo "=================================================="

echo "Log: $LOG"
echo "Report: $REPORT"

log "System integrity session completed."

exit 0

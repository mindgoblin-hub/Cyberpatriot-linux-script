
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL BOOT SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG="$LOG_DIR/boot_security.log"
REPORT="$LOG_DIR/boot_security_report_$(date +%Y%m%d_%H%M%S).txt"
BACKUP_DIR="$LOG_DIR/boot_backups"

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
echo "        CYBERPATRIOT BOOT SECURITY AUDIT"
echo "=============================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Date: $(date)"
echo

# ==================================================
# BOOT MODE DETECTION
# ==================================================

echo "[1] BOOT MODE"
echo "----------------------------------------------"

if [[ -d /sys/firmware/efi ]]; then

    echo "Boot mode: UEFI"
    check PASS "System booted using UEFI."

else

    echo "Boot mode: Legacy BIOS"
    check INFO "System booted using Legacy BIOS."

fi

echo

# ==================================================
# SECURE BOOT AUDIT
# ==================================================

echo "[2] SECURE BOOT"
echo "----------------------------------------------"

if command -v mokutil >/dev/null 2>&1; then

    SECURE_BOOT="$(mokutil --sb-state 2>/dev/null || true)"

    echo "$SECURE_BOOT"

    if grep -qi "SecureBoot enabled" <<< "$SECURE_BOOT"; then
        check PASS "Secure Boot is enabled."
    elif grep -qi "SecureBoot disabled" <<< "$SECURE_BOOT"; then
        check WARNING "Secure Boot is disabled."
    else
        check INFO "Secure Boot status could not be determined."
    fi

elif [[ -d /sys/firmware/efi/efivars ]]; then

    echo "mokutil unavailable."
    check INFO "Install mokutil to inspect Secure Boot state."

else

    check INFO "Secure Boot inspection unavailable in Legacy BIOS mode."

fi

echo

# ==================================================
# GRUB DETECTION
# ==================================================

echo "[3] GRUB BOOTLOADER DETECTION"
echo "----------------------------------------------"

GRUB_FILES=(
    /etc/default/grub
    /boot/grub/grub.cfg
    /boot/grub2/grub.cfg
    /boot/grub/grubenv
)

GRUB_FOUND=0

for FILE in "${GRUB_FILES[@]}"; do

    if [[ -f "$FILE" ]]; then

        echo "Found: $FILE"
        ((GRUB_FOUND+=1))

    fi

done

if ((GRUB_FOUND > 0)); then
    check PASS "GRUB configuration files detected."
else
    check INFO "No standard GRUB configuration detected."
fi

echo

# ==================================================
# GRUB CONFIGURATION PERMISSIONS
# ==================================================

echo "[4] GRUB PERMISSIONS"
echo "----------------------------------------------"

for FILE in "${GRUB_FILES[@]}"; do

    [[ -f "$FILE" ]] || continue

    OWNER="$(stat -c '%U' "$FILE")"
    MODE="$(stat -c '%a' "$FILE")"

    echo
    stat -c '%A %U:%G %n' "$FILE"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "$FILE owned by root."
    else
        check WARNING "$FILE owned by $OWNER."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "$FILE not writable by group or others."
    else
        check CRITICAL "$FILE has unsafe write permissions."
    fi

done

echo

# ==================================================
# GRUB PASSWORD AUDIT
# ==================================================

echo "[5] GRUB PASSWORD PROTECTION"
echo "----------------------------------------------"

GRUB_PASSWORD_FOUND=0

for FILE in /etc/grub.d/*; do

    [[ -f "$FILE" ]] || continue

    if grep -qE '^[[:space:]]*(password|password_pbkdf2)[[:space:]]' \
        "$FILE" 2>/dev/null; then

        echo "GRUB password directive found in: $FILE"
        ((GRUB_PASSWORD_FOUND+=1))

    fi

done

if ((GRUB_PASSWORD_FOUND > 0)); then

    check INFO "GRUB password configuration appears present."
    echo "Verify that the password is securely configured."

else

    check WARNING "No GRUB password directive detected."

fi

echo

# ==================================================
# KERNEL BOOT PARAMETERS
# ==================================================

echo "[6] KERNEL BOOT PARAMETERS"
echo "----------------------------------------------"

echo "Current kernel command line:"
cat /proc/cmdline

echo

if grep -qw "init=/bin/bash" /proc/cmdline; then
    check CRITICAL "Unexpected init=/bin/bash boot parameter detected."
else
    check PASS "No init=/bin/bash parameter detected."
fi

if grep -qw "single" /proc/cmdline; then
    check WARNING "Single-user boot parameter detected."
fi

if grep -qw "systemd.unit=rescue.target" /proc/cmdline; then
    check INFO "System is currently using rescue.target."
fi

echo

# ==================================================
# BOOT DIRECTORY AUDIT
# ==================================================

echo "[7] BOOT DIRECTORY AUDIT"
echo "----------------------------------------------"

for DIR in /boot /boot/grub /boot/grub2; do

    [[ -d "$DIR" ]] || continue

    OWNER="$(stat -c '%U' "$DIR")"
    MODE="$(stat -c '%a' "$DIR")"

    echo
    stat -c '%A %U:%G %n' "$DIR"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "$DIR owned by root."
    else
        check WARNING "$DIR owned by $OWNER."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "$DIR not writable by group or others."
    else
        check WARNING "$DIR has group or other write permissions."
    fi

done

echo

# ==================================================
# EFI PARTITION AUDIT
# ==================================================

echo "[8] EFI PARTITION AUDIT"
echo "----------------------------------------------"

if [[ -d /sys/firmware/efi ]]; then

    EFI_MOUNT=""

    for DIR in /boot/efi /efi; do

        if mountpoint -q "$DIR"; then
            EFI_MOUNT="$DIR"
            break
        fi

    done

    if [[ -n "$EFI_MOUNT" ]]; then

        echo "EFI mount: $EFI_MOUNT"

        findmnt "$EFI_MOUNT" 2>/dev/null || true

        EFI_OWNER="$(stat -c '%U' "$EFI_MOUNT")"
        EFI_MODE="$(stat -c '%a' "$EFI_MOUNT")"

        if [[ "$EFI_OWNER" == "root" ]]; then
            check PASS "EFI mountpoint owned by root."
        else
            check WARNING "EFI mountpoint owned by $EFI_OWNER."
        fi

        if [[ "$EFI_MODE" =~ ^[0-7]+$ ]] &&
           (( (8#$EFI_MODE & 8#022) == 0 )); then
            check PASS "EFI mountpoint not writable by group or others."
        else
            check WARNING "EFI mountpoint permissions require review."
        fi

    else

        check INFO "EFI partition mountpoint not detected."

    fi

else

    check INFO "EFI partition audit skipped for Legacy BIOS."

fi

echo

# ==================================================
# RECOVERY ENTRY AUDIT
# ==================================================

echo "[9] RECOVERY AND RESCUE ENTRIES"
echo "----------------------------------------------"

if [[ -f /boot/grub/grub.cfg ]]; then

    grep -inE 'recovery|rescue|single-user' \
        /boot/grub/grub.cfg 2>/dev/null |
        head -n 20 || true

elif [[ -f /boot/grub2/grub.cfg ]]; then

    grep -inE 'recovery|rescue|single-user' \
        /boot/grub2/grub.cfg 2>/dev/null |
        head -n 20 || true

else

    check INFO "GRUB recovery configuration unavailable."

fi

check INFO "Recovery entries displayed for administrator review."

echo

# ==================================================
# SYSTEMD BOOT SERVICES
# ==================================================

echo "[10] BOOT-RELATED SERVICES"
echo "----------------------------------------------"

BOOT_SERVICES=(
    systemd-boot-update.service
    systemd-reboot.service
    systemd-modules-load.service
    systemd-sysctl.service
    systemd-udevd.service
)

for SERVICE in "${BOOT_SERVICES[@]}"; do

    LOAD_STATE="$(systemctl show "$SERVICE" \
        -p LoadState --value 2>/dev/null || true)"

    [[ "$LOAD_STATE" == "loaded" ]] || continue

    ACTIVE="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"

    echo "$SERVICE: $ACTIVE"

    check INFO "$SERVICE status recorded."

done

echo

# ==================================================
# SYSTEMD BOOTLOADER DETECTION
# ==================================================

echo "[11] SYSTEMD BOOTLOADER"
echo "----------------------------------------------"

if command -v bootctl >/dev/null 2>&1; then

    bootctl status --no-pager 2>/dev/null || true

    check INFO "Systemd bootloader status retrieved."

else

    check INFO "systemd-boot utility not installed."

fi

echo

# ==================================================
# BOOT CONFIGURATION REPORT
# ==================================================

{
    echo "CYBERPATRIOT BOOT SECURITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Kernel: $(uname -r)"
    echo "Date: $(date)"
    echo

    echo "BOOT MODE"
    if [[ -d /sys/firmware/efi ]]; then
        echo "UEFI"
    else
        echo "Legacy BIOS"
    fi

    echo
    echo "KERNEL PARAMETERS"
    cat /proc/cmdline

    echo
    echo "BOOT DIRECTORY"
    ls -ld /boot /boot/grub /boot/grub2 2>/dev/null || true

    echo
    echo "BOOT MOUNTS"
    findmnt /boot /boot/efi /efi 2>/dev/null || true

    echo
    echo "GRUB FILES"
    for FILE in "${GRUB_FILES[@]}"; do
        [[ -f "$FILE" ]] && stat "$FILE"
    done

    echo
    echo "SYSTEMD BOOT STATUS"
    bootctl status --no-pager 2>/dev/null || true

} > "$REPORT"

check PASS "Boot security report generated: $REPORT"

# ==================================================
# SUMMARY
# ==================================================

echo
echo "=============================================="
echo "             AUDIT SUMMARY"
echo "=============================================="

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Critical: $CRITICAL"
echo "Info:     $INFO"

echo
echo "Log: $LOG"
echo "Report: $REPORT"

log "Boot audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE MENU
# ==================================================

echo
read -rp "Would you like to review boot security options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "          BOOT SECURITY MENU"
echo "=============================================="
echo
echo "1. Review bootloader configuration."
echo "2. Review Secure Boot status."
echo "3. Review kernel boot parameters."
echo "4. Review EFI mount information."
echo "5. Back up GRUB configuration."
echo "6. Review boot security report."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)

        for FILE in "${GRUB_FILES[@]}"; do

            if [[ -f "$FILE" ]]; then
                echo
                echo "File: $FILE"
                stat "$FILE"
            fi

        done
        ;;

    2)

        if command -v mokutil >/dev/null 2>&1; then
            mokutil --sb-state
        else
            echo "mokutil is not installed."
        fi
        ;;

    3)

        cat /proc/cmdline
        ;;

    4)

        findmnt /boot /boot/efi /efi 2>/dev/null || true
        ;;

    5)

        BACKUP_COUNT=0

        for FILE in "${GRUB_FILES[@]}"; do

            if [[ -f "$FILE" ]]; then

                if backup_file "$FILE"; then
                    echo "Backed up: $FILE"
                    ((BACKUP_COUNT+=1))
                else
                    echo "Backup failed: $FILE"
                fi

            fi

        done

        if ((BACKUP_COUNT > 0)); then
            check PASS "Boot configuration backups created."
        else
            check WARNING "No GRUB configuration files backed up."
        fi
        ;;

    6)

        if [[ -f "$REPORT" ]]; then
            cat "$REPORT"
        else
            echo "Report unavailable."
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
echo "       FINAL BOOT VERIFICATION"
echo "=============================================="

echo "Boot mode:"
if [[ -d /sys/firmware/efi ]]; then
    echo "UEFI"
else
    echo "Legacy BIOS"
fi

echo
echo "Kernel: $(uname -r)"
echo "Boot directory:"
stat -c '%A %U:%G %n' /boot 2>/dev/null || true

echo
echo "Boot security session completed."
echo "Log: $LOG"

log "Boot security session completed."

exit 0

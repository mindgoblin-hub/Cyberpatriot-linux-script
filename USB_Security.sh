
#!/bin/bash

# ==========================================================
# CYBERPATRIOT UNIVERSAL USB SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$LOG_DIR/usb_backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG="$LOG_DIR/usb_security.log"
REPORT="$LOG_DIR/usb_report_$(date +%Y%m%d_%H%M%S).txt"

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
echo "          CYBERPATRIOT USB SECURITY AUDIT"
echo "=================================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"

# ==========================================================
# USB DEVICE DETECTION
# ==========================================================

section "[1] CONNECTED USB DEVICES"

if command -v lsusb >/dev/null 2>&1; then

    lsusb

    DEVICE_COUNT="$(lsusb | wc -l)"

    echo
    echo "Detected USB devices: $DEVICE_COUNT"

    check INFO "USB device inventory collected."

else

    echo "lsusb is not installed."

    if [[ -d /sys/bus/usb/devices ]]; then
        find /sys/bus/usb/devices -maxdepth 1 -type l -printf '%f\n'
        check INFO "USB devices inventoried through sysfs."
    else
        check WARNING "USB inventory unavailable."
    fi

fi

# ==========================================================
# USB STORAGE AUDIT
# ==========================================================

section "[2] USB STORAGE DEVICES"

if command -v lsblk >/dev/null 2>&1; then

    lsblk -o NAME,TRAN,TYPE,SIZE,FSTYPE,MOUNTPOINTS,RM,MODEL

    echo
    echo "USB transport devices:"

    lsblk -o NAME,TRAN,TYPE,SIZE,MOUNTPOINTS |
        awk 'NR == 1 || $2 == "usb"'

    check INFO "Block storage devices reviewed."

else

    check WARNING "lsblk unavailable."

fi

# ==========================================================
# USBGUARD AUDIT
# ==========================================================

section "[3] USBGUARD STATUS"

if command -v usbguard >/dev/null 2>&1; then

    echo "USBGuard version:"
    usbguard --version 2>/dev/null || true

    STATUS="$(systemctl is-active usbguard 2>/dev/null || true)"
    ENABLED="$(systemctl is-enabled usbguard 2>/dev/null || true)"

    echo "Service status: $STATUS"
    echo "Service enabled: $ENABLED"

    if [[ "$STATUS" == "active" ]]; then

        check PASS "USBGuard service is active."

        echo
        echo "USBGuard status:"

        usbguard get-parameter PresentDevicePolicy 2>/dev/null || true

        echo
        echo "Authorized device inventory:"

        usbguard list-devices 2>/dev/null || true

    else

        check WARNING "USBGuard installed but service inactive."

    fi

else

    check INFO "USBGuard is not installed."

fi

# ==========================================================
# USB AUTOMOUNT AUDIT
# ==========================================================

section "[4] USB AUTOMOUNT CONFIGURATION"

for USER_HOME in /home/*; do

    [[ -d "$USER_HOME" ]] || continue

    USERNAME="$(basename "$USER_HOME")"

    echo
    echo "User: $USERNAME"

    DCONF_DIR="$USER_HOME/.config/dconf"

    if [[ -d "$DCONF_DIR" ]]; then

        echo "dconf configuration directory found."

        if command -v dconf >/dev/null 2>&1 &&
           [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then

            dconf dump /org/gnome/desktop/media-handling/ \
                2>/dev/null || true

        fi

    fi

    if [[ -f "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/thunar-volman.xml" ]]; then

        echo "XFCE removable-media configuration found."

        grep -niE 'automount|mount' \
            "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/thunar-volman.xml" \
            2>/dev/null || true

    fi

done

check INFO "Desktop removable-media configuration reviewed."

# ==========================================================
# USB KERNEL MODULES
# ==========================================================

section "[5] USB KERNEL MODULES"

USB_MODULES=(
    usb_storage
    uas
    usbhid
    usbcore
    usbserial
)

if command -v lsmod >/dev/null 2>&1; then

    for MODULE in "${USB_MODULES[@]}"; do

        if lsmod | awk '{print $1}' | grep -qx "$MODULE"; then

            echo "[LOADED] $MODULE"

            check INFO "USB module loaded: $MODULE"

        else

            echo "[NOT LOADED] $MODULE"

        fi

    done

else

    check INFO "lsmod unavailable."

fi

# ==========================================================
# USB AUTHORIZATION
# ==========================================================

section "[6] USB DEVICE AUTHORIZATION"

USB_AUTH_COUNT=0

if [[ -d /sys/bus/usb/devices ]]; then

    for DEVICE in /sys/bus/usb/devices/*; do

        [[ -f "$DEVICE/authorized" ]] || continue

        DEVICE_NAME="$(basename "$DEVICE")"

        AUTHORIZED="$(cat "$DEVICE/authorized" 2>/dev/null || echo Unknown)"

        echo "$DEVICE_NAME: $AUTHORIZED"

        ((USB_AUTH_COUNT+=1))

    done

    if (( USB_AUTH_COUNT > 0 )); then
        check INFO "USB authorization attributes inspected."
    else
        check INFO "No readable USB authorization attributes found."
    fi

else

    check INFO "USB authorization sysfs directory unavailable."

fi

# ==========================================================
# USB MOUNT AUDIT
# ==========================================================

section "[7] USB MOUNT AUDIT"

if command -v findmnt >/dev/null 2>&1; then

    findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS |
        grep -E '/dev/sd|/dev/mmcblk|/dev/nvme' || true

    check INFO "Mounted storage devices reviewed."

else

    check WARNING "findmnt unavailable."

fi

# ==========================================================
# FSTAB AUDIT
# ==========================================================

section "[8] FSTAB REMOVABLE STORAGE CONFIGURATION"

if [[ -f /etc/fstab ]]; then

    echo "Removable storage-related entries:"

    grep -vE '^[[:space:]]*#|^[[:space:]]*$' /etc/fstab |
        grep -Ei 'usb|media|removable|UUID=' || true

    stat -c '%A %U:%G %n' /etc/fstab

    OWNER="$(stat -c '%U' /etc/fstab)"
    MODE="$(stat -c '%a' /etc/fstab)"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "fstab owned by root."
    else
        check WARNING "fstab not owned by root."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "fstab is not group/other writable."
    else
        check WARNING "fstab is group/other writable."
    fi

fi

# ==========================================================
# UDEV RULES AUDIT
# ==========================================================

section "[9] USB UDEV RULES"

UDEV_DIRS=(
    /etc/udev/rules.d
    /usr/lib/udev/rules.d
    /lib/udev/rules.d
)

for DIR in "${UDEV_DIRS[@]}"; do

    [[ -d "$DIR" ]] || continue

    echo
    echo "Directory: $DIR"

    grep -RniE 'usb|usb_storage|removable' \
        "$DIR" --include='*.rules' 2>/dev/null |
        head -n 40 || true

done

check INFO "USB-related udev rules reviewed."

# ==========================================================
# REMOVABLE MEDIA GROUPS
# ==========================================================

section "[10] REMOVABLE MEDIA GROUPS"

for GROUP in disk storage plugdev; do

    if getent group "$GROUP" >/dev/null 2>&1; then

        echo
        getent group "$GROUP"

        check INFO "Storage-related group found: $GROUP"

    fi

done

# ==========================================================
# USB SECURITY LOGS
# ==========================================================

section "[11] USB SECURITY LOGS"

if command -v journalctl >/dev/null 2>&1; then

    echo "Recent USB-related kernel events:"

    journalctl -k --since "24 hours ago" \
        --no-pager 2>/dev/null |
        grep -iE 'usb|usb_storage|uas' |
        tail -n 50 || true

    check INFO "USB-related kernel events reviewed."

else

    check INFO "Journal unavailable."

fi

# ==========================================================
# USB PACKAGE AUDIT
# ==========================================================

section "[12] USB SECURITY PACKAGES"

PACKAGES=(
    usbguard
    usbutils
    udisks2
    gvfs
    libblockdev
)

for PACKAGE in "${PACKAGES[@]}"; do

    FOUND=0

    if command -v dpkg-query >/dev/null 2>&1; then

        dpkg-query -W -f='${Status}' "$PACKAGE" \
            2>/dev/null | grep -q "install ok installed" &&
            FOUND=1

    elif command -v rpm >/dev/null 2>&1; then

        rpm -q "$PACKAGE" >/dev/null 2>&1 &&
            FOUND=1

    elif command -v pacman >/dev/null 2>&1; then

        pacman -Q "$PACKAGE" >/dev/null 2>&1 &&
            FOUND=1

    fi

    if (( FOUND == 1 )); then
        echo "[INSTALLED] $PACKAGE"
    fi

done

check INFO "USB-related package inventory completed."

# ==========================================================
# REPORT GENERATION
# ==========================================================

section "[13] GENERATING REPORT"

{
    echo "CYBERPATRIOT USB SECURITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Date: $(date)"

    echo
    echo "CONNECTED USB DEVICES"

    lsusb 2>/dev/null || true

    echo
    echo "USB STORAGE"

    lsblk -o NAME,TRAN,TYPE,SIZE,FSTYPE,MOUNTPOINTS,RM,MODEL 2>/dev/null || true

    echo
    echo "USBGUARD"

    usbguard list-devices 2>/dev/null || true
    systemctl status usbguard --no-pager 2>/dev/null || true

    echo
    echo "USB KERNEL MODULES"

    lsmod 2>/dev/null |
        grep -E 'usb_storage|uas|usbhid|usbcore|usbserial' || true

    echo
    echo "USB AUTHORIZATION"

    for DEVICE in /sys/bus/usb/devices/*; do

        [[ -f "$DEVICE/authorized" ]] || continue

        echo "$(basename "$DEVICE"): $(cat "$DEVICE/authorized" 2>/dev/null)"

    done

    echo
    echo "USB MOUNTS"

    findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS |
        grep -E '/dev/sd|/dev/mmcblk|/dev/nvme' || true

    echo
    echo "FSTAB"

    cat /etc/fstab 2>/dev/null || true

    echo
    echo "USB UDEV RULES"

    grep -RniE 'usb|usb_storage|removable' \
        /etc/udev/rules.d --include='*.rules' 2>/dev/null || true

    echo
    echo "USB EVENTS"

    journalctl -k --since "24 hours ago" \
        --no-pager 2>/dev/null |
        grep -iE 'usb|usb_storage|uas' || true

} > "$REPORT"

check PASS "USB security report generated."

# ==========================================================
# AUDIT SUMMARY
# ==========================================================

section "[14] AUDIT SUMMARY"

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Critical: $CRITICAL"
echo "Info:     $INFO"

echo
echo "Log: $LOG"
echo "Report: $REPORT"

log "USB audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==========================================================
# INTERACTIVE MENU
# ==========================================================

section "[15] USB SECURITY MANAGEMENT MENU"

echo "1. Review connected USB devices."
echo "2. Review USB storage devices."
echo "3. Review USBGuard status."
echo "4. Review USB kernel modules."
echo "5. Review USB authorization."
echo "6. Review USB-related logs."
echo "7. Back up USB configurations."
echo "8. View audit report."
echo "0. Exit."

echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)

        lsusb 2>/dev/null ||
            echo "lsusb unavailable."

        ;;

    2)

        lsblk -o NAME,TRAN,TYPE,SIZE,FSTYPE,MOUNTPOINTS,RM,MODEL

        ;;

    3)

        if command -v usbguard >/dev/null 2>&1; then

            systemctl status usbguard --no-pager 2>/dev/null || true

            usbguard list-devices 2>/dev/null || true

        else

            echo "USBGuard unavailable."

        fi

        ;;

    4)

        lsmod |
            grep -E 'usb_storage|uas|usbhid|usbcore|usbserial' ||
            echo "No matching modules found."

        ;;

    5)

        for DEVICE in /sys/bus/usb/devices/*; do

            [[ -f "$DEVICE/authorized" ]] || continue

            echo "$(basename "$DEVICE"): $(cat "$DEVICE/authorized")"

        done

        ;;

    6)

        journalctl -k --since "24 hours ago" \
            --no-pager 2>/dev/null |
            grep -iE 'usb|usb_storage|uas' |
            tail -n 50 || true

        ;;

    7)

        for FILE in /etc/fstab /etc/udev/rules.d; do

            [[ -e "$FILE" ]] || continue

            NAME="$(basename "$FILE")"

            tar -czf \
                "$BACKUP_DIR/${NAME}_$(date +%Y%m%d_%H%M%S).tar.gz" \
                -C /etc "$NAME"

            echo "Backed up: $FILE"

        done

        ;;

    8)

        cat "$REPORT"

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
echo "          USB SECURITY AUDIT COMPLETED"
echo "=================================================="

echo "Log: $LOG"
echo "Report: $REPORT"

log "USB security session completed."

exit 0

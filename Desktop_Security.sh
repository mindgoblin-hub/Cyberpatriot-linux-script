
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL DESKTOP SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG="$LOG_DIR/desktop_security.log"
REPORT="$LOG_DIR/desktop_security_report_$(date +%Y%m%d_%H%M%S).txt"
BACKUP_DIR="$LOG_DIR/desktop_backups"

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

# ==================================================
# LOGGING
# ==================================================

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
# HEADER
# ==================================================

echo "=============================================="
echo "       CYBERPATRIOT DESKTOP SECURITY AUDIT"
echo "=============================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"
echo

# ==================================================
# DESKTOP ENVIRONMENT DETECTION
# ==================================================

echo "[1] DESKTOP ENVIRONMENT"
echo "----------------------------------------------"

DESKTOP_FOUND=0

for USER_HOME in /home/*; do

    [[ -d "$USER_HOME" ]] || continue

    USERNAME="$(basename "$USER_HOME")"

    if [[ -f "$USER_HOME/.xsession" ]] ||
       [[ -f "$USER_HOME/.xinitrc" ]] ||
       [[ -d "$USER_HOME/.config" ]]; then

        echo "Desktop configuration detected for: $USERNAME"
        ((DESKTOP_FOUND+=1))

    fi

done

echo "Current session: ${XDG_CURRENT_DESKTOP:-Unknown}"
echo "Session type: ${XDG_SESSION_TYPE:-Unknown}"

if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    check INFO "Desktop environment: $XDG_CURRENT_DESKTOP"
else
    check INFO "Desktop environment could not be identified from current session."
fi

echo

# ==================================================
# DISPLAY MANAGER AUDIT
# ==================================================

echo "[2] DISPLAY MANAGER"
echo "----------------------------------------------"

DISPLAY_MANAGERS=(
    gdm
    gdm3
    lightdm
    sddm
    lxdm
)

DM_FOUND=0

for DM in "${DISPLAY_MANAGERS[@]}"; do

    if systemctl list-unit-files "${DM}.service" \
        --no-legend 2>/dev/null | grep -q "${DM}.service"; then

        STATUS="$(systemctl is-active "${DM}.service" 2>/dev/null || true)"

        echo "$DM: $STATUS"

        ((DM_FOUND+=1))

        check INFO "Display manager $DM detected."

    fi

done

if ((DM_FOUND == 0)); then
    check INFO "No recognized display manager detected."
fi

echo

# ==================================================
# GUEST ACCOUNT AUDIT
# ==================================================

echo "[3] GUEST ACCOUNT AUDIT"
echo "----------------------------------------------"

GUEST_CONFIGS=(
    /etc/lightdm/lightdm.conf
    /etc/lightdm/lightdm.conf.d
    /etc/gdm3/custom.conf
    /etc/gdm/custom.conf
)

GUEST_FOUND=0

for CONFIG in "${GUEST_CONFIGS[@]}"; do

    [[ -e "$CONFIG" ]] || continue

    MATCHES="$(grep -RniE 'allow-guest[[:space:]]*=[[:space:]]*true|TimedLoginEnable[[:space:]]*=[[:space:]]*true' \
        "$CONFIG" 2>/dev/null || true)"

    if [[ -n "$MATCHES" ]]; then

        echo "$MATCHES"

        ((GUEST_FOUND+=1))

        check WARNING "Guest or automatic login configuration requires review."

    fi

done

if ((GUEST_FOUND == 0)); then
    check INFO "No enabled guest-login configuration detected in inspected files."
fi

echo

# ==================================================
# AUTOMATIC LOGIN AUDIT
# ==================================================

echo "[4] AUTOMATIC LOGIN"
echo "----------------------------------------------"

AUTOLOGIN_FOUND=0

for CONFIG in \
    /etc/gdm3/custom.conf \
    /etc/gdm/custom.conf \
    /etc/lightdm/lightdm.conf \
    /etc/sddm.conf
do

    [[ -f "$CONFIG" ]] || continue

    MATCHES="$(grep -niE 'AutomaticLogin|autologin-user|autologin-user-timeout' \
        "$CONFIG" 2>/dev/null || true)"

    if [[ -n "$MATCHES" ]]; then

        echo "$CONFIG"
        echo "$MATCHES"

        ((AUTOLOGIN_FOUND+=1))

    fi

done

if ((AUTOLOGIN_FOUND > 0)); then
    check WARNING "Automatic login settings found. Verify whether they are enabled."
else
    check PASS "No automatic login directives found in inspected configuration files."
fi

echo

# ==================================================
# SCREEN LOCK AUDIT
# ==================================================

echo "[5] SCREEN LOCK CONFIGURATION"
echo "----------------------------------------------"

LOCK_FOUND=0

for USER_HOME in /home/*; do

    [[ -d "$USER_HOME" ]] || continue

    USERNAME="$(basename "$USER_HOME")"

    if [[ -d "$USER_HOME/.config" ]]; then

        echo
        echo "User: $USERNAME"

        if [[ -d "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml" ]]; then

            XFCE_CONFIG="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml"

            if [[ -f "$XFCE_CONFIG" ]]; then

                grep -niE 'lock|idle|timeout' "$XFCE_CONFIG" || true

                ((LOCK_FOUND+=1))

            fi

        fi

        if [[ -d "$USER_HOME/.config/gnome-session" ]]; then

            echo "GNOME session configuration detected."

        fi

    fi

done

if ((LOCK_FOUND > 0)); then
    check INFO "Desktop screen-lock configuration files found."
else
    check INFO "Screen-lock settings require review through desktop settings."
fi

echo

# ==================================================
# REMOTE DESKTOP AUDIT
# ==================================================

echo "[6] REMOTE DESKTOP SERVICES"
echo "----------------------------------------------"

REMOTE_SERVICES=(
    xrdp
    xrdp-sesman
    vino-server
    gnome-remote-desktop
    wayvnc
    vncserver
)

REMOTE_FOUND=0

for SERVICE in "${REMOTE_SERVICES[@]}"; do

    LOAD_STATE="$(systemctl show "$SERVICE.service" \
        -p LoadState --value 2>/dev/null || true)"

    [[ "$LOAD_STATE" == "loaded" ]] || continue

    STATUS="$(systemctl is-active "$SERVICE.service" 2>/dev/null || true)"

    ENABLED="$(systemctl is-enabled "$SERVICE.service" 2>/dev/null || true)"

    echo "$SERVICE: $STATUS / $ENABLED"

    ((REMOTE_FOUND+=1))

    if [[ "$STATUS" == "active" ]]; then
        check WARNING "Remote desktop service $SERVICE is active. Verify authorization."
    else
        check INFO "Remote desktop service $SERVICE is installed but inactive."
    fi

done

if ((REMOTE_FOUND == 0)); then
    check PASS "No recognized remote desktop services detected."
fi

echo

# ==================================================
# SCREEN SAVER AUDIT
# ==================================================

echo "[7] SCREEN SAVER PACKAGES"
echo "----------------------------------------------"

for PACKAGE in \
    xscreensaver \
    gnome-screensaver \
    xfce4-screensaver \
    mate-screensaver
do

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

    if ((FOUND == 1)); then
        echo "[INSTALLED] $PACKAGE"
        check INFO "$PACKAGE installed."
    fi

done

echo

# ==================================================
# ROOT DESKTOP ACCESS AUDIT
# ==================================================

echo "[8] ROOT DESKTOP ACCESS"
echo "----------------------------------------------"

if [[ -f /etc/pam.d/gdm-password ]]; then

    if grep -q 'pam_succeed_if.so.*user != root' /etc/pam.d/gdm-password; then
        check PASS "GDM root login restriction detected."
    else
        check INFO "Review GDM root login restrictions."
    fi

else

    check INFO "GDM PAM configuration unavailable."

fi

echo

# ==================================================
# DESKTOP CONFIGURATION PERMISSIONS
# ==================================================

echo "[9] DESKTOP CONFIGURATION PERMISSIONS"
echo "----------------------------------------------"

for CONFIG in \
    /etc/gdm3 \
    /etc/gdm \
    /etc/lightdm \
    /etc/sddm.conf
do

    [[ -e "$CONFIG" ]] || continue

    OWNER="$(stat -c '%U' "$CONFIG")"

    echo
    stat -c '%A %U:%G %n' "$CONFIG"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "$CONFIG owned by root."
    else
        check WARNING "$CONFIG owned by $OWNER."
    fi

done

echo

# ==================================================
# DESKTOP SHARING AUDIT
# ==================================================

echo "[10] DESKTOP SHARING CONFIGURATION"
echo "----------------------------------------------"

SHARING_DIRS=(
    /etc/gnome-remote-desktop
    /etc/vino
    /etc/xrdp
)

for DIR in "${SHARING_DIRS[@]}"; do

    if [[ -d "$DIR" ]]; then

        echo "Found: $DIR"

        find "$DIR" -maxdepth 2 -type f -print 2>/dev/null

        check INFO "Desktop sharing configuration found: $DIR"

    fi

done

echo

# ==================================================
# REPORT GENERATION
# ==================================================

{
    echo "CYBERPATRIOT DESKTOP SECURITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Date: $(date)"

    echo
    echo "DISPLAY MANAGERS"

    for DM in "${DISPLAY_MANAGERS[@]}"; do
        systemctl status "${DM}.service" --no-pager 2>/dev/null || true
    done

    echo
    echo "REMOTE DESKTOP SERVICES"

    for SERVICE in "${REMOTE_SERVICES[@]}"; do
        systemctl status "$SERVICE.service" --no-pager 2>/dev/null || true
    done

    echo
    echo "LOGIN CONFIGURATION"

    grep -RniE 'AutomaticLogin|autologin-user|allow-guest' \
        /etc/gdm3 /etc/gdm /etc/lightdm /etc/sddm.conf \
        2>/dev/null || true

    echo
    echo "DESKTOP SHARING CONFIGURATION"

    find /etc/gnome-remote-desktop /etc/vino /etc/xrdp \
        -maxdepth 2 -type f -print 2>/dev/null || true

} > "$REPORT"

check PASS "Desktop security report generated."

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

log "Desktop audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE MENU
# ==================================================

echo
read -rp "Would you like to review desktop security options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "          DESKTOP SECURITY MENU"
echo "=============================================="
echo
echo "1. Review display managers."
echo "2. Review automatic login configuration."
echo "3. Review guest login configuration."
echo "4. Review remote desktop services."
echo "5. Review desktop configuration permissions."
echo "6. Review desktop security report."
echo "7. Back up desktop configurations."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)

        for DM in "${DISPLAY_MANAGERS[@]}"; do
            systemctl status "${DM}.service" --no-pager 2>/dev/null || true
        done

        ;;

    2)

        grep -RniE 'AutomaticLogin|autologin-user' \
            /etc/gdm3 /etc/gdm /etc/lightdm /etc/sddm.conf \
            2>/dev/null || echo "No matching configuration found."

        ;;

    3)

        grep -RniE 'allow-guest|TimedLoginEnable' \
            /etc/lightdm /etc/gdm3 /etc/gdm \
            2>/dev/null || echo "No matching configuration found."

        ;;

    4)

        for SERVICE in "${REMOTE_SERVICES[@]}"; do
            systemctl status "$SERVICE.service" --no-pager 2>/dev/null || true
        done

        ;;

    5)

        for CONFIG in /etc/gdm3 /etc/gdm /etc/lightdm /etc/sddm.conf; do

            [[ -e "$CONFIG" ]] || continue

            stat -c '%A %U:%G %n' "$CONFIG"

        done

        ;;

    6)

        cat "$REPORT"

        ;;

    7)

        for CONFIG in \
            /etc/gdm3 \
            /etc/gdm \
            /etc/lightdm \
            /etc/sddm.conf
        do

            [[ -e "$CONFIG" ]] || continue

            NAME="$(basename "$CONFIG")"

            cp -a "$CONFIG" \
                "$BACKUP_DIR/${NAME}_$(date +%Y%m%d_%H%M%S)"

            echo "Backed up: $CONFIG"

        done

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
echo "       FINAL DESKTOP VERIFICATION"
echo "=============================================="

echo "Display environment: ${XDG_CURRENT_DESKTOP:-Unknown}"
echo "Session type: ${XDG_SESSION_TYPE:-Unknown}"

echo
echo "Remote desktop services:"

for SERVICE in "${REMOTE_SERVICES[@]}"; do

    STATUS="$(systemctl is-active "$SERVICE.service" 2>/dev/null || true)"

    if [[ "$STATUS" == "active" ]]; then
        echo "$SERVICE: ACTIVE"
    fi

done

echo
echo "Desktop security session completed."
echo "Log: $LOG"
echo "Report: $REPORT"

log "Desktop security session completed."

exit 0

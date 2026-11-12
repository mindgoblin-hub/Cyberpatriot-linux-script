
#!/bin/bash

# ==========================================================
# CYBERPATRIOT UNIVERSAL APPARMOR / SELINUX SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$LOG_DIR/mac_backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG="$LOG_DIR/apparmor_selinux.log"
REPORT="$LOG_DIR/mac_report_$(date +%Y%m%d_%H%M%S).txt"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run with sudo."
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
echo "       CYBERPATRIOT APPARMOR / SELINUX AUDIT"
echo "=================================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Kernel: $(uname -r)"
echo "Hostname: $(hostname)"
echo "Date: $(date)"

# ==========================================================
# DETECTION
# ==========================================================

APPARMOR=0
SELINUX=0

if command -v aa-status >/dev/null 2>&1 ||
   [[ -d /sys/kernel/security/apparmor ]]; then
    APPARMOR=1
fi

if command -v getenforce >/dev/null 2>&1 ||
   [[ -d /sys/fs/selinux ]]; then
    SELINUX=1
fi

section "[1] SECURITY FRAMEWORK DETECTION"

if (( APPARMOR == 1 )); then
    echo "AppArmor: DETECTED"
    check INFO "AppArmor detected."
else
    echo "AppArmor: NOT DETECTED"
fi

if (( SELINUX == 1 )); then
    echo "SELinux: DETECTED"
    check INFO "SELinux detected."
else
    echo "SELinux: NOT DETECTED"
fi

if (( APPARMOR == 0 && SELINUX == 0 )); then
    check WARNING "No supported MAC framework detected."
fi

# ==========================================================
# APPARMOR STATUS
# ==========================================================

section "[2] APPARMOR STATUS"

if (( APPARMOR == 1 )); then

    if command -v aa-status >/dev/null 2>&1; then

        AA_OUTPUT="$(aa-status 2>&1 || true)"

        echo "$AA_OUTPUT"

        if grep -qi "apparmor module is loaded" <<< "$AA_OUTPUT"; then
            check PASS "AppArmor kernel module loaded."
        else
            check WARNING "AppArmor module status needs investigation."
        fi

        if grep -qi "profiles are in enforce mode" <<< "$AA_OUTPUT"; then
            check PASS "AppArmor enforcing profiles detected."
        else
            check WARNING "No enforcing profiles reported."
        fi

        if grep -qi "profiles are in complain mode" <<< "$AA_OUTPUT"; then
            check WARNING "Complain-mode profiles detected."
        fi

    else

        check WARNING "aa-status utility unavailable."

    fi

    if [[ -r /sys/module/apparmor/parameters/enabled ]]; then

        ENABLED="$(cat /sys/module/apparmor/parameters/enabled)"

        echo "Kernel AppArmor enabled: $ENABLED"

        [[ "$ENABLED" == "Y" ]] &&
            check PASS "AppArmor enabled in kernel." ||
            check WARNING "AppArmor kernel parameter is not enabled."

    fi

else

    check INFO "AppArmor audit skipped."

fi

# ==========================================================
# APPARMOR SERVICE
# ==========================================================

section "[3] APPARMOR SERVICE"

if systemctl list-unit-files apparmor.service \
    --no-legend 2>/dev/null | grep -q apparmor; then

    STATUS="$(systemctl is-active apparmor 2>/dev/null || true)"
    ENABLED="$(systemctl is-enabled apparmor 2>/dev/null || true)"

    echo "Status: $STATUS"
    echo "Enabled: $ENABLED"

    if [[ "$STATUS" == "active" ]]; then
        check PASS "AppArmor service active."
    else
        check WARNING "AppArmor service inactive."
    fi

else

    check INFO "AppArmor service unavailable."

fi

# ==========================================================
# APPARMOR PROFILE AUDIT
# ==========================================================

section "[4] APPARMOR PROFILES"

if (( APPARMOR == 1 )); then

    if [[ -d /etc/apparmor.d ]]; then

        echo "Installed profiles:"

        find /etc/apparmor.d -maxdepth 1 -type f \
            ! -name '.*' -printf '%f\n' 2>/dev/null

        PROFILE_COUNT="$(find /etc/apparmor.d -maxdepth 1 \
            -type f ! -name '.*' 2>/dev/null | wc -l)"

        echo "Profile count: $PROFILE_COUNT"

        check INFO "AppArmor profiles inventoried."

    else

        check WARNING "AppArmor profile directory missing."

    fi

else

    check INFO "AppArmor profiles unavailable."

fi

# ==========================================================
# SELINUX STATUS
# ==========================================================

section "[5] SELINUX STATUS"

if (( SELINUX == 1 )); then

    if command -v getenforce >/dev/null 2>&1; then

        MODE="$(getenforce 2>/dev/null || echo Unknown)"

        echo "SELinux Mode: $MODE"

        case "$MODE" in
            Enforcing)
                check PASS "SELinux enforcing."
                ;;
            Permissive)
                check WARNING "SELinux permissive."
                ;;
            Disabled)
                check CRITICAL "SELinux disabled."
                ;;
            *)
                check WARNING "Unknown SELinux state."
                ;;
        esac

    fi

    if command -v sestatus >/dev/null 2>&1; then
        echo
        sestatus
    fi

else

    check INFO "SELinux audit skipped."

fi

# ==========================================================
# SELINUX CONFIGURATION
# ==========================================================

section "[6] SELINUX CONFIGURATION"

SELINUX_CONFIG="/etc/selinux/config"

if [[ -f "$SELINUX_CONFIG" ]]; then

    cat "$SELINUX_CONFIG"

    CONFIG_MODE="$(grep -E '^[[:space:]]*SELINUX=' \
        "$SELINUX_CONFIG" | tail -n 1 |
        cut -d= -f2 | tr -d ' "' || true)"

    case "$CONFIG_MODE" in
        enforcing)
            check PASS "SELinux configuration specifies enforcing."
            ;;
        permissive)
            check WARNING "SELinux configuration specifies permissive."
            ;;
        disabled)
            check CRITICAL "SELinux configuration specifies disabled."
            ;;
        *)
            check INFO "SELinux configuration requires review."
            ;;
    esac

    OWNER="$(stat -c '%U' "$SELINUX_CONFIG")"
    MODE="$(stat -c '%a' "$SELINUX_CONFIG")"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "SELinux configuration owned by root."
    else
        check WARNING "SELinux configuration not owned by root."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "SELinux configuration permissions acceptable."
    else
        check WARNING "SELinux configuration is group/other writable."
    fi

else

    check INFO "SELinux configuration file unavailable."

fi

# ==========================================================
# SELINUX BOOLEAN AUDIT
# ==========================================================

section "[7] SELINUX BOOLEANS"

if command -v getsebool >/dev/null 2>&1; then

    getsebool -a 2>/dev/null | head -n 50

    check INFO "SELinux booleans reviewed."

else

    check INFO "getsebool unavailable."

fi

# ==========================================================
# SELINUX POLICY AUDIT
# ==========================================================

section "[8] SELINUX POLICIES"

if command -v semodule >/dev/null 2>&1; then

    semodule -l 2>/dev/null | head -n 50

    check INFO "SELinux policy modules reviewed."

else

    check INFO "SELinux policy tools unavailable."

fi

# ==========================================================
# SECURITY CONTEXT AUDIT
# ==========================================================

section "[9] SECURITY CONTEXTS"

if command -v ls >/dev/null 2>&1 &&
   command -v getenforce >/dev/null 2>&1; then

    ls -Zd /etc /etc/passwd /etc/shadow \
        /var/log /home /root 2>/dev/null || true

    check INFO "SELinux contexts reviewed."

else

    check INFO "SELinux context inspection unavailable."

fi

# ==========================================================
# APPARMOR DENIAL AUDIT
# ==========================================================

section "[10] APPARMOR DENIALS"

if command -v journalctl >/dev/null 2>&1; then

    DENIALS="$(journalctl -k --since "24 hours ago" \
        --no-pager 2>/dev/null |
        grep -i 'apparmor="DENIED"' |
        tail -n 30 || true)"

    if [[ -n "$DENIALS" ]]; then
        echo "$DENIALS"
        check WARNING "AppArmor denial events found."
    else
        check INFO "No recent AppArmor denials found in accessible logs."
    fi

else

    check INFO "Journal unavailable."

fi

# ==========================================================
# SELINUX DENIAL AUDIT
# ==========================================================

section "[11] SELINUX DENIALS"

if command -v ausearch >/dev/null 2>&1; then

    DENIALS="$(ausearch -m AVC,USER_AVC -ts recent 2>/dev/null |
        tail -n 40 || true)"

    if [[ -n "$DENIALS" ]]; then
        echo "$DENIALS"
        check WARNING "SELinux denial events found."
    else
        check INFO "No recent SELinux denials returned."
    fi

else

    echo "ausearch unavailable."

    if command -v journalctl >/dev/null 2>&1; then
        journalctl --since "24 hours ago" --no-pager 2>/dev/null |
            grep -i 'avc:.*denied' | tail -n 30 || true
    fi

    check INFO "SELinux audit utility unavailable."

fi

# ==========================================================
# PACKAGE AUDIT
# ==========================================================

section "[12] SECURITY PACKAGES"

PACKAGES=(
    apparmor
    apparmor-utils
    selinux-policy
    selinux-policy-targeted
    policycoreutils
    policycoreutils-python-utils
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

check INFO "Security package inventory completed."

# ==========================================================
# REPORT GENERATION
# ==========================================================

{
    echo "CYBERPATRIOT APPARMOR / SELINUX REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Date: $(date)"

    echo
    echo "APPARMOR STATUS"
    aa-status 2>&1 || true

    echo
    echo "SELINUX STATUS"
    sestatus 2>/dev/null || true

    echo
    echo "SELINUX CONFIGURATION"
    cat /etc/selinux/config 2>/dev/null || true

    echo
    echo "APPARMOR PROFILES"
    find /etc/apparmor.d -maxdepth 1 -type f \
        -printf '%f\n' 2>/dev/null || true

    echo
    echo "SELINUX BOOLEANS"
    getsebool -a 2>/dev/null || true

    echo
    echo "SELINUX POLICIES"
    semodule -l 2>/dev/null || true

    echo
    echo "SELINUX DENIALS"
    ausearch -m AVC,USER_AVC -ts recent 2>/dev/null || true

} > "$REPORT"

check PASS "Security report generated."

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

log "Audit complete: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==========================================================
# INTERACTIVE MENU
# ==========================================================

section "[14] SECURITY MANAGEMENT MENU"

echo "1. Review AppArmor status"
echo "2. Review AppArmor profiles"
echo "3. Review SELinux status"
echo "4. Review SELinux configuration"
echo "5. Review SELinux booleans"
echo "6. Review security denials"
echo "7. Back up security configurations"
echo "8. View audit report"
echo "0. Exit"

echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)
        aa-status 2>&1 || echo "AppArmor unavailable."
        ;;

    2)
        if [[ -d /etc/apparmor.d ]]; then
            find /etc/apparmor.d -maxdepth 1 -type f -print
        else
            echo "AppArmor unavailable."
        fi
        ;;

    3)
        if command -v sestatus >/dev/null 2>&1; then
            sestatus
        elif command -v getenforce >/dev/null 2>&1; then
            getenforce
        else
            echo "SELinux unavailable."
        fi
        ;;

    4)
        cat "$SELINUX_CONFIG" 2>/dev/null ||
            echo "Configuration unavailable."
        ;;

    5)
        getsebool -a 2>/dev/null ||
            echo "SELinux boolean utility unavailable."
        ;;

    6)
        journalctl -k --since "24 hours ago" \
            --no-pager 2>/dev/null |
            grep -i 'apparmor="DENIED"' |
            tail -n 30 || true

        echo
        ausearch -m AVC,USER_AVC -ts recent 2>/dev/null || true
        ;;

    7)

        if [[ -f "$SELINUX_CONFIG" ]]; then

            cp -a "$SELINUX_CONFIG" \
                "$BACKUP_DIR/selinux_config_$(date +%Y%m%d_%H%M%S)"

            echo "SELinux configuration backed up."

        fi

        if [[ -d /etc/apparmor.d ]]; then

            tar -czf \
                "$BACKUP_DIR/apparmor_profiles_$(date +%Y%m%d_%H%M%S).tar.gz" \
                -C /etc apparmor.d

            echo "AppArmor profiles backed up."

        fi

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
echo "       MAC SECURITY AUDIT COMPLETED"
echo "=================================================="

echo "Log: $LOG"
echo "Report: $REPORT"

log "AppArmor / SELinux session completed."

exit 0

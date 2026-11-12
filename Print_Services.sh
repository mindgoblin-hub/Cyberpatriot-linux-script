
#!/bin/bash

# ==========================================================
# CYBERPATRIOT UNIVERSAL PRINT SERVICES SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$LOG_DIR/print_backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG="$LOG_DIR/print_services.log"
REPORT="$LOG_DIR/print_report_$(date +%Y%m%d_%H%M%S).txt"

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
echo "        CYBERPATRIOT PRINT SERVICES AUDIT"
echo "=================================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"

# ==========================================================
# SERVICE DETECTION
# ==========================================================

PRINT_SERVICES=(
    cups
    cups-browsed
    cups.socket
    cups.path
    avahi-daemon
    ipp-usb
    saned
)

section "[1] PRINT SERVICE DETECTION"

for SERVICE in "${PRINT_SERVICES[@]}"; do

    LOAD_STATE="$(systemctl show "$SERVICE" \
        -p LoadState --value 2>/dev/null || true)"

    [[ "$LOAD_STATE" == "loaded" ]] || continue

    STATUS="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
    ENABLED="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

    echo
    echo "Service: $SERVICE"
    echo "Status: $STATUS"
    echo "Enabled: $ENABLED"

    if [[ "$STATUS" == "active" ]]; then
        check INFO "$SERVICE is running."
    else
        check PASS "$SERVICE is not currently running."
    fi

done

# ==========================================================
# CUPS DETECTION
# ==========================================================

section "[2] CUPS DETECTION"

if command -v cups-config >/dev/null 2>&1; then

    echo "CUPS version:"
    cups-config --version 2>/dev/null || true

    check PASS "CUPS utilities detected."

elif command -v lpstat >/dev/null 2>&1; then

    echo "CUPS printing utility detected."

    check INFO "CUPS utilities partially available."

else

    check INFO "CUPS utilities not installed or unavailable."

fi

# ==========================================================
# CUPS SERVICE STATUS
# ==========================================================

section "[3] CUPS SERVICE STATUS"

if systemctl list-unit-files cups.service \
    --no-legend 2>/dev/null | grep -q cups; then

    STATUS="$(systemctl is-active cups 2>/dev/null || true)"
    ENABLED="$(systemctl is-enabled cups 2>/dev/null || true)"

    echo "CUPS status: $STATUS"
    echo "CUPS enabled: $ENABLED"

    if [[ "$STATUS" == "active" ]]; then
        check INFO "CUPS is running. Verify whether printing is required."
    else
        check PASS "CUPS is not running."
    fi

else

    check INFO "CUPS service not installed."

fi

# ==========================================================
# PRINTER QUEUE AUDIT
# ==========================================================

section "[4] PRINTER QUEUE AUDIT"

if command -v lpstat >/dev/null 2>&1; then

    echo "Configured printers:"
    lpstat -p -d 2>/dev/null || true

    echo
    echo "Printer destinations:"
    lpstat -v 2>/dev/null || true

    echo
    echo "Active print jobs:"
    lpstat -o 2>/dev/null || true

    check INFO "Printer queues reviewed."

else

    check INFO "lpstat unavailable. Cannot inspect printer queues."

fi

# ==========================================================
# CUPS CONFIGURATION
# ==========================================================

section "[5] CUPS CONFIGURATION AUDIT"

CUPS_CONFIG="/etc/cups/cupsd.conf"

if [[ -f "$CUPS_CONFIG" ]]; then

    echo "Configuration file: $CUPS_CONFIG"

    stat -c '%A %U:%G %n' "$CUPS_CONFIG"

    OWNER="$(stat -c '%U' "$CUPS_CONFIG")"
    MODE="$(stat -c '%a' "$CUPS_CONFIG")"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "CUPS configuration owned by root."
    else
        check WARNING "CUPS configuration is not owned by root."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "CUPS configuration is not group/other writable."
    else
        check WARNING "CUPS configuration is group/other writable."
    fi

    echo
    echo "Important CUPS directives:"

    grep -nE '^[[:space:]]*(Listen|Port|Browsing|BrowseLocalProtocols|WebInterface|DefaultAuthType|<Location|</Location|Allow|Deny|Require)' \
        "$CUPS_CONFIG" 2>/dev/null || true

    check INFO "CUPS configuration directives reviewed."

else

    check INFO "CUPS configuration file unavailable."

fi

# ==========================================================
# CUPS ACCESS CONTROL
# ==========================================================

section "[6] CUPS ACCESS CONTROL"

if [[ -f "$CUPS_CONFIG" ]]; then

    if grep -Eq '^[[:space:]]*Listen[[:space:]]+localhost:631' "$CUPS_CONFIG"; then
        check PASS "CUPS localhost listener configuration detected."
    fi

    if grep -Eq '^[[:space:]]*Port[[:space:]]+631' "$CUPS_CONFIG"; then
        check WARNING "CUPS Port 631 directive found. Review network exposure."
    fi

    if grep -Eq '^[[:space:]]*Browsing[[:space:]]+Yes' "$CUPS_CONFIG"; then
        check WARNING "CUPS browsing enabled."
    else
        check INFO "CUPS browsing is not explicitly enabled."
    fi

    if grep -Eq '^[[:space:]]*WebInterface[[:space:]]+Yes' "$CUPS_CONFIG"; then
        check INFO "CUPS web administration interface enabled."
    fi

else

    check INFO "CUPS access control audit skipped."

fi

# ==========================================================
# NETWORK LISTENERS
# ==========================================================

section "[7] PRINTING NETWORK LISTENERS"

if command -v ss >/dev/null 2>&1; then

    echo "TCP listeners associated with printing:"
    ss -lntp 2>/dev/null |
        grep -E ':(631|515|9100)([[:space:]]|$)' || true

    echo
    echo "UDP listeners associated with printing:"
    ss -lunp 2>/dev/null |
        grep -E ':(631|5353)([[:space:]]|$)' || true

    check INFO "Printing-related network listeners inspected."

else

    check INFO "ss utility unavailable."

fi

# ==========================================================
# AVAHI SERVICE
# ==========================================================

section "[8] AVAHI / PRINTER DISCOVERY"

if systemctl list-unit-files avahi-daemon.service \
    --no-legend 2>/dev/null | grep -q avahi-daemon; then

    STATUS="$(systemctl is-active avahi-daemon 2>/dev/null || true)"

    echo "Avahi status: $STATUS"

    if [[ "$STATUS" == "active" ]]; then
        check WARNING "Avahi is running. Verify whether network printer discovery is needed."
    else
        check PASS "Avahi is not running."
    fi

else

    check INFO "Avahi service unavailable."

fi

# ==========================================================
# SANED SERVICE
# ==========================================================

section "[9] SCANNER SERVICE AUDIT"

if systemctl list-unit-files saned.service \
    --no-legend 2>/dev/null | grep -q saned; then

    STATUS="$(systemctl is-active saned 2>/dev/null || true)"
    ENABLED="$(systemctl is-enabled saned 2>/dev/null || true)"

    echo "SANED status: $STATUS"
    echo "SANED enabled: $ENABLED"

    if [[ "$STATUS" == "active" ]]; then
        check WARNING "SANED is running. Verify scanner sharing requirements."
    else
        check PASS "SANED is not running."
    fi

else

    check INFO "SANED service unavailable."

fi

# ==========================================================
# PRINTING GROUP AUDIT
# ==========================================================

section "[10] PRINTING GROUP MEMBERSHIP"

for GROUP in lp lpadmin scanner; do

    if getent group "$GROUP" >/dev/null 2>&1; then

        echo
        getent group "$GROUP"

        check INFO "Printing-related group found: $GROUP"

    fi

done

# ==========================================================
# PRINTING CONFIGURATION PERMISSIONS
# ==========================================================

section "[11] PRINTING CONFIGURATION PERMISSIONS"

for DIR in \
    /etc/cups \
    /etc/printcap \
    /var/spool/cups
do

    [[ -e "$DIR" ]] || continue

    echo
    stat -c '%A %U:%G %n' "$DIR"

    OWNER="$(stat -c '%U' "$DIR")"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "$DIR owned by root."
    else
        check WARNING "$DIR not owned by root."
    fi

done

# ==========================================================
# FIREWALL AUDIT
# ==========================================================

section "[12] PRINTING FIREWALL RULES"

if command -v ufw >/dev/null 2>&1; then

    echo "UFW status:"
    ufw status 2>/dev/null || true

elif command -v firewall-cmd >/dev/null 2>&1; then

    echo "Firewalld status:"
    firewall-cmd --state 2>/dev/null || true

    echo
    echo "Open services:"
    firewall-cmd --list-services 2>/dev/null || true

    echo
    echo "Open ports:"
    firewall-cmd --list-ports 2>/dev/null || true

else

    echo "No recognized firewall utility detected."

fi

check INFO "Firewall printing access requires review."

# ==========================================================
# PACKAGE AUDIT
# ==========================================================

section "[13] PRINTING PACKAGE INVENTORY"

PACKAGES=(
    cups
    cups-client
    cups-browsed
    cups-filters
    cups-pdf
    avahi-daemon
    sane
    sane-utils
    system-config-printer
    ipp-usb
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

check INFO "Printing package inventory completed."

# ==========================================================
# REPORT GENERATION
# ==========================================================

section "[14] GENERATING REPORT"

{
    echo "CYBERPATRIOT PRINT SERVICES SECURITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Date: $(date)"

    echo
    echo "PRINTING SERVICES"

    for SERVICE in "${PRINT_SERVICES[@]}"; do
        systemctl status "$SERVICE" --no-pager 2>/dev/null || true
    done

    echo
    echo "PRINTER QUEUES"

    lpstat -p -d 2>/dev/null || true
    lpstat -v 2>/dev/null || true

    echo
    echo "CUPS CONFIGURATION"

    cat "$CUPS_CONFIG" 2>/dev/null || true

    echo
    echo "NETWORK LISTENERS"

    ss -lntup 2>/dev/null |
        grep -E ':(631|515|9100|5353)([[:space:]]|$)' || true

    echo
    echo "FIREWALL"

    ufw status 2>/dev/null || true
    firewall-cmd --list-all 2>/dev/null || true

} > "$REPORT"

check PASS "Print services report generated."

# ==========================================================
# AUDIT SUMMARY
# ==========================================================

section "[15] AUDIT SUMMARY"

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Critical: $CRITICAL"
echo "Info:     $INFO"

echo
echo "Log: $LOG"
echo "Report: $REPORT"

log "Print services audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==========================================================
# INTERACTIVE MENU
# ==========================================================

section "[16] PRINT SERVICES MANAGEMENT MENU"

echo "1. Review CUPS status"
echo "2. Review printer queues"
echo "3. Review CUPS configuration"
echo "4. Review network printing listeners"
echo "5. Review Avahi status"
echo "6. Review scanner services"
echo "7. Back up printing configurations"
echo "8. View audit report"
echo "0. Exit"

echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)
        systemctl status cups --no-pager 2>/dev/null ||
            echo "CUPS unavailable."
        ;;

    2)
        lpstat -t 2>/dev/null ||
            echo "Printer utilities unavailable."
        ;;

    3)
        cat "$CUPS_CONFIG" 2>/dev/null ||
            echo "CUPS configuration unavailable."
        ;;

    4)
        ss -lntup 2>/dev/null |
            grep -E ':(631|515|9100|5353)([[:space:]]|$)' ||
            echo "No matching listeners found."
        ;;

    5)
        systemctl status avahi-daemon --no-pager 2>/dev/null ||
            echo "Avahi unavailable."
        ;;

    6)
        systemctl status saned --no-pager 2>/dev/null ||
            echo "SANED unavailable."
        ;;

    7)

        for DIR in /etc/cups /etc/avahi /etc/sane.d; do

            [[ -d "$DIR" ]] || continue

            NAME="$(basename "$DIR")"

            tar -czf \
                "$BACKUP_DIR/${NAME}_$(date +%Y%m%d_%H%M%S).tar.gz" \
                -C /etc "$NAME"

            echo "Backed up: $DIR"

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
echo "        PRINT SERVICES AUDIT COMPLETED"
echo "=================================================="

echo "Log: $LOG"
echo "Report: $REPORT"

log "Print services session completed."

exit 0


#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL SERVICE MANAGEMENT
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/service_management.log"

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

# ==================================================
# SYSTEMD DETECTION
# ==================================================

echo "=============================================="
echo "    CYBERPATRIOT SERVICE MANAGEMENT AUDIT"
echo "=============================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo

if ! command -v systemctl >/dev/null 2>&1; then
    echo "ERROR: systemctl is unavailable."
    echo "This script requires a systemd-based system."
    exit 1
fi

if ! systemctl is-system-running >/dev/null 2>&1; then
    echo "[INFO] System may be running in degraded or container mode."
fi

# ==================================================
# SERVICE INVENTORY
# ==================================================

echo "[1] RUNNING SERVICES"
echo "----------------------------------------------"

RUNNING_SERVICES="$(systemctl list-units \
    --type=service \
    --state=running \
    --no-legend \
    --no-pager 2>/dev/null)"

if [[ -n "$RUNNING_SERVICES" ]]; then
    echo "$RUNNING_SERVICES"
    check INFO "Running service inventory collected."
else
    check WARNING "No running services detected or systemd unavailable."
fi

echo

# ==================================================
# ENABLED SERVICE INVENTORY
# ==================================================

echo "[2] ENABLED SERVICES"
echo "----------------------------------------------"

ENABLED_SERVICES="$(systemctl list-unit-files \
    --type=service \
    --state=enabled \
    --no-legend \
    --no-pager 2>/dev/null)"

if [[ -n "$ENABLED_SERVICES" ]]; then
    echo "$ENABLED_SERVICES"
    check INFO "Enabled service inventory collected."
else
    check INFO "No enabled services found."
fi

echo

# ==================================================
# LISTENING PORT AUDIT
# ==================================================

echo "[3] LISTENING NETWORK PORTS"
echo "----------------------------------------------"

if command -v ss >/dev/null 2>&1; then

    LISTENING="$(ss -tulpen 2>/dev/null)"

    if [[ -n "$LISTENING" ]]; then
        echo "$LISTENING"
        check INFO "Listening network sockets collected."
    else
        check INFO "No listening sockets detected."
    fi

elif command -v netstat >/dev/null 2>&1; then

    netstat -tulpen 2>/dev/null
    check INFO "Listening sockets collected using netstat."

else
    check WARNING "Neither ss nor netstat is installed."
fi

echo

# ==================================================
# COMMON SERVICE AUDIT
# ==================================================

echo "[4] COMMON SERVICE SECURITY AUDIT"
echo "----------------------------------------------"

# These services are worth reviewing, not automatically
# disabling. Their names differ between distributions.

SERVICE_NAMES=(
    "telnet.socket"
    "telnet.service"
    "vsftpd.service"
    "proftpd.service"
    "pure-ftpd.service"
    "tftp.service"
    "tftp.socket"
    "cups.service"
    "avahi-daemon.service"
    "rpcbind.service"
    "nfs-server.service"
    "smb.service"
    "smbd.service"
    "nmb.service"
    "postfix.service"
    "dovecot.service"
    "apache2.service"
    "httpd.service"
    "mysql.service"
    "mariadb.service"
    "sshd.service"
    "ssh.service"
)

for SERVICE in "${SERVICE_NAMES[@]}"; do

    LOAD_STATE="$(systemctl show "$SERVICE" \
        -p LoadState --value 2>/dev/null || true)"

    if [[ "$LOAD_STATE" != "loaded" ]]; then
        continue
    fi

    ACTIVE_STATE="$(systemctl show "$SERVICE" \
        -p ActiveState --value 2>/dev/null || true)"

    ENABLE_STATE="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

    echo
    echo "Service: $SERVICE"
    echo "Status: $ACTIVE_STATE"
    echo "Enabled: $ENABLE_STATE"

    case "$SERVICE" in
        telnet*|tftp*)
            if [[ "$ACTIVE_STATE" == "active" ]]; then
                check CRITICAL "$SERVICE is active. Review necessity."
            else
                check INFO "$SERVICE detected but not active."
            fi
            ;;
        *)
            check INFO "$SERVICE inventory recorded."
            ;;
    esac

done

echo

# ==================================================
# FAILED SERVICE AUDIT
# ==================================================

echo "[5] FAILED SERVICES"
echo "----------------------------------------------"

FAILED_SERVICES="$(systemctl --failed \
    --type=service \
    --no-legend \
    --no-pager 2>/dev/null)"

if [[ -z "$FAILED_SERVICES" ]]; then
    check PASS "No failed services detected."
else
    echo "$FAILED_SERVICES"
    check WARNING "Failed services detected. Review their logs."
fi

echo

# ==================================================
# SERVICE SECURITY DETAILS
# ==================================================

echo "[6] SERVICE CONFIGURATION AUDIT"
echo "----------------------------------------------"

for SERVICE in "${SERVICE_NAMES[@]}"; do

    LOAD_STATE="$(systemctl show "$SERVICE" \
        -p LoadState --value 2>/dev/null || true)"

    [[ "$LOAD_STATE" == "loaded" ]] || continue

    FRAGMENT="$(systemctl show "$SERVICE" \
        -p FragmentPath --value 2>/dev/null || true)"

    if [[ -n "$FRAGMENT" && -f "$FRAGMENT" ]]; then

        OWNER="$(stat -c '%U' "$FRAGMENT" 2>/dev/null)"

        if [[ "$OWNER" == "root" ]]; then
            check PASS "$SERVICE unit file owned by root."
        else
            check WARNING "$SERVICE unit file owned by $OWNER."
        fi

    fi

done

echo

# ==================================================
# SERVICE INVENTORY SAVE
# ==================================================

REPORT="$LOG_DIR/service_inventory_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "CYBERPATRIOT SERVICE INVENTORY"
    echo "OS: ${PRETTY_NAME:-Unknown}"
    echo "Date: $(date)"
    echo
    echo "RUNNING SERVICES"
    systemctl list-units --type=service --state=running --no-pager
    echo
    echo "ENABLED SERVICES"
    systemctl list-unit-files --type=service --state=enabled --no-pager
    echo
    echo "LISTENING PORTS"
    ss -tulpen 2>/dev/null || true
    echo
    echo "FAILED SERVICES"
    systemctl --failed --type=service --no-pager
} > "$REPORT"

check PASS "Service inventory saved to $REPORT."

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
echo "Inventory: $REPORT"

log "Service audit complete: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE SERVICE HARDENING
# ==================================================

echo
read -rp "Would you like to review service hardening options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "       SERVICE MANAGEMENT MENU"
echo "=============================================="
echo
echo "1. Stop a service temporarily."
echo "2. Disable a service at startup."
echo "3. Stop and disable a service."
echo "4. Review a service."
echo "5. Review listening ports."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

if [[ "$OPTION" == "0" ]]; then
    exit 0
fi

# ==================================================
# SERVICE VALIDATION
# ==================================================

validate_service() {

    local SERVICE="$1"

    if [[ ! "$SERVICE" =~ ^[a-zA-Z0-9_.@:-]+$ ]]; then
        echo "Invalid service name."
        return 1
    fi

    if ! systemctl list-unit-files "$SERVICE" \
        --no-legend 2>/dev/null | grep -Fq "$SERVICE"; then
        echo "Service not found."
        return 1
    fi

    return 0
}

# ==================================================
# SERVICE REMEDIATION
# ==================================================

case "$OPTION" in

    1)
        read -rp "Enter service name: " SERVICE

        if validate_service "$SERVICE"; then

            echo
            echo "WARNING: Stopping a service may affect applications."
            read -rp "Confirm stop of $SERVICE? (y/n): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then

                if systemctl stop "$SERVICE"; then
                    check PASS "$SERVICE stopped successfully."
                else
                    check WARNING "Could not stop $SERVICE."
                fi

            fi
        fi
        ;;

    2)
        read -rp "Enter service name: " SERVICE

        if validate_service "$SERVICE"; then

            echo
            echo "This prevents automatic startup."
            read -rp "Confirm disabling $SERVICE? (y/n): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then

                if systemctl disable "$SERVICE"; then
                    check PASS "$SERVICE disabled at startup."
                else
                    check WARNING "Could not disable $SERVICE."
                fi

            fi
        fi
        ;;

    3)
        read -rp "Enter service name: " SERVICE

        if validate_service "$SERVICE"; then

            echo
            echo "WARNING: This stops and disables the service."
            read -rp "Confirm both actions? (y/n): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then

                if systemctl disable --now "$SERVICE"; then
                    check PASS "$SERVICE stopped and disabled."
                else
                    check WARNING "Service hardening failed."
                fi

            fi
        fi
        ;;

    4)
        read -rp "Enter service name: " SERVICE

        if validate_service "$SERVICE"; then

            echo
            systemctl status "$SERVICE" --no-pager
            echo
            systemctl cat "$SERVICE" --no-pager

        fi
        ;;

    5)
        echo
        ss -tulpen 2>/dev/null || \
            netstat -tulpen 2>/dev/null || \
            echo "No socket inspection utility found."
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
echo "       FINAL SERVICE VERIFICATION"
echo "=============================================="

if [[ -n "${SERVICE:-}" ]] &&
   systemctl list-unit-files "$SERVICE" --no-legend 2>/dev/null |
   grep -Fq "$SERVICE"; then

    systemctl is-active "$SERVICE" 2>/dev/null || true
    systemctl is-enabled "$SERVICE" 2>/dev/null || true

fi

echo
echo "Service management process complete."
echo "Log: $LOG"

log "Service management session completed."

exit 0

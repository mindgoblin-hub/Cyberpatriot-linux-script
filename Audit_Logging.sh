
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL AUDIT LOGGING SECURITY
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/audit_logging.log"

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
# BACKUP FUNCTION
# ==================================================

backup_file() {
    local file="$1"

    [[ -f "$file" ]] || return 1

    local backup_dir="$LOG_DIR/logging_backups"
    mkdir -p "$backup_dir"

    local name
    name="$(echo "$file" | sed 's#/#_#g')"

    cp -a "$file" \
        "$backup_dir/${name}.$(date +%Y%m%d_%H%M%S)"
}

echo "=============================================="
echo "      CYBERPATRIOT AUDIT LOGGING AUDIT"
echo "=============================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Date: $(date)"
echo

# ==================================================
# LOGGING SERVICE AUDIT
# ==================================================

echo "[1] LOGGING SERVICE AUDIT"
echo "----------------------------------------------"

for SERVICE in rsyslog auditd systemd-journald; do

    LOAD_STATE="$(systemctl show "$SERVICE" \
        -p LoadState --value 2>/dev/null || true)"

    if [[ "$LOAD_STATE" != "loaded" ]]; then
        check INFO "$SERVICE is not installed or not available."
        continue
    fi

    ACTIVE="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"

    if [[ "$ACTIVE" == "active" ]]; then
        check PASS "$SERVICE is running."
    else
        check WARNING "$SERVICE is not running."
    fi

    ENABLED="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

    if [[ "$ENABLED" == "enabled" ]]; then
        check PASS "$SERVICE is enabled."
    else
        check INFO "$SERVICE startup state: $ENABLED"
    fi

done

echo

# ==================================================
# AUDITD CONFIGURATION
# ==================================================

echo "[2] AUDITD CONFIGURATION"
echo "----------------------------------------------"

if command -v auditctl >/dev/null 2>&1; then

    AUDIT_STATUS="$(auditctl -s 2>/dev/null || true)"

    if [[ -n "$AUDIT_STATUS" ]]; then
        echo "$AUDIT_STATUS"
        check PASS "Audit subsystem status retrieved."
    else
        check WARNING "Could not retrieve audit subsystem status."
    fi

    if echo "$AUDIT_STATUS" | grep -q 'enabled 2'; then
        check INFO "Audit rules are immutable until reboot."
    fi

    RULES="$(auditctl -l 2>/dev/null || true)"

    if [[ -n "$RULES" ]]; then
        echo
        echo "Active audit rules:"
        echo "$RULES"
        check PASS "Active audit rules found."
    else
        check WARNING "No active audit rules found or access unavailable."
    fi

else
    check WARNING "auditctl is not installed."
fi

echo

# ==================================================
# JOURNAL PERSISTENCE AUDIT
# ==================================================

echo "[3] SYSTEMD JOURNAL AUDIT"
echo "----------------------------------------------"

if command -v journalctl >/dev/null 2>&1; then

    STORAGE="$(journalctl --disk-usage 2>/dev/null || true)"

    if [[ -n "$STORAGE" ]]; then
        echo "$STORAGE"
        check PASS "Journal storage is accessible."
    else
        check WARNING "Could not retrieve journal storage information."
    fi

    if [[ -d /var/log/journal ]]; then
        check PASS "Persistent journal directory exists."
    else
        check WARNING "Persistent journal directory not found."
    fi

    JOURNAL_CONF="/etc/systemd/journald.conf"

    if [[ -f "$JOURNAL_CONF" ]]; then

        STORAGE_SETTING="$(grep -Ei \
            '^[[:space:]]*Storage=' "$JOURNAL_CONF" |
            tail -n 1 || true)"

        if [[ "$STORAGE_SETTING" == *"persistent"* ]]; then
            check PASS "Persistent journal storage configured."
        else
            check WARNING "Persistent journal storage is not explicitly configured."
        fi

    else
        check INFO "Default journald configuration file not found."
    fi

else
    check INFO "systemd journal tools unavailable."
fi

echo

# ==================================================
# AUTHENTICATION LOG AUDIT
# ==================================================

echo "[4] AUTHENTICATION LOG AUDIT"
echo "----------------------------------------------"

AUTH_LOGS=(
    "/var/log/auth.log"
    "/var/log/secure"
    "/var/log/messages"
    "/var/log/syslog"
)

FOUND_AUTH=0

for FILE in "${AUTH_LOGS[@]}"; do

    if [[ -f "$FILE" ]]; then

        ((FOUND_AUTH+=1))

        echo
        echo "File: $FILE"

        OWNER="$(stat -c '%U' "$FILE" 2>/dev/null)"
        MODE="$(stat -c '%a' "$FILE" 2>/dev/null)"

        echo "Owner: $OWNER"
        echo "Permissions: $MODE"

        if [[ "$OWNER" == "root" ]]; then
            check PASS "$FILE is owned by root."
        else
            check WARNING "$FILE is not owned by root."
        fi

        if [[ "$MODE" =~ ^[0-7]+$ ]] &&
           (( (8#$MODE & 8#007) == 0 )); then
            check PASS "$FILE is not accessible to other users."
        else
            check WARNING "$FILE permissions require review."
        fi

        if [[ -s "$FILE" ]]; then
            check PASS "$FILE contains log data."
        else
            check WARNING "$FILE is empty."
        fi

    fi

done

if ((FOUND_AUTH == 0)); then
    check WARNING "No standard authentication logs found."
fi

echo

# ==================================================
# LOG DIRECTORY AUDIT
# ==================================================

echo "[5] LOG DIRECTORY AUDIT"
echo "----------------------------------------------"

if [[ -d /var/log ]]; then

    OWNER="$(stat -c '%U' /var/log 2>/dev/null)"
    MODE="$(stat -c '%a' /var/log 2>/dev/null)"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "/var/log is owned by root."
    else
        check WARNING "/var/log is owned by $OWNER."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#002) == 0 )); then
        check PASS "/var/log is not world-writable."
    else
        check CRITICAL "/var/log is world-writable."
    fi

else
    check CRITICAL "/var/log directory missing."
fi

echo

# ==================================================
# LOG ROTATION AUDIT
# ==================================================

echo "[6] LOG ROTATION AUDIT"
echo "----------------------------------------------"

if command -v logrotate >/dev/null 2>&1; then

    check PASS "logrotate is installed."

    if [[ -f /etc/logrotate.conf ]]; then
        check PASS "Main logrotate configuration exists."

        if logrotate --debug /etc/logrotate.conf \
            >/dev/null 2>&1; then
            check PASS "Logrotate configuration parses successfully."
        else
            check WARNING "Logrotate configuration has errors."
        fi

    else
        check WARNING "Main logrotate configuration missing."
    fi

else
    check WARNING "logrotate is not installed."
fi

echo

# ==================================================
# FAILED LOGIN AUDIT
# ==================================================

echo "[7] FAILED LOGIN AUDIT"
echo "----------------------------------------------"

if command -v journalctl >/dev/null 2>&1; then

    echo "Recent authentication failures:"

    journalctl --since "24 hours ago" \
        --no-pager 2>/dev/null |
        grep -iE 'failed password|authentication failure|invalid user' |
        tail -n 15 || true

    check INFO "Recent journal authentication events reviewed."

elif command -v lastb >/dev/null 2>&1; then

    lastb -n 15 2>/dev/null || true
    check INFO "Failed login history reviewed."

else
    check INFO "Failed login reporting unavailable."
fi

echo

# ==================================================
# AUDIT RULE DIRECTORY
# ==================================================

echo "[8] AUDIT RULE FILES"
echo "----------------------------------------------"

if [[ -d /etc/audit/rules.d ]]; then

    RULE_FILES=()

    while IFS= read -r -d '' FILE; do
        RULE_FILES+=("$FILE")
    done < <(find /etc/audit/rules.d \
        -maxdepth 1 -type f -name '*.rules' -print0 2>/dev/null)

    if ((${#RULE_FILES[@]} > 0)); then

        check PASS "Audit rule files found."

        for FILE in "${RULE_FILES[@]}"; do
            OWNER="$(stat -c '%U' "$FILE" 2>/dev/null)"
            MODE="$(stat -c '%a' "$FILE" 2>/dev/null)"

            if [[ "$OWNER" == "root" ]]; then
                check PASS "$FILE owned by root."
            else
                check WARNING "$FILE owned by $OWNER."
            fi

            if [[ "$MODE" =~ ^[0-7]+$ ]] &&
               (( (8#$MODE & 8#022) == 0 )); then
                check PASS "$FILE not writable by group or others."
            else
                check WARNING "$FILE permissions need review."
            fi
        done

    else
        check WARNING "No audit rule files found."
    fi

else
    check INFO "Audit rules directory not present."
fi

echo

# ==================================================
# AUDIT SUMMARY
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

log "Audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE HARDENING
# ==================================================

echo
read -rp "Review logging hardening options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "         LOGGING HARDENING MENU"
echo "=============================================="
echo
echo "1. Enable persistent systemd journal storage."
echo "2. Start and enable auditd."
echo "3. Start and enable rsyslog."
echo "4. Review logging service status."
echo "5. Review recent authentication events."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)
        if ! command -v journalctl >/dev/null 2>&1; then
            echo "systemd journal unavailable."
            exit 1
        fi

        CONF="/etc/systemd/journald.conf"
        mkdir -p "$(dirname "$CONF")"

        if [[ -f "$CONF" ]]; then
            backup_file "$CONF" || {
                echo "Backup failed."
                exit 1
            }
        fi

        mkdir -p /var/log/journal

        if [[ -f "$CONF" ]]; then

            if grep -Eq '^[[:space:]]*Storage=' "$CONF"; then
                sed -i \
                    's/^[[:space:]]*Storage=.*/Storage=persistent/' \
                    "$CONF"
            else
                printf '\n[Journal]\nStorage=persistent\n' >> "$CONF"
            fi

        else
            printf '[Journal]\nStorage=persistent\n' > "$CONF"
        fi

        if systemd-tmpfiles --create --prefix /var/log/journal; then

            if systemctl restart systemd-journald; then
                check PASS "Persistent journal storage configured."
            else
                check WARNING "Could not restart journald."
            fi

        else
            check WARNING "Could not initialize journal directory."
        fi
        ;;

    2)
        if ! command -v auditctl >/dev/null 2>&1; then
            echo "auditd does not appear to be installed."
            echo "Install it using your distribution package manager."
            exit 1
        fi

        if systemctl enable --now auditd; then
            check PASS "auditd enabled and started."
        else
            check WARNING "Could not start auditd."
        fi
        ;;

    3)
        if ! systemctl list-unit-files rsyslog.service \
            --no-legend 2>/dev/null | grep -q rsyslog; then
            echo "rsyslog is not installed."
            echo "Install it using your distribution package manager."
            exit 1
        fi

        if systemctl enable --now rsyslog; then
            check PASS "rsyslog enabled and started."
        else
            check WARNING "Could not start rsyslog."
        fi
        ;;

    4)
        systemctl status auditd rsyslog systemd-journald \
            --no-pager 2>/dev/null || true
        ;;

    5)
        journalctl --since "24 hours ago" \
            --no-pager 2>/dev/null |
            grep -iE 'failed password|authentication failure|invalid user' |
            tail -n 30 || true
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
echo "       FINAL LOGGING VERIFICATION"
echo "=============================================="

for SERVICE in auditd rsyslog systemd-journald; do

    if systemctl list-unit-files "$SERVICE.service" \
        --no-legend 2>/dev/null | grep -q "$SERVICE"; then

        STATUS="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
        echo "$SERVICE: $STATUS"

    fi

done

echo
echo "Audit logging process complete."
echo "Log: $LOG"

log "Audit logging session completed."

exit 0

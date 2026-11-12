
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL CRON SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/cron_security.log"

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

    local FILE="$1"

    [[ -f "$FILE" ]] || return 1

    local BACKUP_DIR="$LOG_DIR/cron_backups"
    mkdir -p "$BACKUP_DIR"

    local NAME
    NAME="$(echo "$FILE" | sed 's#/#_#g')"

    cp -a "$FILE" \
        "$BACKUP_DIR/${NAME}.$(date +%Y%m%d_%H%M%S)"
}

echo "=============================================="
echo "       CYBERPATRIOT CRON SECURITY AUDIT"
echo "=============================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Date: $(date)"
echo

# ==================================================
# CRON SERVICE AUDIT
# ==================================================

echo "[1] CRON SERVICE STATUS"
echo "----------------------------------------------"

CRON_SERVICES=(
    cron.service
    crond.service
)

FOUND_CRON=0

for SERVICE in "${CRON_SERVICES[@]}"; do

    LOAD_STATE="$(systemctl show "$SERVICE" \
        -p LoadState --value 2>/dev/null || true)"

    [[ "$LOAD_STATE" == "loaded" ]] || continue

    ((FOUND_CRON+=1))

    ACTIVE="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
    ENABLED="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

    echo "$SERVICE"
    echo "Status: $ACTIVE"
    echo "Enabled: $ENABLED"

    if [[ "$ACTIVE" == "active" ]]; then
        check PASS "$SERVICE is running."
    else
        check INFO "$SERVICE is not running."
    fi

done

if ((FOUND_CRON == 0)); then
    check INFO "No standard cron service detected."
fi

echo

# ==================================================
# SYSTEM CRONTAB AUDIT
# ==================================================

echo "[2] SYSTEM CRONTAB"
echo "----------------------------------------------"

if [[ -f /etc/crontab ]]; then

    cat /etc/crontab

    OWNER="$(stat -c '%U' /etc/crontab)"
    MODE="$(stat -c '%a' /etc/crontab)"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "/etc/crontab owned by root."
    else
        check CRITICAL "/etc/crontab owned by $OWNER."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "/etc/crontab is not writable by group or others."
    else
        check CRITICAL "/etc/crontab has unsafe write permissions."
    fi

else
    check INFO "/etc/crontab does not exist."
fi

echo

# ==================================================
# CRON DIRECTORIES
# ==================================================

echo "[3] SYSTEM CRON DIRECTORIES"
echo "----------------------------------------------"

CRON_DIRS=(
    /etc/cron.d
    /etc/cron.hourly
    /etc/cron.daily
    /etc/cron.weekly
    /etc/cron.monthly
)

for DIR in "${CRON_DIRS[@]}"; do

    [[ -d "$DIR" ]] || continue

    echo
    echo "Directory: $DIR"

    OWNER="$(stat -c '%U' "$DIR")"
    MODE="$(stat -c '%a' "$DIR")"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "$DIR owned by root."
    else
        check CRITICAL "$DIR owned by $OWNER."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "$DIR not writable by group or others."
    else
        check CRITICAL "$DIR has unsafe permissions."
    fi

    find "$DIR" -maxdepth 1 -type f -print 2>/dev/null

    while IFS= read -r -d '' FILE; do

        FILE_OWNER="$(stat -c '%U' "$FILE")"
        FILE_MODE="$(stat -c '%a' "$FILE")"

        if [[ "$FILE_OWNER" != "root" ]]; then
            check WARNING "$FILE owned by $FILE_OWNER."
        fi

        if [[ "$FILE_MODE" =~ ^[0-7]+$ ]] &&
           (( (8#$FILE_MODE & 8#022) != 0 )); then
            check CRITICAL "$FILE writable by group or others."
        fi

    done < <(find "$DIR" -maxdepth 1 -type f -print0 2>/dev/null)

done

echo

# ==================================================
# USER CRONTAB AUDIT
# ==================================================

echo "[4] USER CRONTAB AUDIT"
echo "----------------------------------------------"

if command -v crontab >/dev/null 2>&1; then

    while IFS=: read -r USERNAME PASSWORD UID GID COMMENT HOME SHELL; do

        [[ -n "$USERNAME" ]] || continue

        CRONTAB_OUTPUT="$(crontab -u "$USERNAME" -l 2>/dev/null || true)"

        if [[ -n "$CRONTAB_OUTPUT" ]]; then

            echo
            echo "User: $USERNAME"
            echo "$CRONTAB_OUTPUT"

            check INFO "Crontab found for $USERNAME."

        fi

    done < /etc/passwd

else
    check INFO "crontab command unavailable."
fi

echo

# ==================================================
# CRON ACCESS CONTROL
# ==================================================

echo "[5] CRON ACCESS CONTROL"
echo "----------------------------------------------"

for FILE in /etc/cron.allow /etc/cron.deny; do

    if [[ -f "$FILE" ]]; then

        echo
        echo "$FILE"
        cat "$FILE"

        OWNER="$(stat -c '%U' "$FILE")"
        MODE="$(stat -c '%a' "$FILE")"

        if [[ "$OWNER" == "root" ]]; then
            check PASS "$FILE owned by root."
        else
            check WARNING "$FILE owned by $OWNER."
        fi

        if [[ "$MODE" =~ ^[0-7]+$ ]] &&
           (( (8#$MODE & 8#022) == 0 )); then
            check PASS "$FILE is not writable by group or others."
        else
            check CRITICAL "$FILE has unsafe permissions."
        fi

    fi

done

if [[ ! -f /etc/cron.allow ]]; then
    check INFO "/etc/cron.allow is absent; review distribution access defaults."
fi

echo

# ==================================================
# WORLD-WRITABLE CRON FILE AUDIT
# ==================================================

echo "[6] WORLD-WRITABLE CRON FILES"
echo "----------------------------------------------"

WW_COUNT=0

for DIR in "${CRON_DIRS[@]}"; do

    [[ -d "$DIR" ]] || continue

    while IFS= read -r -d '' FILE; do

        ((WW_COUNT+=1))
        check CRITICAL "World-writable cron object: $FILE"

    done < <(find "$DIR" -xdev -perm -0002 -print0 2>/dev/null)

done

if ((WW_COUNT == 0)); then
    check PASS "No world-writable cron objects found."
fi

echo

# ==================================================
# SYSTEMD TIMER AUDIT
# ==================================================

echo "[7] SYSTEMD TIMER AUDIT"
echo "----------------------------------------------"

if command -v systemctl >/dev/null 2>&1; then

    TIMERS="$(systemctl list-timers --all --no-pager 2>/dev/null || true)"

    if [[ -n "$TIMERS" ]]; then
        echo "$TIMERS"
        check INFO "Systemd timer inventory collected."
    else
        check INFO "No systemd timers detected."
    fi

else
    check INFO "Systemd unavailable."
fi

echo

# ==================================================
# AT SCHEDULER AUDIT
# ==================================================

echo "[8] AT SCHEDULER AUDIT"
echo "----------------------------------------------"

if command -v atq >/dev/null 2>&1; then

    AT_JOBS="$(atq 2>/dev/null || true)"

    if [[ -n "$AT_JOBS" ]]; then
        echo "$AT_JOBS"
        check WARNING "Scheduled at jobs detected. Review authorization."
    else
        check PASS "No pending at jobs found."
    fi

else
    check INFO "at scheduler unavailable."
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
echo "Log: $LOG"

log "Cron audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE HARDENING
# ==================================================

echo
read -rp "Would you like to review cron remediation options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "          CRON SECURITY MENU"
echo "=============================================="
echo
echo "1. Review a user's crontab."
echo "2. Remove a specific user's crontab."
echo "3. Review a cron configuration file."
echo "4. Repair a cron directory's permissions."
echo "5. Review systemd timers."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)
        read -rp "Enter username: " USERNAME

        if ! getent passwd "$USERNAME" >/dev/null 2>&1; then
            echo "User does not exist."
            exit 1
        fi

        crontab -u "$USERNAME" -l 2>/dev/null || \
            echo "No crontab found for this user."
        ;;

    2)
        read -rp "Enter username: " USERNAME

        if ! getent passwd "$USERNAME" >/dev/null 2>&1; then
            echo "User does not exist."
            exit 1
        fi

        echo
        echo "WARNING: This removes all scheduled cron jobs for this user."
        echo "Review the crontab and save any required jobs first."

        read -rp "Confirm removal for $USERNAME? (y/n): " CONFIRM

        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then

            BACKUP_DIR="$LOG_DIR/cron_backups"
            mkdir -p "$BACKUP_DIR"

            if crontab -u "$USERNAME" -l \
                > "$BACKUP_DIR/${USERNAME}_crontab_$(date +%Y%m%d_%H%M%S)" \
                2>/dev/null; then

                echo "Crontab backup saved."

                if crontab -u "$USERNAME" -r; then
                    check PASS "Crontab removed for $USERNAME."
                else
                    check WARNING "Could not remove crontab."
                fi

            else
                echo "Could not back up crontab. No changes made."
                exit 1
            fi

        fi
        ;;

    3)
        read -rp "Enter full path to configuration file: " FILE

        case "$FILE" in
            /etc/crontab|/etc/cron.allow|/etc/cron.deny|/etc/cron.d/*)
                ;;
            *)
                echo "Path not allowed."
                exit 1
                ;;
        esac

        if [[ -f "$FILE" ]]; then
            echo
            stat "$FILE"
            echo
            cat "$FILE"
        else
            echo "File does not exist."
        fi
        ;;

    4)
        read -rp "Enter cron directory: " DIR

        case "$DIR" in
            /etc/cron.d|/etc/cron.hourly|/etc/cron.daily|/etc/cron.weekly|/etc/cron.monthly)
                ;;
            *)
                echo "Directory not allowed."
                exit 1
                ;;
        esac

        if [[ ! -d "$DIR" ]]; then
            echo "Directory does not exist."
            exit 1
        fi

        echo
        echo "This changes directory permissions only."
        echo "Requested mode: 755"

        read -rp "Confirm change? (y/n): " CONFIRM

        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            if chmod 755 "$DIR"; then
                check PASS "Permissions updated on $DIR."
            else
                check WARNING "Could not update directory permissions."
            fi
        fi
        ;;

    5)
        systemctl list-timers --all --no-pager
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
echo "       FINAL CRON VERIFICATION"
echo "=============================================="

for DIR in "${CRON_DIRS[@]}"; do

    if [[ -d "$DIR" ]]; then
        echo
        stat -c '%A %U:%G %n' "$DIR"
    fi

done

echo
echo "Cron security session completed."
echo "Log: $LOG"

log "Cron security session completed."

exit 0

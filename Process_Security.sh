
#!/bin/bash

# ==========================================================
# CYBERPATRIOT UNIVERSAL PROCESS SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$LOG_DIR/process_backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG="$LOG_DIR/process_security.log"
REPORT="$LOG_DIR/process_report_$(date +%Y%m%d_%H%M%S).txt"

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
echo "        CYBERPATRIOT PROCESS SECURITY AUDIT"
echo "=================================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"

# ==========================================================
# RUNNING PROCESS INVENTORY
# ==========================================================

section "[1] RUNNING PROCESS INVENTORY"

PROCESS_REPORT="$LOG_DIR/process_inventory_$(date +%Y%m%d_%H%M%S).txt"

ps -eo user,pid,ppid,stat,%cpu,%mem,etime,comm,args \
    --sort=-%cpu > "$PROCESS_REPORT"

echo "Top running processes:"
ps -eo user,pid,ppid,stat,%cpu,%mem,comm \
    --sort=-%cpu | head -n 21

check PASS "Running process inventory collected."

# ==========================================================
# ROOT PROCESS AUDIT
# ==========================================================

section "[2] ROOT-OWNED PROCESSES"

ROOT_COUNT="$(ps -eo user= | awk '$1=="root"{count++} END{print count+0}')"

echo "Number of root-owned processes: $ROOT_COUNT"

ps -eo user,pid,ppid,stat,comm,args |
    awk '$1=="root"' |
    head -n 50

check INFO "Root-owned processes reviewed."

# ==========================================================
# TEMPORARY DIRECTORY EXECUTION
# ==========================================================

section "[3] TEMPORARY DIRECTORY EXECUTION AUDIT"

TEMP_REPORT="$LOG_DIR/temp_processes_$(date +%Y%m%d_%H%M%S).txt"

ps -eo pid,user,args --no-headers |
    grep -E '/tmp/|/var/tmp/|/dev/shm/' |
    grep -v grep > "$TEMP_REPORT" || true

if [[ -s "$TEMP_REPORT" ]]; then

    cat "$TEMP_REPORT"

    check WARNING "Processes referencing temporary directories found. Review manually."

else

    check PASS "No processes referencing common temporary directories found."

fi

# ==========================================================
# EXECUTABLE PATH AUDIT
# ==========================================================

section "[4] PROCESS EXECUTABLE PATH AUDIT"

UNUSUAL_REPORT="$LOG_DIR/unusual_processes_$(date +%Y%m%d_%H%M%S).txt"

for PROC in /proc/[0-9]*; do

    [[ -d "$PROC" ]] || continue

    PID="${PROC##*/}"

    EXE="$(readlink "$PROC/exe" 2>/dev/null || true)"

    [[ -n "$EXE" ]] || continue

    case "$EXE" in

        /tmp/*|/var/tmp/*|/dev/shm/*|/home/*|/run/user/*)

            echo "PID: $PID EXECUTABLE: $EXE" |
                tee -a "$UNUSUAL_REPORT"

            ;;

    esac

done

if [[ -s "$UNUSUAL_REPORT" ]]; then

    check WARNING "Processes executing from unusual locations detected."

else

    check PASS "No executables found in the audited unusual locations."

fi

# ==========================================================
# ZOMBIE PROCESS AUDIT
# ==========================================================

section "[5] ZOMBIE PROCESS AUDIT"

ZOMBIE_COUNT="$(ps -eo stat= | awk '$1 ~ /^Z/{count++} END{print count+0}')"

echo "Zombie processes: $ZOMBIE_COUNT"

if (( ZOMBIE_COUNT > 0 )); then

    ps -eo pid,ppid,user,stat,comm |
        awk '$4 ~ /^Z/'

    check WARNING "Zombie processes detected."

else

    check PASS "No zombie processes detected."

fi

# ==========================================================
# PROCESS CAPABILITIES
# ==========================================================

section "[6] PROCESS CAPABILITY AUDIT"

if command -v getpcaps >/dev/null 2>&1; then

    echo "Processes with capabilities:"

    for PROC in /proc/[0-9]*; do

        PID="${PROC##*/}"

        getpcaps "$PID" 2>/dev/null

    done | grep -v '=(empty)' | head -n 50

    check INFO "Process capabilities reviewed."

else

    echo "getpcaps unavailable."

    if command -v capsh >/dev/null 2>&1; then
        capsh --print 2>/dev/null || true
    fi

    check INFO "Install libcap utilities to inspect process capabilities."

fi

# ==========================================================
# NETWORK LISTENERS
# ==========================================================

section "[7] NETWORK LISTENING PROCESSES"

if command -v ss >/dev/null 2>&1; then

    ss -lntup 2>/dev/null

    echo
    echo "Listening TCP and UDP ports:"

    ss -lntup 2>/dev/null |
        awk 'NR==1 || NR>1'

    check INFO "Network listening processes reviewed."

else

    check WARNING "ss utility unavailable."

fi

# ==========================================================
# PROCESS RESOURCE AUDIT
# ==========================================================

section "[8] PROCESS RESOURCE USAGE"

echo "Top CPU consumers:"

ps -eo pid,user,%cpu,%mem,comm \
    --sort=-%cpu | head -n 11

echo
echo "Top memory consumers:"

ps -eo pid,user,%mem,%cpu,comm \
    --sort=-%mem | head -n 11

check INFO "Process resource consumption reviewed."

# ==========================================================
# PROCESS STARTUP AUDIT
# ==========================================================

section "[9] PROCESS STARTUP SERVICES"

if command -v systemctl >/dev/null 2>&1; then

    echo "Running system services:"

    systemctl list-units --type=service --state=running \
        --no-pager --no-legend 2>/dev/null |
        head -n 50

    echo
    echo "Enabled services:"

    systemctl list-unit-files --type=service --state=enabled \
        --no-pager --no-legend 2>/dev/null |
        head -n 50

    check INFO "System service startup configuration reviewed."

else

    check INFO "systemctl unavailable."

fi

# ==========================================================
# USER PROCESS AUDIT
# ==========================================================

section "[10] USER PROCESS AUDIT"

for USER_HOME in /home/*; do

    [[ -d "$USER_HOME" ]] || continue

    USERNAME="$(basename "$USER_HOME")"

    COUNT="$(pgrep -u "$USERNAME" 2>/dev/null | wc -l)"

    echo "$USERNAME: $COUNT processes"

    ps -u "$USERNAME" -o pid,ppid,stat,comm \
        --no-headers 2>/dev/null | head -n 15

done

check INFO "User process inventory completed."

# ==========================================================
# PROCESS SECURITY UTILITIES
# ==========================================================

section "[11] PROCESS SECURITY TOOLS"

TOOLS=(
    ps
    pgrep
    pstree
    lsof
    ss
    getpcaps
    auditctl
    ausearch
)

for TOOL in "${TOOLS[@]}"; do

    if command -v "$TOOL" >/dev/null 2>&1; then

        echo "[AVAILABLE] $TOOL"

    else

        echo "[UNAVAILABLE] $TOOL"

    fi

done

check INFO "Process security utility inventory completed."

# ==========================================================
# PROCESS ENVIRONMENT AUDIT
# ==========================================================

section "[12] PROCESS ENVIRONMENT"

echo "System uptime:"
uptime

echo
echo "System load:"
cat /proc/loadavg

echo
echo "Process limits:"

ulimit -a

check INFO "Process environment reviewed."

# ==========================================================
# REPORT GENERATION
# ==========================================================

section "[13] GENERATING REPORT"

{
    echo "CYBERPATRIOT PROCESS SECURITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Date: $(date)"

    echo
    echo "RUNNING PROCESSES"

    cat "$PROCESS_REPORT"

    echo
    echo "TEMPORARY DIRECTORY PROCESSES"

    cat "$TEMP_REPORT" 2>/dev/null || true

    echo
    echo "UNUSUAL EXECUTABLE LOCATIONS"

    cat "$UNUSUAL_REPORT" 2>/dev/null || true

    echo
    echo "ZOMBIE PROCESSES"

    ps -eo pid,ppid,user,stat,comm |
        awk '$4 ~ /^Z/'

    echo
    echo "NETWORK LISTENERS"

    ss -lntup 2>/dev/null || true

    echo
    echo "RUNNING SERVICES"

    systemctl list-units --type=service --state=running \
        --no-pager 2>/dev/null || true

    echo
    echo "SYSTEM LOAD"

    uptime

    echo
    echo "PROCESS AUDIT LOG"

    cat "$LOG"

} > "$REPORT"

check PASS "Process security report generated."

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

log "Process audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==========================================================
# INTERACTIVE MENU
# ==========================================================

section "[15] PROCESS SECURITY MENU"

echo "1. Review all running processes."
echo "2. Review root-owned processes."
echo "3. Review temporary directory processes."
echo "4. Review unusual executable paths."
echo "5. Review zombie processes."
echo "6. Review network listeners."
echo "7. Review top CPU processes."
echo "8. Review top memory processes."
echo "9. Review running system services."
echo "10. View complete audit report."
echo "11. Back up audit reports."
echo "0. Exit."

echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)

        cat "$PROCESS_REPORT"

        ;;

    2)

        ps -eo user,pid,ppid,stat,comm,args |
            awk '$1=="root"'

        ;;

    3)

        cat "$TEMP_REPORT"

        ;;

    4)

        cat "$UNUSUAL_REPORT"

        ;;

    5)

        ps -eo pid,ppid,user,stat,comm |
            awk '$4 ~ /^Z/'

        ;;

    6)

        ss -lntup 2>/dev/null ||
            echo "ss unavailable."

        ;;

    7)

        ps -eo pid,user,%cpu,%mem,comm \
            --sort=-%cpu | head -n 21

        ;;

    8)

        ps -eo pid,user,%mem,%cpu,comm \
            --sort=-%mem | head -n 21

        ;;

    9)

        systemctl list-units --type=service --state=running \
            --no-pager

        ;;

    10)

        cat "$REPORT"

        ;;

    11)

        tar -czf \
            "$BACKUP_DIR/process_reports_$(date +%Y%m%d_%H%M%S).tar.gz" \
            -C "$LOG_DIR" \
            "$(basename "$REPORT")" \
            "$(basename "$PROCESS_REPORT")" \
            "$(basename "$LOG")"

        echo "Reports backed up."

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
echo "        PROCESS SECURITY AUDIT COMPLETED"
echo "=================================================="

echo "Log: $LOG"
echo "Report: $REPORT"

log "Process security session completed."

exit 0

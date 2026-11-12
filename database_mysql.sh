
#!/bin/bash

# CyberPatriot MySQL / MariaDB Security Auditor
# Multi-distro Linux support

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/mysql_audit.log"

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

PASS=0
WARN=0

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

check() {
    if [[ "$2" == "PASS" ]]; then
        ((PASS+=1))
        log "[PASS] $1"
    else
        ((WARN+=1))
        log "[WARNING] $1"
    fi
}

echo "========================================"
echo " CYBERPATRIOT MYSQL SECURITY AUDIT"
echo "========================================"
echo "OS: ${PRETTY_NAME:-Unknown}"
echo

if ! command -v mysql >/dev/null 2>&1; then
    echo "MySQL client not installed."
    exit 1
fi

SERVICE=""

for s in mysql mariadb mysqld; do
    if systemctl list-unit-files "$s.service" 2>/dev/null |
        grep -q "$s.service"; then
        SERVICE="$s"
        break
    fi
done

if [[ -z "$SERVICE" ]]; then
    echo "Could not identify MySQL service."
    exit 1
fi

echo "Detected service: $SERVICE"
echo

if systemctl is-active --quiet "$SERVICE"; then
    check "Database service is running" PASS
else
    check "Database service is not running" WARN
fi

echo
echo "Checking MySQL configuration files..."

CONFIG_FILES=()

for f in /etc/my.cnf \
         /etc/mysql/my.cnf \
         /etc/mysql/mysql.conf.d/*.cnf \
         /etc/mysql/conf.d/*.cnf \
         /etc/my.cnf.d/*.cnf; do
    [[ -f "$f" ]] && CONFIG_FILES+=("$f")
done

if ((${#CONFIG_FILES[@]} == 0)); then
    echo "No standard configuration files found."
else
    check "MySQL configuration files found" PASS
fi

if grep -hRiE '^[[:space:]]*local_infile[[:space:]]*=[[:space:]]*0' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "Local file loading disabled in configuration" PASS
else
    check "Local file loading restriction not found" WARN
fi

if grep -hRiE '^[[:space:]]*symbolic-links[[:space:]]*=[[:space:]]*0|^[[:space:]]*skip-symbolic-links' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "Symbolic links disabled in configuration" PASS
else
    check "Symbolic link restriction not found" WARN
fi

echo
echo "Checking database account security..."
echo "Attempting local database audit using existing credentials."
echo

if DB_OUTPUT=$(mysql --connect-timeout=5 --batch --skip-column-names -e "
SELECT User, Host
FROM mysql.user
WHERE User = '';
" 2>/dev/null); then

    if [[ -z "$DB_OUTPUT" ]]; then
        check "No anonymous database accounts found" PASS
    else
        check "Anonymous database accounts detected" WARN
        echo "$DB_OUTPUT"
    fi

    ROOT_OUTPUT=$(mysql --connect-timeout=5 --batch --skip-column-names -e "
SELECT User, Host
FROM mysql.user
WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
" 2>/dev/null || true)

    if [[ -z "$ROOT_OUTPUT" ]]; then
        check "No externally defined root accounts found" PASS
    else
        check "Root accounts with non-local hosts found" WARN
        echo "$ROOT_OUTPUT"
    fi

else
    check "Database account audit unavailable (authentication required)" WARN
    echo "Configure MySQL credentials before running account audits."
fi

echo
echo "========================================"
echo " AUDIT SUMMARY"
echo "========================================"
echo "Passed: $PASS"
echo "Warnings: $WARN"
echo "Log: $LOG"
echo

read -rp "Apply recommended MySQL configuration hardening? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

# Select a configuration directory that is already included
# in the server configuration.

if [[ -d /etc/mysql/conf.d ]]; then
    CONF_DIR="/etc/mysql/conf.d"
elif [[ -d /etc/mysql/mysql.conf.d ]]; then
    CONF_DIR="/etc/mysql/mysql.conf.d"
elif [[ -d /etc/my.cnf.d ]]; then
    CONF_DIR="/etc/my.cnf.d"
else
    echo "No recognized MySQL configuration directory found."
    echo "No changes made."
    exit 1
fi

TARGET="$CONF_DIR/zz-cyberpatriot-hardening.cnf"
BACKUP=""

if [[ -f "$TARGET" ]]; then
    BACKUP="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
    cp -a "$TARGET" "$BACKUP" || exit 1
fi

cat > "$TARGET" <<'EOF'
# CyberPatriot MySQL security settings

[mysqld]
local_infile=0
symbolic-links=0
EOF

echo
echo "Configuration file created: $TARGET"
echo
echo "The following settings were added:"
echo "- local_infile=0"
echo "- symbolic-links=0"
echo
echo "These settings require a database restart to take effect."
echo "Review application compatibility before restarting."

log "MySQL hardening configuration written to $TARGET"

if [[ -n "$BACKUP" ]]; then
    echo "Previous configuration backup: $BACKUP"
fi

echo
echo "Verify configuration and schedule a maintenance restart."
echo "No database accounts or passwords were modified."
echo "MySQL hardening process complete."

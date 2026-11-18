#!/bin/bash

# CyberPatriot MySQL / MariaDB Security Auditor + Hardener
# Multi-distro Linux support
#
# Checks:
#   - local_infile disabled
#   - symbolic links disabled
#   - anonymous accounts
#   - externally accessible root accounts
#   - SSL/TLS status
#   - authentication plugin / weak auth where query access permits
#   - secure file privileges
#
# IMPORTANT:
# This script intentionally does not blindly change database accounts,
# passwords, grants, or TLS certificates.

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"
mkdir -p "$LOG_DIR" "$BACKUP_DIR"
LOG="$LOG_DIR/mysql_audit.log"

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

PASS=0
WARN=0
INFO=0

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

check() {
    local message="$1"
    local status="$2"

    case "$status" in
        PASS)
            ((PASS+=1))
            log "[PASS] $message"
            ;;
        WARN)
            ((WARN+=1))
            log "[WARNING] $message"
            ;;
        INFO)
            ((INFO+=1))
            log "[INFO] $message"
            ;;
    esac
}

echo "========================================"
echo " CYBERPATRIOT MYSQL/MARIADB AUDITOR"
echo "========================================"
echo "OS: ${PRETTY_NAME:-Unknown}"
echo

# ------------------------------------------------------------
# Detect service
# ------------------------------------------------------------

SERVICE=""

for s in mysql mariadb mysqld; do
    if systemctl list-unit-files "$s.service" 2>/dev/null |
        grep -q "^${s}.service"; then
        SERVICE="$s"
        break
    fi
done

if [[ -z "$SERVICE" ]]; then
    echo "Could not identify MySQL/MariaDB service."
    exit 1
fi

echo "Detected service: $SERVICE"

if systemctl is-active --quiet "$SERVICE"; then
    check "Database service is running" PASS
else
    check "Database service is running" WARN
fi

# ------------------------------------------------------------
# Find client
# ------------------------------------------------------------

MYSQL_BIN=""

for candidate in mysql mariadb; do
    if command -v "$candidate" >/dev/null 2>&1; then
        MYSQL_BIN="$(command -v "$candidate")"
        break
    fi
done

if [[ -z "$MYSQL_BIN" ]]; then
    check "MySQL/MariaDB client installed" WARN
    exit 1
else
    check "MySQL/MariaDB client installed" PASS
fi

# ------------------------------------------------------------
# Configuration discovery
# ------------------------------------------------------------

CONFIG_FILES=()

for f in \
    /etc/my.cnf \
    /etc/mysql/my.cnf \
    /etc/mysql/mysql.conf.d/*.cnf \
    /etc/mysql/conf.d/*.cnf \
    /etc/my.cnf.d/*.cnf; do
    [[ -f "$f" ]] && CONFIG_FILES+=("$f")
done

if ((${#CONFIG_FILES[@]} > 0)); then
    check "MySQL/MariaDB configuration files found" PASS
else
    check "MySQL/MariaDB configuration files found" WARN
fi

# ------------------------------------------------------------
# Static configuration checks
# ------------------------------------------------------------

echo
echo "Checking configuration..."

if grep -hRiE '^[[:space:]]*local_infile[[:space:]]*=[[:space:]]*0([[:space:]]|$)' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "local_infile is disabled" PASS
else
    check "local_infile is disabled" WARN
fi

if grep -hRiE '^[[:space:]]*(skip-symbolic-links|symbolic-links[[:space:]]*=[[:space:]]*0)([[:space:]]|$)' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "Symbolic links are disabled" PASS
else
    check "Symbolic links are disabled" WARN
fi

if grep -hRiE '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*(127\.0\.0\.1|localhost)([[:space:]]|$)' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "Database bind address is localhost" PASS
else
    check "Database bind address is not restricted to localhost" WARN
fi

# ------------------------------------------------------------
# Live server variables
# ------------------------------------------------------------

QUERY_ACCESS=0

run_mysql() {
    "$MYSQL_BIN" --connect-timeout=5 --batch --skip-column-names -e "$1" 2>/dev/null
}

if run_mysql "SELECT 1;" >/dev/null 2>&1; then
    QUERY_ACCESS=1
    check "Database administrative query access available" PASS
else
    check "Database administrative query access available" WARN
    echo "Account-level checks require local MySQL/MariaDB credentials."
fi

if ((QUERY_ACCESS)); then

    LOCAL_INFILE="$(run_mysql "SHOW GLOBAL VARIABLES LIKE 'local_infile';" | awk '{print $2}')"
    if [[ "$LOCAL_INFILE" == "OFF" ]]; then
        check "Live local_infile setting is OFF" PASS
    else
        check "Live local_infile setting is OFF" WARN
    fi

    SSL_DISABLED="$(run_mysql "SHOW VARIABLES LIKE 'have_ssl';" | awk '{print $2}')"
    if [[ "$SSL_DISABLED" =~ ^YES$|^yes$ ]]; then
        check "MySQL/MariaDB SSL support is available" PASS
    else
        check "MySQL/MariaDB SSL support is available" WARN
    fi

    TLS_VERSION="$(run_mysql "SHOW VARIABLES LIKE 'tls_version';" | awk '{print $2}')"
    if [[ -n "$TLS_VERSION" ]]; then
        check "TLS version configuration is present" INFO
        echo "TLS versions: $TLS_VERSION"
    fi

    SSL_CIPHER="$(run_mysql "SHOW STATUS LIKE 'Ssl_cipher';" | awk '{print $2}')"
    if [[ -n "$SSL_CIPHER" && "$SSL_CIPHER" != "NULL" ]]; then
        check "Current administrative connection is using TLS" PASS
    else
        check "Current administrative connection is using TLS" WARN
    fi

    ANON="$(run_mysql "SELECT User,Host FROM mysql.user WHERE User='';")"
    if [[ -z "$ANON" ]]; then
        check "No anonymous database accounts found" PASS
    else
        check "Anonymous database accounts found" WARN
        echo "$ANON"
    fi

    REMOTE_ROOT="$(run_mysql "SELECT User,Host FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');")"
    if [[ -z "$REMOTE_ROOT" ]]; then
        check "No externally defined root accounts found" PASS
    else
        check "Externally defined root accounts found" WARN
        echo "$REMOTE_ROOT"
    fi

    EMPTY_AUTH="$(run_mysql "SELECT User,Host FROM mysql.user WHERE authentication_string='' OR authentication_string IS NULL;")"
    if [[ -z "$EMPTY_AUTH" ]]; then
        check "No database accounts with empty authentication strings found" PASS
    else
        check "Database accounts with empty authentication strings found" WARN
        echo "$EMPTY_AUTH"
    fi

    FILE_PRIV="$(run_mysql "SELECT User,Host FROM mysql.user WHERE File_priv='Y';")"
    if [[ -z "$FILE_PRIV" ]]; then
        check "No unexpected FILE privilege detected at global account level" PASS
    else
        check "Accounts with FILE privilege detected" WARN
        echo "$FILE_PRIV"
    fi

    SUPER_PRIV="$(run_mysql "SELECT User,Host FROM mysql.user WHERE Super_priv='Y' AND User NOT IN ('root');")"
    if [[ -z "$SUPER_PRIV" ]]; then
        check "No non-root global SUPER accounts detected" PASS
    else
        check "Non-root global SUPER accounts detected" WARN
        echo "$SUPER_PRIV"
    fi

fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo
echo "========================================"
echo " AUDIT SUMMARY"
echo "========================================"
echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Info:     $INFO"
echo "Log:      $LOG"
echo

read -rp "Apply safe MySQL/MariaDB configuration hardening? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

# ------------------------------------------------------------
# Select included configuration directory
# ------------------------------------------------------------

if [[ -d /etc/mysql/conf.d ]]; then
    CONF_DIR="/etc/mysql/conf.d"
elif [[ -d /etc/mysql/mysql.conf.d ]]; then
    CONF_DIR="/etc/mysql/mysql.conf.d"
elif [[ -d /etc/my.cnf.d ]]; then
    CONF_DIR="/etc/my.cnf.d"
else
    echo "No recognized MySQL/MariaDB configuration directory found."
    exit 1
fi

TARGET="$CONF_DIR/zz-cyberpatriot-hardening.cnf"
BACKUP_DIR="$BACKUP_DIR/mysql_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [[ -f "$TARGET" ]]; then
    cp -a "$TARGET" "$BACKUP_DIR/"
fi

cat > "$TARGET" <<'EOF'
# CyberPatriot MySQL/MariaDB safe hardening settings

[mysqld]
local_infile=0
symbolic-links=0
EOF

echo
echo "Created: $TARGET"
echo "Added:"
echo "  local_infile=0"
echo "  symbolic-links=0"
echo
echo "Backup: $BACKUP_DIR"

log "Safe MySQL/MariaDB hardening configuration written to $TARGET"

if systemctl restart "$SERVICE"; then
    echo
    echo "Database restarted successfully."

    if ((QUERY_ACCESS)); then
        LIVE="$(run_mysql "SHOW GLOBAL VARIABLES LIKE 'local_infile';" | awk '{print $2}')"
        if [[ "$LIVE" == "OFF" ]]; then
            check "local_infile remains OFF after restart" PASS
        else
            check "local_infile remains OFF after restart" WARN
        fi
    fi
else
    echo "WARNING: Database restart failed."
    echo "Review: $TARGET"
    echo "Backup: $BACKUP_DIR"
    exit 1
fi

echo
echo "MySQL/MariaDB hardening complete."
echo "No accounts, passwords, grants, or TLS certificates were modified."

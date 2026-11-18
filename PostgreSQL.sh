#!/bin/bash

# CyberPatriot PostgreSQL Security Auditor + Safe Hardener
# Multi-distro Linux support
#
# Checks:
#   - SSL enabled
#   - TCP authentication required
#   - hostssl / non-SSL TCP exposure
#   - password_encryption
#   - MD5 authentication rules
#   - listen_addresses
#   - connection/disconnection logging
#   - pg_hba.conf parse errors
#   - dangerous/broad trust rules
#   - login/superuser/passwordless roles
#   - PostgreSQL data/config permissions
#
# IMPORTANT:
# Authentication rules are NOT blindly rewritten. pg_hba.conf is order
# sensitive, and replacing authentication methods can lock out users/apps.

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_ROOT="$BASE_DIR/backups"
mkdir -p "$LOG_DIR" "$BACKUP_ROOT"
LOG="$LOG_DIR/postgresql_audit.log"

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
        PASS) ((PASS+=1)); log "[PASS] $message" ;;
        WARN) ((WARN+=1)); log "[WARNING] $message" ;;
        INFO) ((INFO+=1)); log "[INFO] $message" ;;
    esac
}

echo "========================================"
echo " CYBERPATRIOT POSTGRESQL AUDITOR"
echo "========================================"
echo "OS: ${PRETTY_NAME:-Unknown}"
echo

# ------------------------------------------------------------
# Service discovery
# ------------------------------------------------------------

SERVICE=""

mapfile -t SERVICES < <(
    systemctl list-unit-files --type=service --no-legend 2>/dev/null |
    awk '$1 ~ /^postgresql(@.*)?\.service$/ {sub(/\.service$/,"",$1); print $1}' |
    sort -u
)

for s in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$s"; then
        SERVICE="$s"
        break
    fi
done

if [[ -z "$SERVICE" && ${#SERVICES[@]} -gt 0 ]]; then
    SERVICE="${SERVICES[0]}"
fi

if [[ -z "$SERVICE" ]]; then
    for s in postgresql postgresql@14-main postgresql@15-main postgresql@16-main \
             postgresql@17-main postgresql@18-main; do
        if systemctl list-unit-files "$s.service" 2>/dev/null | grep -q "^$s.service"; then
            SERVICE="$s"
            break
        fi
    done
fi

if [[ -z "$SERVICE" ]]; then
    echo "Could not identify PostgreSQL service."
    exit 1
fi

echo "Detected service: $SERVICE"

if systemctl is-active --quiet "$SERVICE"; then
    check "PostgreSQL service is running" PASS
else
    check "PostgreSQL service is running" WARN
fi

# ------------------------------------------------------------
# psql
# ------------------------------------------------------------

PSQL="$(command -v psql 2>/dev/null || true)"

if [[ -z "$PSQL" ]]; then
    check "PostgreSQL client installed" WARN
    exit 1
else
    check "PostgreSQL client installed" PASS
fi

if ! id postgres >/dev/null 2>&1; then
    check "postgres operating-system account exists" WARN
    exit 1
fi

PGQUERY=(runuser -u postgres -- "$PSQL" -X -Atqc)

# ------------------------------------------------------------
# Discover configuration using PostgreSQL itself
# ------------------------------------------------------------

PG_CONFIG="$("${PGQUERY[@]}" "SHOW config_file;" 2>/dev/null | head -n1 || true)"
PG_HBA="$("${PGQUERY[@]}" "SHOW hba_file;" 2>/dev/null | head -n1 || true)"
PG_DATA="$("${PGQUERY[@]}" "SHOW data_directory;" 2>/dev/null | head -n1 || true)"

echo
echo "PostgreSQL configuration:"
echo "  postgresql.conf: ${PG_CONFIG:-Not found}"
echo "  pg_hba.conf:     ${PG_HBA:-Not found}"
echo "  data_directory:  ${PG_DATA:-Not found}"

[[ -f "$PG_CONFIG" ]] && check "postgresql.conf found" PASS || check "postgresql.conf found" WARN
[[ -f "$PG_HBA" ]] && check "pg_hba.conf found" PASS || check "pg_hba.conf found" WARN

# ------------------------------------------------------------
# Live settings
# ------------------------------------------------------------

echo
echo "Checking PostgreSQL security settings..."

SSL="$("${PGQUERY[@]}" "SHOW ssl;" 2>/dev/null | head -n1 || true)"
if [[ "$SSL" == "on" ]]; then
    check "PostgreSQL SSL is enabled" PASS
else
    check "PostgreSQL SSL is enabled" WARN
fi

PASSWORD_ENCRYPTION="$("${PGQUERY[@]}" "SHOW password_encryption;" 2>/dev/null | head -n1 || true)"
if [[ "$PASSWORD_ENCRYPTION" == "scram-sha-256" ]]; then
    check "password_encryption is scram-sha-256" PASS
else
    check "password_encryption is scram-sha-256" WARN
    echo "Current password_encryption: ${PASSWORD_ENCRYPTION:-unknown}"
fi

LISTEN="$("${PGQUERY[@]}" "SHOW listen_addresses;" 2>/dev/null | head -n1 || true)"
case "$LISTEN" in
    localhost|127.0.0.1|127.0.0.1,::1|::1)
        check "PostgreSQL listen_addresses is restricted to local interfaces" PASS
        ;;
    "")
        check "PostgreSQL listen_addresses could be determined" WARN
        ;;
    *)
        check "PostgreSQL listen_addresses is restricted" WARN
        echo "Current listen_addresses: $LISTEN"
        ;;
esac

LOG_CONNECTIONS="$("${PGQUERY[@]}" "SHOW log_connections;" 2>/dev/null | head -n1 || true)"
if [[ "$LOG_CONNECTIONS" == "on" ]]; then
    check "PostgreSQL connection logging is enabled" PASS
else
    check "PostgreSQL connection logging is enabled" WARN
fi

LOG_DISCONNECTIONS="$("${PGQUERY[@]}" "SHOW log_disconnections;" 2>/dev/null | head -n1 || true)"
if [[ "$LOG_DISCONNECTIONS" == "on" ]]; then
    check "PostgreSQL disconnection logging is enabled" PASS
else
    check "PostgreSQL disconnection logging is enabled" WARN
fi

# ------------------------------------------------------------
# pg_hba.conf analysis
# ------------------------------------------------------------

echo
echo "Checking pg_hba.conf..."

TRUST_RULES=""
MD5_RULES=""
HOST_RULES=""
NONSSL_HOST_RULES=""

if [[ -f "$PG_HBA" ]]; then

    # PostgreSQL host rule columns:
    # type database user address auth-method [options]
    HOST_RULES="$(
        awk '
        /^[[:space:]]*#/ {next}
        /^[[:space:]]*$/ {next}
        $1 ~ /^host/ {print}
        ' "$PG_HBA"
    )"

    if [[ -n "$HOST_RULES" ]]; then
        check "TCP host authentication rules are configured" PASS
    else
        check "TCP host authentication rules are configured" INFO
        echo "No host rules found; PostgreSQL may only be accepting local socket connections."
    fi

    TRUST_RULES="$(
        awk '
        /^[[:space:]]*#/ {next}
        /^[[:space:]]*$/ {next}
        $1 ~ /^host/ && $5 == "trust" {print NR ":" $0}
        ' "$PG_HBA"
    )"

    if [[ -z "$TRUST_RULES" ]]; then
        check "No unauthenticated TCP trust rules found" PASS
    else
        check "Unauthenticated TCP trust rules found" WARN
        echo "$TRUST_RULES"
    fi

    MD5_RULES="$(
        awk '
        /^[[:space:]]*#/ {next}
        /^[[:space:]]*$/ {next}
        $1 ~ /^host/ && $5 == "md5" {print NR ":" $0}
        ' "$PG_HBA"
    )"

    if [[ -z "$MD5_RULES" ]]; then
        check "No MD5 TCP authentication rules found" PASS
    else
        check "MD5 TCP authentication rules found" WARN
        echo "$MD5_RULES"
    fi

    NONSSL_HOST_RULES="$(
        awk '
        /^[[:space:]]*#/ {next}
        /^[[:space:]]*$/ {next}
        $1 == "host" {print NR ":" $0}
        ' "$PG_HBA"
    )"

    if [[ -z "$NONSSL_HOST_RULES" ]]; then
        check "No plain host rules allowing non-SSL TCP connections" PASS
    else
        check "Plain host rules can permit non-SSL TCP connections" WARN
        echo "$NONSSL_HOST_RULES"
        echo "Use hostssl when the policy requires encrypted TCP connections."
    fi

    BROAD_TRUST="$(
        awk '
        /^[[:space:]]*#/ {next}
        /^[[:space:]]*$/ {next}
        $1 ~ /^host/ && $2 == "all" && $3 == "all" && ($4 == "0.0.0.0/0" || $4 == "::/0") && $5 == "trust" {print NR ":" $0}
        ' "$PG_HBA"
    )"

    if [[ -z "$BROAD_TRUST" ]]; then
        check "No broad internet-range trust rule found" PASS
    else
        check "Broad all-database/all-user trust rule found" WARN
        echo "$BROAD_TRUST"
    fi
fi

# ------------------------------------------------------------
# pg_hba_file_rules parse validation
# ------------------------------------------------------------

if [[ -n "$("${PGQUERY[@]}" "SELECT to_regclass('pg_catalog.pg_hba_file_rules');" 2>/dev/null | head -n1)" ]]; then
    HBA_ERRORS="$(
        "${PGQUERY[@]}" "
        SELECT COALESCE(line_number::text || ': ' || error, '')
        FROM pg_catalog.pg_hba_file_rules
        WHERE error IS NOT NULL
        ORDER BY line_number;
        " 2>/dev/null || true
    )"

    if [[ -z "$HBA_ERRORS" ]]; then
        check "PostgreSQL reports no pg_hba.conf parsing errors" PASS
    else
        check "PostgreSQL reports pg_hba.conf parsing errors" WARN
        echo "$HBA_ERRORS"
    fi
fi

# ------------------------------------------------------------
# Role audit
# ------------------------------------------------------------

echo
echo "Checking PostgreSQL roles..."

LOGIN_ROLES="$(
    "${PGQUERY[@]}" "
    SELECT rolname || E' | superuser=' || rolsuper ||
           E' | createdb=' || rolcreatedb ||
           E' | createrole=' || rolcreaterole
    FROM pg_authid
    WHERE rolcanlogin
    ORDER BY rolname;
    " 2>/dev/null || true
)"

if [[ -n "$LOGIN_ROLES" ]]; then
    check "PostgreSQL login roles can be enumerated" PASS
    echo "$LOGIN_ROLES"
else
    check "PostgreSQL login roles can be enumerated" WARN
fi

SUPERUSERS="$(
    "${PGQUERY[@]}" "
    SELECT rolname
    FROM pg_authid
    WHERE rolcanlogin AND rolsuper
    ORDER BY rolname;
    " 2>/dev/null || true
)"

SUPER_COUNT="$(printf '%s\n' "$SUPERUSERS" | sed '/^[[:space:]]*$/d' | wc -l)"

if (( SUPER_COUNT <= 1 )); then
    check "No unnecessary PostgreSQL login superusers detected" PASS
else
    check "Multiple PostgreSQL login superusers detected" WARN
    echo "$SUPERUSERS"
fi

NULL_PASSWORDS="$(
    "${PGQUERY[@]}" "
    SELECT rolname
    FROM pg_authid
    WHERE rolcanlogin AND rolpassword IS NULL
    ORDER BY rolname;
    " 2>/dev/null || true
)"

if [[ -z "$NULL_PASSWORDS" ]]; then
    check "No login roles with NULL stored passwords detected" PASS
else
    check "Login roles with NULL stored passwords detected" WARN
    echo "$NULL_PASSWORDS"
fi

MD5_PASSWORDS="$(
    "${PGQUERY[@]}" "
    SELECT rolname
    FROM pg_authid
    WHERE rolcanlogin AND rolpassword LIKE 'md5%'
    ORDER BY rolname;
    " 2>/dev/null || true
)"

if [[ -z "$MD5_PASSWORDS" ]]; then
    check "No login roles with MD5 password hashes detected" PASS
else
    check "Login roles with MD5 password hashes detected" WARN
    echo "$MD5_PASSWORDS"
    echo "Users must change their passwords after SCRAM is configured."
fi

# ------------------------------------------------------------
# File permissions
# ------------------------------------------------------------

echo
echo "Checking PostgreSQL file permissions..."

if [[ -n "$PG_CONFIG" && -f "$PG_CONFIG" ]]; then
    OWNER="$(stat -c '%U:%G' "$PG_CONFIG" 2>/dev/null || true)"
    MODE="$(stat -c '%a' "$PG_CONFIG" 2>/dev/null || true)"

    if [[ "$OWNER" == "postgres:postgres" || "$OWNER" == "postgres:postgres" ]]; then
        check "postgresql.conf is owned by postgres" PASS
    else
        check "postgresql.conf is owned by postgres" WARN
        echo "Owner: $OWNER"
    fi

    if [[ "$MODE" =~ ^6[0-4][0-4]$|^600$|^640$ ]]; then
        check "postgresql.conf is not world-writable/world-readable" PASS
    else
        check "postgresql.conf permissions should be reviewed" WARN
        echo "Mode: $MODE"
    fi
fi

if [[ -n "$PG_HBA" && -f "$PG_HBA" ]]; then
    OWNER="$(stat -c '%U:%G' "$PG_HBA" 2>/dev/null || true)"
    MODE="$(stat -c '%a' "$PG_HBA" 2>/dev/null || true)"

    if [[ "$OWNER" == "postgres:postgres" ]]; then
        check "pg_hba.conf is owned by postgres" PASS
    else
        check "pg_hba.conf is owned by postgres" WARN
        echo "Owner: $OWNER"
    fi

    if [[ "$MODE" =~ ^6[0-4][0-4]$|^600$|^640$ ]]; then
        check "pg_hba.conf is not world-writable/world-readable" PASS
    else
        check "pg_hba.conf permissions should be reviewed" WARN
        echo "Mode: $MODE"
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

read -rp "Apply safe PostgreSQL hardening? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

if [[ ! -f "$PG_CONFIG" || ! -f "$PG_HBA" ]]; then
    echo "Required PostgreSQL configuration files were not found."
    echo "No changes made."
    exit 1
fi

BACKUP="$BACKUP_ROOT/postgresql_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP"
cp -a "$PG_CONFIG" "$BACKUP/postgresql.conf"
cp -a "$PG_HBA" "$BACKUP/pg_hba.conf"

echo
echo "Backup created: $BACKUP"

# ------------------------------------------------------------
# Safe settings
# ------------------------------------------------------------

set_config() {
    local file="$1"
    local key="$2"
    local value="$3"

    sed -i -E "/^[[:space:]]*${key}[[:space:]]*=/d" "$file"
    printf '\n# CyberPatriot PostgreSQL hardening\n%s = %s\n' "$key" "$value" >> "$file"
}

echo
echo "Applying safe PostgreSQL settings..."

set_config "$PG_CONFIG" "ssl" "on"
set_config "$PG_CONFIG" "password_encryption" "'scram-sha-256'"
set_config "$PG_CONFIG" "log_connections" "on"
set_config "$PG_CONFIG" "log_disconnections" "on"

echo "Configured:"
echo "  ssl = on"
echo "  password_encryption = 'scram-sha-256'"
echo "  log_connections = on"
echo "  log_disconnections = on"

# ------------------------------------------------------------
# Authentication rules
# ------------------------------------------------------------

echo
echo "Reviewing pg_hba.conf authentication rules..."

if [[ -n "$TRUST_RULES" ]]; then
    echo
    echo "WARNING: trust rules were found."
    echo "They were NOT automatically changed."
    echo
    echo "$TRUST_RULES"
    echo
    echo "Replace each trust rule with an authentication method"
    echo "appropriate for the CyberPatriot image/application."
else
    echo "No TCP trust rules were found."
fi

if [[ -n "$NONSSL_HOST_RULES" ]]; then
    echo
    echo "WARNING: plain 'host' rules were found."
    echo "These can permit non-SSL TCP connections."
    echo "They were NOT automatically rewritten."
    echo
    echo "$NONSSL_HOST_RULES"
    echo
    echo "For environments requiring TLS, use hostssl with an"
    echo "appropriate authenticated method such as scram-sha-256."
fi

# ------------------------------------------------------------
# Validate configuration before restart
# ------------------------------------------------------------

echo
echo "Validating PostgreSQL configuration..."

if systemctl reload "$SERVICE"; then
    echo "PostgreSQL configuration reload succeeded."
else
    echo "WARNING: PostgreSQL reload failed."
    echo "Backup: $BACKUP"
    exit 1
fi

SSL_AFTER="$("${PGQUERY[@]}" "SHOW ssl;" 2>/dev/null | head -n1 || true)"
PE_AFTER="$("${PGQUERY[@]}" "SHOW password_encryption;" 2>/dev/null | head -n1 || true)"

[[ "$SSL_AFTER" == "on" ]] &&
    check "SSL is active after reload" PASS ||
    check "SSL is active after reload" WARN

[[ "$PE_AFTER" == "scram-sha-256" ]] &&
    check "password_encryption is SCRAM after reload" PASS ||
    check "password_encryption is SCRAM after reload" WARN

echo
echo "PostgreSQL hardening complete."
echo
echo "IMPORTANT:"
echo "- Existing MD5 passwords are not automatically converted."
echo "- Users with MD5 hashes need to change their passwords."
echo "- trust/host rules were intentionally not rewritten automatically."
echo "- Review pg_hba.conf before changing authentication methods."
echo "- Backup: $BACKUP"

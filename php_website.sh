
#!/bin/bash

# CyberPatriot PHP 7.4 Website Security Auditor
# Supports Debian-based and RHEL-based PHP layouts

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/php_audit.log"

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

PASS=0
WARN=0
PHP_DIRS=()

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
echo " CYBERPATRIOT PHP WEBSITE AUDIT"
echo "========================================"
echo "OS: ${PRETTY_NAME:-Unknown}"
echo

# Find PHP 7.4 website configuration directories.

for d in /etc/php/7.4/apache2/conf.d \
         /etc/php/7.4/fpm/conf.d \
         /etc/php.d; do
    if [[ -d "$d" ]]; then
        PHP_DIRS+=("$d")
    fi
done

if [[ -d /etc/php.d ]]; then
    if command -v php >/dev/null 2>&1 &&
       php -v 2>/dev/null | grep -q 'PHP 7\.4'; then
        :
    else
        # Avoid assuming /etc/php.d belongs to PHP 7.4.
        PHP_DIRS=("${PHP_DIRS[@]/\/etc\/php.d}")
    fi
fi

# Remove empty array entries.
CLEAN_DIRS=()
for d in "${PHP_DIRS[@]}"; do
    [[ -n "$d" ]] && CLEAN_DIRS+=("$d")
done
PHP_DIRS=("${CLEAN_DIRS[@]}")

if ((${#PHP_DIRS[@]} == 0)); then
    echo "No PHP 7.4 Apache/FPM configuration directories found."
    echo "This script will not modify another PHP version."
    exit 1
fi

echo "Detected PHP configuration directories:"
for d in "${PHP_DIRS[@]}"; do
    echo " - $d"
done

echo
echo "Checking PHP configuration..."

PHP_FILES=()

for d in "${PHP_DIRS[@]}"; do
    while IFS= read -r -d '' f; do
        PHP_FILES+=("$f")
    done < <(find "$d" -maxdepth 1 -type f -name '*.ini' -print0)
done

# Include the primary PHP 7.4 configuration files.
for f in /etc/php/7.4/apache2/php.ini \
         /etc/php/7.4/fpm/php.ini \
         /etc/php.ini; do
    [[ -f "$f" ]] && PHP_FILES+=("$f")
done

audit_setting() {
    local setting="$1"
    local expected="$2"

    if grep -hEi "^[[:space:]]*${setting}[[:space:]]*=[[:space:]]*${expected}([[:space:]]*;.*)?$" \
        "${PHP_FILES[@]}" 2>/dev/null | grep -q .; then
        check "$setting is configured as $expected" PASS
    else
        check "$setting is not configured as $expected" WARN
    fi
}

audit_setting "expose_php" "Off"
audit_setting "display_errors" "Off"
audit_setting "log_errors" "On"
audit_setting "allow_url_include" "Off"
audit_setting "session.cookie_httponly" "1"
audit_setting "session.use_strict_mode" "1"

echo
echo "Checking PHP version..."

if command -v php >/dev/null 2>&1; then
    php -v | head -n 1
    if php -v 2>/dev/null | grep -q 'PHP 7\.4'; then
        check "CLI PHP reports version 7.4" PASS
    else
        check "CLI PHP is not reporting version 7.4" WARN
    fi
else
    check "PHP CLI is not installed" WARN
fi

echo
echo "========================================"
echo " AUDIT SUMMARY"
echo "========================================"
echo "Passed: $PASS"
echo "Warnings: $WARN"
echo "Log: $LOG"
echo

read -rp "Apply recommended PHP hardening settings? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

SETTINGS=$(cat <<'EOF'
; CyberPatriot PHP 7.4 security settings
expose_php = Off
display_errors = Off
log_errors = On
allow_url_include = Off
session.cookie_httponly = 1
session.use_strict_mode = 1
EOF
)

echo
echo "These settings will be added to PHP 7.4 website configuration."
echo "They do not disable PHP functions or change the PHP version."
echo

CHANGED=0

for d in "${PHP_DIRS[@]}"; do

    TARGET="$d/99-cyberpatriot-hardening.ini"
    BACKUP=""

    if [[ -f "$TARGET" ]]; then
        BACKUP="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
        cp -a "$TARGET" "$BACKUP" || {
            echo "Could not back up $TARGET"
            continue
        }
    fi

    printf '%s\n' "$SETTINGS" > "$TARGET" || {
        echo "Could not write $TARGET"
        continue
    }

    echo "[SUCCESS] Updated: $TARGET"
    [[ -n "$BACKUP" ]] && echo "Backup: $BACKUP"

    log "PHP configuration updated: $TARGET"
    ((CHANGED+=1))
done

echo
echo "========================================"
echo " PHP HARDENING SUMMARY"
echo "========================================"
echo "Configuration directories updated: $CHANGED"

if ((CHANGED > 0)); then
    echo
    echo "IMPORTANT:"
    echo "Review website compatibility before restarting PHP."
    echo "Restart the applicable Apache or PHP-FPM service"
    echo "during an appropriate maintenance window."
fi

echo
echo "PHP hardening process complete."

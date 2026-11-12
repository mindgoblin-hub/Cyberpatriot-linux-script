
#!/bin/bash

# CyberPatriot Apache Web Server Auditor
# Multi-distro: Debian, Ubuntu, Mint, Fedora, RHEL,
# Rocky, AlmaLinux, Arch, Manjaro, openSUSE

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/apache_audit.log"

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

case "${ID:-}" in
    ubuntu|debian|linuxmint|pop)
        SERVICE="apache2"
        CONF_DIR="/etc/apache2/conf-enabled"
        ;;
    fedora|rhel|rocky|almalinux|centos)
        SERVICE="httpd"
        CONF_DIR="/etc/httpd/conf.d"
        ;;
    arch|manjaro)
        SERVICE="httpd"
        CONF_DIR="/etc/httpd/conf.d"
        ;;
    opensuse*|sles)
        SERVICE="apache2"
        CONF_DIR="/etc/apache2/conf.d"
        ;;
    *)
        echo "Unknown distribution: ${PRETTY_NAME:-Unknown}"
        echo "Apache checks will use detected system paths."
        SERVICE="apache2"
        CONF_DIR="/etc/apache2/conf-enabled"
        ;;
esac

REPORT=0
PASS=0
WARN=0

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

check() {
    local description="$1"
    local result="$2"

    if [[ "$result" == "PASS" ]]; then
        ((PASS+=1))
        log "[PASS] $description"
    else
        ((WARN+=1))
        log "[WARNING] $description"
    fi
}

echo "========================================"
echo " CYBERPATRIOT APACHE SECURITY AUDIT"
echo "========================================"
echo "OS: ${PRETTY_NAME:-Unknown}"
echo "Service: $SERVICE"
echo

if ! command -v apachectl >/dev/null 2>&1 &&
   ! command -v apache2ctl >/dev/null 2>&1 &&
   ! command -v httpd >/dev/null 2>&1; then
    echo "Apache does not appear to be installed."
    exit 1
fi

if systemctl is-active --quiet "$SERVICE"; then
    check "Apache service is running" PASS
else
    check "Apache service is not running" WARN
fi

if command -v apachectl >/dev/null 2>&1; then
    APACHE_CMD="apachectl"
elif command -v apache2ctl >/dev/null 2>&1; then
    APACHE_CMD="apache2ctl"
else
    APACHE_CMD="httpd"
fi

echo
echo "Checking Apache configuration..."

if "$APACHE_CMD" -t 2>&1; then
    check "Apache configuration syntax" PASS
else
    check "Apache configuration syntax" WARN
fi

CONFIG_FILES=()

for f in /etc/apache2/apache2.conf \
         /etc/httpd/conf/httpd.conf \
         /etc/apache2/conf-enabled/*.conf \
         /etc/apache2/conf-available/*.conf \
         /etc/httpd/conf.d/*.conf \
         /etc/apache2/conf.d/*.conf; do
    [[ -f "$f" ]] && CONFIG_FILES+=("$f")
done

echo
echo "Checking security directives..."

if grep -hRiE '^[[:space:]]*ServerTokens[[:space:]]+Prod' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "ServerTokens Prod" PASS
else
    check "ServerTokens Prod" WARN
fi

if grep -hRiE '^[[:space:]]*ServerSignature[[:space:]]+Off' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "ServerSignature Off" PASS
else
    check "ServerSignature Off" WARN
fi

if grep -hRiE 'Options.*-Indexes' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "Directory listing restriction found" PASS
else
    check "Directory listing restriction not found" WARN
fi

if grep -hRiE '^[[:space:]]*TraceEnable[[:space:]]+Off' \
    "${CONFIG_FILES[@]}" 2>/dev/null | grep -q .; then
    check "HTTP TRACE disabled" PASS
else
    check "HTTP TRACE restriction not found" WARN
fi

echo
echo "========================================"
echo " AUDIT SUMMARY"
echo "========================================"
echo "Passed: $PASS"
echo "Warnings: $WARN"
echo "Log: $LOG"
echo

read -rp "Would you like to apply recommended Apache hardening? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

mkdir -p "$CONF_DIR"

TARGET="$CONF_DIR/zz-cyberpatriot-hardening.conf"
BACKUP=""

if [[ -f "$TARGET" ]]; then
    BACKUP="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
    cp -a "$TARGET" "$BACKUP" || exit 1
fi

cat > "$TARGET" <<'EOF'
# CyberPatriot Apache security settings
ServerTokens Prod
ServerSignature Off
TraceEnable Off

<Directory />
    Options -Indexes
</Directory>
EOF

echo
echo "Testing new Apache configuration..."

if "$APACHE_CMD" -t; then
    echo "[PASS] Configuration accepted."
    log "Apache hardening configuration installed."

    if systemctl is-active --quiet "$SERVICE"; then
        if systemctl reload "$SERVICE"; then
            echo "[PASS] Apache reloaded successfully."
        else
            echo "[WARNING] Reload failed. Check service status."
            log "Apache reload failed."
        fi
    else
        echo "[INFO] Apache is not running; no reload performed."
    fi
else
    echo "[ERROR] Configuration test failed. Restoring previous file."

    if [[ -n "$BACKUP" ]]; then
        cp -a "$BACKUP" "$TARGET"
    else
        rm -f "$TARGET"
    fi

    log "Apache configuration rolled back."
    exit 1
fi

echo
echo "Apache hardening process complete."

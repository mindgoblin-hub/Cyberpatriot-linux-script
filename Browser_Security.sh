
#!/bin/bash

# ==========================================================
# CYBERPATRIOT UNIVERSAL BROWSER SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$LOG_DIR/browser_backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG="$LOG_DIR/browser_security.log"
REPORT="$LOG_DIR/browser_report_$(date +%Y%m%d_%H%M%S).txt"

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
echo "        CYBERPATRIOT BROWSER SECURITY AUDIT"
echo "=================================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"

# ==========================================================
# BROWSER DETECTION
# ==========================================================

section "[1] BROWSER DETECTION"

BROWSERS=(
    firefox
    firefox-esr
    chromium
    chromium-browser
    google-chrome
    google-chrome-stable
    brave-browser
    microsoft-edge
)

FOUND_BROWSERS=()

for BROWSER in "${BROWSERS[@]}"; do

    if command -v "$BROWSER" >/dev/null 2>&1; then

        FOUND_BROWSERS+=("$BROWSER")

        LOCATION="$(command -v "$BROWSER")"

        echo "[DETECTED] $BROWSER"
        echo "Location: $LOCATION"

        VERSION="$("$BROWSER" --version 2>/dev/null | head -n 1 || true)"

        echo "Version: ${VERSION:-Unknown}"

        check INFO "Browser detected: $BROWSER"

    fi

done

if (( ${#FOUND_BROWSERS[@]} == 0 )); then
    check WARNING "No recognized browsers detected."
fi

# ==========================================================
# BROWSER PACKAGE AUDIT
# ==========================================================

section "[2] BROWSER PACKAGE AUDIT"

for BROWSER in "${FOUND_BROWSERS[@]}"; do

    echo
    echo "Browser: $BROWSER"

    if command -v dpkg-query >/dev/null 2>&1; then

        dpkg-query -S "$(command -v "$BROWSER")" 2>/dev/null || true

    elif command -v rpm >/dev/null 2>&1; then

        rpm -qf "$(command -v "$BROWSER")" 2>/dev/null || true

    elif command -v pacman >/dev/null 2>&1; then

        pacman -Qo "$(command -v "$BROWSER")" 2>/dev/null || true

    fi

done

check INFO "Browser package ownership reviewed."

# ==========================================================
# BROWSER PROFILE DISCOVERY
# ==========================================================

section "[3] BROWSER PROFILE DISCOVERY"

PROFILE_DIRS=()

for USER_HOME in /home/*; do

    [[ -d "$USER_HOME" ]] || continue

    USERNAME="$(basename "$USER_HOME")"

    echo
    echo "User: $USERNAME"

    CANDIDATE_DIRS=(
        "$USER_HOME/.mozilla/firefox"
        "$USER_HOME/.config/chromium"
        "$USER_HOME/.config/google-chrome"
        "$USER_HOME/.config/BraveSoftware/Brave-Browser"
        "$USER_HOME/.config/microsoft-edge"
    )

    for DIR in "${CANDIDATE_DIRS[@]}"; do

        if [[ -d "$DIR" ]]; then

            PROFILE_DIRS+=("$DIR")

            echo "[PROFILE] $DIR"

            check INFO "Browser profile found: $DIR"

        fi

    done

done

if (( ${#PROFILE_DIRS[@]} == 0 )); then
    check INFO "No browser profiles found in standard user locations."
fi

# ==========================================================
# FIREFOX PROFILE AUDIT
# ==========================================================

section "[4] FIREFOX SECURITY"

FIREFOX_PROFILES=()

for DIR in /home/*/.mozilla/firefox; do

    [[ -d "$DIR" ]] || continue

    FIREFOX_PROFILES+=("$DIR")

done

for DIR in "${FIREFOX_PROFILES[@]}"; do

    echo
    echo "Firefox directory: $DIR"

    if [[ -f "$DIR/profiles.ini" ]]; then

        echo "Profiles:"
        grep -E '^\[Profile|^Name=|^Path=|^IsRelative=' \
            "$DIR/profiles.ini" || true

        check INFO "Firefox profile configuration found."

    fi

    find "$DIR" -maxdepth 2 -type f \
        -name prefs.js -print 2>/dev/null

    while IFS= read -r PREFS; do

        echo
        echo "Checking: $PREFS"

        for PREF in \
            network.cookie.cookieBehavior \
            signon.rememberSignons \
            security.tls.version.min \
            security.ssl.require_safe_negotiation \
            browser.safebrowsing.malware.enabled \
            browser.safebrowsing.phishing.enabled \
            security.enterprise_roots.enabled
        do

            VALUE="$(grep -E "user_pref\\(\"$PREF\"" \
                "$PREFS" 2>/dev/null | tail -n 1 || true)"

            if [[ -n "$VALUE" ]]; then
                echo "$VALUE"
            fi

        done

        check INFO "Firefox preferences reviewed."

    done < <(find "$DIR" -maxdepth 2 -type f \
        -name prefs.js -print 2>/dev/null)

done

# ==========================================================
# CHROMIUM / CHROME / BRAVE PROFILE AUDIT
# ==========================================================

section "[5] CHROMIUM-BASED BROWSER SECURITY"

CHROMIUM_DIRS=(
    /home/*/.config/chromium
    /home/*/.config/google-chrome
    /home/*/.config/BraveSoftware/Brave-Browser
    /home/*/.config/microsoft-edge
)

for DIR in "${CHROMIUM_DIRS[@]}"; do

    [[ -d "$DIR" ]] || continue

    echo
    echo "Browser profile: $DIR"

    if [[ -d "$DIR/Default/Extensions" ]]; then

        EXTENSIONS="$(find "$DIR/Default/Extensions" \
            -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"

        echo "Default profile extensions: $EXTENSIONS"

        check INFO "Chromium extension inventory collected."

    fi

    if [[ -f "$DIR/Default/Preferences" ]]; then

        stat -c '%A %U:%G %n' "$DIR/Default/Preferences"

        check INFO "Chromium preferences file found."

    fi

done

# ==========================================================
# EXTENSION AUDIT
# ==========================================================

section "[6] BROWSER EXTENSION AUDIT"

for DIR in "${PROFILE_DIRS[@]}"; do

    echo
    echo "Profile: $DIR"

    find "$DIR" -type d \
        \( -path '*/Extensions/*' -o -path '*/extensions/*' \) \
        -maxdepth 7 -print 2>/dev/null | head -n 50

done

check INFO "Browser extension directories reviewed."

# ==========================================================
# PROFILE PERMISSIONS
# ==========================================================

section "[7] BROWSER PROFILE PERMISSIONS"

for DIR in "${PROFILE_DIRS[@]}"; do

    echo
    echo "$DIR"

    stat -c '%A %U:%G %n' "$DIR"

    OWNER="$(stat -c '%U' "$DIR")"

    if [[ "$OWNER" == "root" ]]; then
        check WARNING "Browser profile is owned by root: $DIR"
    else
        check INFO "Browser profile owner: $OWNER"
    fi

    if [[ -w "$DIR" ]]; then
        check INFO "Profile is writable by the audit process: $DIR"
    fi

done

# ==========================================================
# BROWSER POLICY AUDIT
# ==========================================================

section "[8] BROWSER POLICIES"

POLICY_DIRS=(
    /etc/firefox
    /etc/firefox/policies
    /usr/lib/firefox/distribution
    /etc/chromium
    /etc/opt/chrome/policies
    /etc/opt/BraveSoftware/policies
    /etc/microsoft-edge
)

for DIR in "${POLICY_DIRS[@]}"; do

    [[ -d "$DIR" ]] || continue

    echo
    echo "Policy directory: $DIR"

    find "$DIR" -maxdepth 3 -type f -print 2>/dev/null

    while IFS= read -r FILE; do

        [[ -f "$FILE" ]] || continue

        echo
        echo "File: $FILE"

        stat -c '%A %U:%G %n' "$FILE"

        if [[ "$FILE" == *.json ]]; then
            if command -v python3 >/dev/null 2>&1; then
                python3 -m json.tool "$FILE" >/dev/null 2>&1 &&
                    check PASS "Valid JSON policy: $FILE" ||
                    check WARNING "Invalid JSON policy: $FILE"
            fi
        fi

    done < <(find "$DIR" -maxdepth 3 -type f -print 2>/dev/null)

done

check INFO "Browser policy directories reviewed."

# ==========================================================
# BROWSER AUTOSTART AUDIT
# ==========================================================

section "[9] BROWSER AUTOSTART"

for USER_HOME in /home/*; do

    [[ -d "$USER_HOME" ]] || continue

    AUTOSTART="$USER_HOME/.config/autostart"

    [[ -d "$AUTOSTART" ]] || continue

    echo
    echo "User: $(basename "$USER_HOME")"

    find "$AUTOSTART" -maxdepth 1 -type f \
        -print 2>/dev/null

done

check INFO "Browser-related desktop autostart locations reviewed."

# ==========================================================
# SAVED CREDENTIAL INDICATORS
# ==========================================================

section "[10] SAVED CREDENTIAL CONFIGURATION"

for DIR in "${PROFILE_DIRS[@]}"; do

    echo
    echo "Profile: $DIR"

    if [[ -f "$DIR/logins.json" ]]; then
        echo "Firefox saved-login file exists."
        check INFO "Firefox saved-login configuration found."
    fi

    if [[ -f "$DIR/Default/Login Data" ]]; then
        echo "Chromium saved-login database exists."
        check INFO "Chromium saved-login database found."
    fi

done

echo "Note: File existence does not establish whether credentials are protected."

# ==========================================================
# BROWSER UPDATE AUDIT
# ==========================================================

section "[11] BROWSER UPDATE SERVICES"

UPDATE_SERVICES=(
    packagekit
    packagekit-offline-update
    apt-daily.timer
    apt-daily-upgrade.timer
    dnf-automatic.timer
    snapd
)

for SERVICE in "${UPDATE_SERVICES[@]}"; do

    STATUS="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
    ENABLED="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

    if [[ "$STATUS" != "unknown" || "$ENABLED" != "unknown" ]]; then
        echo "$SERVICE: $STATUS / $ENABLED"
    fi

done

check INFO "System update service status reviewed."

# ==========================================================
# REPORT GENERATION
# ==========================================================

{
    echo "CYBERPATRIOT BROWSER SECURITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Date: $(date)"

    echo
    echo "DETECTED BROWSERS"

    for BROWSER in "${FOUND_BROWSERS[@]}"; do
        "$BROWSER" --version 2>/dev/null || true
    done

    echo
    echo "BROWSER PROFILES"

    for DIR in "${PROFILE_DIRS[@]}"; do
        stat -c '%A %U:%G %n' "$DIR" 2>/dev/null || true
    done

    echo
    echo "FIREFOX PREFERENCES"

    grep -RhE 'security\.tls|signon\.rememberSignons|browser\.safebrowsing' \
        /home/*/.mozilla/firefox/*/prefs.js 2>/dev/null || true

    echo
    echo "BROWSER POLICIES"

    for DIR in "${POLICY_DIRS[@]}"; do
        find "$DIR" -maxdepth 3 -type f -print 2>/dev/null || true
    done

} > "$REPORT"

check PASS "Browser security report generated."

# ==========================================================
# SUMMARY
# ==========================================================

section "[12] AUDIT SUMMARY"

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Critical: $CRITICAL"
echo "Info:     $INFO"

echo
echo "Log: $LOG"
echo "Report: $REPORT"

log "Browser audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==========================================================
# INTERACTIVE MENU
# ==========================================================

section "[13] BROWSER SECURITY MENU"

echo "1. Display installed browsers."
echo "2. Review browser profiles."
echo "3. Review Firefox preferences."
echo "4. Review Chromium profiles."
echo "5. Review browser policies."
echo "6. Review browser extensions."
echo "7. Back up browser policies."
echo "8. Display security report."
echo "0. Exit."

echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)

        for BROWSER in "${FOUND_BROWSERS[@]}"; do
            "$BROWSER" --version 2>/dev/null || true
        done

        ;;

    2)

        for DIR in "${PROFILE_DIRS[@]}"; do
            echo "$DIR"
        done

        ;;

    3)

        grep -RhE 'security\.tls|signon\.rememberSignons|browser\.safebrowsing' \
            /home/*/.mozilla/firefox/*/prefs.js 2>/dev/null ||
            echo "No Firefox preferences found."

        ;;

    4)

        for DIR in "${CHROMIUM_DIRS[@]}"; do
            [[ -d "$DIR" ]] && echo "$DIR"
        done

        ;;

    5)

        for DIR in "${POLICY_DIRS[@]}"; do
            [[ -d "$DIR" ]] && find "$DIR" -maxdepth 3 -type f -print
        done

        ;;

    6)

        for DIR in "${PROFILE_DIRS[@]}"; do

            find "$DIR" -type d \
                \( -path '*/Extensions/*' -o -path '*/extensions/*' \) \
                -maxdepth 7 -print 2>/dev/null

        done

        ;;

    7)

        for DIR in "${POLICY_DIRS[@]}"; do

            [[ -d "$DIR" ]] || continue

            NAME="$(basename "$DIR")"

            tar -czf \
                "$BACKUP_DIR/${NAME}_$(date +%Y%m%d_%H%M%S).tar.gz" \
                -C "$(dirname "$DIR")" "$NAME"

            echo "Backed up: $DIR"

        done

        ;;

    8)

        cat "$REPORT"

        ;;

    0)

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
echo "        BROWSER SECURITY AUDIT COMPLETED"
echo "=================================================="

echo "Log: $LOG"
echo "Report: $REPORT"

log "Browser security session completed."

exit 0

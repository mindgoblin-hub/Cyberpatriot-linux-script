```bash
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL KERNEL SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/kernel_security.log"

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
# SYSCTL CHECK FUNCTION
# ==================================================

check_sysctl() {
    local KEY="$1"
    local EXPECTED="$2"
    local DESCRIPTION="$3"

    local CURRENT

    CURRENT="$(sysctl -n "$KEY" 2>/dev/null || true)"

    if [[ -z "$CURRENT" ]]; then
        check INFO "$KEY is unavailable."
        return
    fi

    if [[ "$CURRENT" == "$EXPECTED" ]]; then
        check PASS "$DESCRIPTION ($CURRENT)"
    else
        check WARNING "$DESCRIPTION: current=$CURRENT expected=$EXPECTED"
    fi
}

# ==================================================
# PASSWORD HASHING DETECTION
# ==================================================

get_password_hash_method() {

    local METHOD=""

    # First check login.defs
    if [[ -r /etc/login.defs ]]; then

        METHOD="$(grep -E \
            '^[[:space:]]*ENCRYPT_METHOD[[:space:]]+' \
            /etc/login.defs 2>/dev/null |
            awk '{print $2}' |
            tail -n 1)"

    fi

    # Fedora/RHEL systems may use authselect/PAM configuration
    if [[ -z "$METHOD" ]]; then

        METHOD="$(grep -RhoE \
            'yescrypt|sha512|sha256|md5' \
            /etc/pam.d /etc/authselect 2>/dev/null |
            head -n 1)"

    fi

    echo "$METHOD"
}

password_hash_is_secure() {

    local METHOD="$1"

    case "${METHOD,,}" in

        yescrypt)
            return 0
            ;;

        sha512)
            return 0
            ;;

        sha256)
            return 1
            ;;

        md5|des)
            return 1
            ;;

        *)
            return 1
            ;;

    esac
}

# ==================================================
# HEADER
# ==================================================

echo "=============================================="
echo "       CYBERPATRIOT KERNEL SECURITY AUDIT"
echo "=============================================="
echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Kernel Version: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Date: $(date)"
echo

# ==================================================
# KERNEL VERSION AUDIT
# ==================================================

echo "[1] KERNEL INFORMATION"
echo "----------------------------------------------"

uname -a

check INFO "Kernel information collected."

echo

# ==================================================
# ASLR AUDIT
# ==================================================

echo "[2] ADDRESS SPACE LAYOUT RANDOMIZATION"
echo "----------------------------------------------"

check_sysctl \
    kernel.randomize_va_space \
    2 \
    "Full ASLR protection"

echo

# ==================================================
# KERNEL POINTER PROTECTION
# ==================================================

echo "[3] KERNEL POINTER PROTECTION"
echo "----------------------------------------------"

check_sysctl \
    kernel.kptr_restrict \
    2 \
    "Kernel pointer restrictions"

check_sysctl \
    kernel.dmesg_restrict \
    1 \
    "Kernel message access restrictions"

echo

# ==================================================
# CORE DUMP SECURITY
# ==================================================

echo "[4] CORE DUMP SECURITY"
echo "----------------------------------------------"

check_sysctl \
    fs.suid_dumpable \
    0 \
    "SUID program core dump restriction"

if [[ -f /etc/security/limits.conf ]]; then

    if grep -Eq '^[[:space:]]*\*[[:space:]]+hard[[:space:]]+core[[:space:]]+0' \
        /etc/security/limits.conf; then

        check PASS "Core dump hard limit found in limits.conf."

    else

        check WARNING "Core dump hard limit not explicitly configured in limits.conf."

    fi

else

    check INFO "limits.conf not found."

fi

echo

# ==================================================
# NETWORK KERNEL SECURITY
# ==================================================

echo "[5] NETWORK KERNEL SECURITY"
echo "----------------------------------------------"

check_sysctl \
    net.ipv4.conf.all.accept_redirects \
    0 \
    "IPv4 ICMP redirect protection"

check_sysctl \
    net.ipv4.conf.default.accept_redirects \
    0 \
    "Default IPv4 redirect protection"

check_sysctl \
    net.ipv4.conf.all.send_redirects \
    0 \
    "IPv4 redirect sending protection"

check_sysctl \
    net.ipv4.conf.all.accept_source_route \
    0 \
    "IPv4 source routing protection"

check_sysctl \
    net.ipv4.conf.default.accept_source_route \
    0 \
    "Default IPv4 source routing protection"

check_sysctl \
    net.ipv4.tcp_syncookies \
    1 \
    "TCP SYN flood protection"

check_sysctl \
    net.ipv6.conf.all.accept_redirects \
    0 \
    "IPv6 redirect protection"

check_sysctl \
    net.ipv6.conf.default.accept_redirects \
    0 \
    "Default IPv6 redirect protection"

# Log impossible/martian IPv4 addresses
check_sysctl \
    net.ipv4.conf.all.log_martians \
    1 \
    "IPv4 martian packet logging"

check_sysctl \
    net.ipv4.conf.default.log_martians \
    1 \
    "Default IPv4 martian packet logging"

echo

# ==================================================
# IP FORWARDING AUDIT
# ==================================================

echo "[6] IP FORWARDING AUDIT"
echo "----------------------------------------------"

IPV4_FORWARD="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo unavailable)"

echo "IPv4 forwarding: $IPV4_FORWARD"

if [[ "$IPV4_FORWARD" == "0" ]]; then
    check PASS "IPv4 forwarding disabled."
elif [[ "$IPV4_FORWARD" == "1" ]]; then
    check WARNING "IPv4 forwarding enabled. Verify whether routing is required."
else
    check INFO "IPv4 forwarding setting unavailable."
fi

IPV6_FORWARD="$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo unavailable)"

echo "IPv6 forwarding: $IPV6_FORWARD"

if [[ "$IPV6_FORWARD" == "0" ]]; then
    check PASS "IPv6 forwarding disabled."
elif [[ "$IPV6_FORWARD" == "1" ]]; then
    check WARNING "IPv6 forwarding enabled. Verify whether routing is required."
else
    check INFO "IPv6 forwarding setting unavailable."
fi

echo

# ==================================================
# KERNEL MODULE AUDIT
# ==================================================

echo "[7] KERNEL MODULE AUDIT"
echo "----------------------------------------------"

if command -v lsmod >/dev/null 2>&1; then

    MODULE_COUNT="$(lsmod | tail -n +2 | wc -l)"

    echo "Loaded kernel modules: $MODULE_COUNT"

    lsmod | head -n 25

    check INFO "Loaded kernel modules inventoried."

else

    check WARNING "lsmod command unavailable."

fi

echo

# ==================================================
# FILESYSTEM MODULE AUDIT
# ==================================================

echo "[8] FILESYSTEM MODULE REVIEW"
echo "----------------------------------------------"

if [[ -d /lib/modules/"$(uname -r)" ]]; then

    echo "Kernel module directory exists."

    for MODULE in cramfs freevxfs jffs2 hfs hfsplus squashfs; do

        if [[ -d /sys/module/"$MODULE" ]]; then
            check INFO "$MODULE module is loaded."
        else
            check INFO "$MODULE module is not currently loaded."
        fi

    done

else

    check WARNING "Kernel module directory not found."

fi

echo

# ==================================================
# MODULE SIGNATURE AUDIT
# ==================================================

echo "[9] MODULE SIGNATURE AUDIT"
echo "----------------------------------------------"

if [[ -r /sys/module/module/parameters/sig_enforce ]]; then

    SIGNATURE="$(cat /sys/module/module/parameters/sig_enforce)"

    if [[ "$SIGNATURE" == "Y" ]]; then
        check PASS "Kernel module signature enforcement enabled."
    else
        check WARNING "Kernel module signature enforcement not enabled."
    fi

else

    check INFO "Module signature enforcement status unavailable."

fi

echo

# ==================================================
# KERNEL LOCKDOWN AUDIT
# ==================================================

echo "[10] KERNEL LOCKDOWN"
echo "----------------------------------------------"

if [[ -r /sys/kernel/security/lockdown ]]; then

    LOCKDOWN="$(cat /sys/kernel/security/lockdown)"

    echo "Lockdown status: $LOCKDOWN"
    check INFO "Kernel lockdown status retrieved."

else

    check INFO "Kernel lockdown interface unavailable."

fi

echo

# ==================================================
# SYSCTL CONFIGURATION AUDIT
# ==================================================

echo "[11] SYSCTL CONFIGURATION"
echo "----------------------------------------------"

if [[ -f /etc/sysctl.conf ]]; then

    echo "Main sysctl configuration exists."

    stat -c '%A %U:%G %n' /etc/sysctl.conf

    OWNER="$(stat -c '%U' /etc/sysctl.conf)"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "/etc/sysctl.conf owned by root."
    else
        check WARNING "/etc/sysctl.conf owned by $OWNER."
    fi

else

    check INFO "/etc/sysctl.conf does not exist."

fi

if [[ -d /etc/sysctl.d ]]; then

    echo
    echo "Additional sysctl configuration files:"

    find /etc/sysctl.d -maxdepth 1 -type f \
        -name '*.conf' -print 2>/dev/null

    check INFO "Additional sysctl configuration inventory collected."

fi

echo

# ==================================================
# PASSWORD HASHING SECURITY AUDIT
# ==================================================

echo "[12] PASSWORD HASHING SECURITY"
echo "----------------------------------------------"

HASH_METHOD="$(get_password_hash_method)"

if [[ -n "$HASH_METHOD" ]]; then

    echo "Detected password hashing method: $HASH_METHOD"

    if password_hash_is_secure "$HASH_METHOD"; then

        check PASS "Secure password hashing algorithm detected: $HASH_METHOD."

    else

        case "${HASH_METHOD,,}" in

            md5|des)
                check CRITICAL "Weak password hashing algorithm detected: $HASH_METHOD."
                ;;

            sha256)
                check WARNING "SHA-256 password hashing detected. A stronger password hashing method should be used when supported."
                ;;

            *)
                check WARNING "Password hashing method requires verification: $HASH_METHOD."
                ;;

        esac

    fi

else

    check WARNING "Unable to determine the configured password hashing algorithm."

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

log "Kernel audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE HARDENING
# ==================================================

echo
read -rp "Would you like to review kernel hardening options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

# ==================================================
# CONFIGURATION PATH
# ==================================================

CONFIG="/etc/sysctl.d/99-cyberpatriot-hardening.conf"

# ==================================================
# BACKUP CONFIGURATION
# ==================================================

backup_config() {

    BACKUP_DIR="$LOG_DIR/kernel_backups"
    mkdir -p "$BACKUP_DIR"

    if [[ -f "$CONFIG" ]]; then

        cp -a "$CONFIG" \
            "$BACKUP_DIR/99-cyberpatriot-hardening.conf.$(date +%Y%m%d_%H%M%S)"

        return $?

    fi

    return 0
}

# ==================================================
# BACKUP PASSWORD CONFIGURATION
# ==================================================

backup_password_config() {

    BACKUP_DIR="$LOG_DIR/password_hash_backups"
    mkdir -p "$BACKUP_DIR"

    BACKUP_DATE="$(date +%Y%m%d_%H%M%S)"

    if [[ -f /etc/login.defs ]]; then

        cp -a /etc/login.defs \
            "$BACKUP_DIR/login.defs.$BACKUP_DATE"

    fi

    if [[ -f /etc/pam.d/common-password ]]; then

        cp -a /etc/pam.d/common-password \
            "$BACKUP_DIR/common-password.$BACKUP_DATE"

    fi

    return 0
}

# ==================================================
# APPLY SYSCTL HARDENING
# ==================================================

apply_sysctl_hardening() {

    if ! backup_config; then
        echo "ERROR: Could not back up existing sysctl configuration."
        return 1
    fi

    TEMP_CONFIG="$(mktemp)"

    cat > "$TEMP_CONFIG" <<'EOF'
# CyberPatriot Kernel Security Hardening
# Generated by Kernel_Security.sh

# Address Space Layout Randomization
kernel.randomize_va_space = 2

# Kernel pointer restrictions
kernel.kptr_restrict = 2

# Restrict kernel message access
kernel.dmesg_restrict = 1

# Disable SUID core dumps
fs.suid_dumpable = 0

# IPv4 redirect protection
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# IPv4 source routing protection
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1

# IPv6 redirect protection
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Log IPv4 martian/impossible addresses
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF

    chmod 644 "$TEMP_CONFIG"

    if ! mv "$TEMP_CONFIG" "$CONFIG"; then
        echo "ERROR: Could not install sysctl configuration."
        rm -f "$TEMP_CONFIG"
        return 1
    fi

    if sysctl --load="$CONFIG"; then
        check PASS "Kernel security settings applied."
        return 0
    else
        echo "ERROR: Some sysctl settings could not be applied."
        check WARNING "Kernel settings require additional review."
        return 1
    fi
}

# ==================================================
# PASSWORD HASHING HARDENING
# ==================================================

apply_password_hashing_hardening() {

    echo
    echo "=============================================="
    echo "       PASSWORD HASHING HARDENING"
    echo "=============================================="

    echo
    echo "The script will check whether yescrypt is supported."
    echo "If yescrypt is supported, it will be configured."
    echo "Otherwise, SHA-512 will be used where appropriate."
    echo
    echo "A backup of the relevant authentication configuration"
    echo "will be created before changes are attempted."
    echo

    read -rp "Apply secure password hashing configuration? (y/n): " HASH_CONFIRM

    if [[ ! "$HASH_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Password hashing changes cancelled."
        return 0
    fi

    backup_password_config

    # --------------------------------------------------
    # Debian / Ubuntu / Mint / Pop!_OS
    # --------------------------------------------------

    if [[ -f /etc/pam.d/common-password ]]; then

        echo
        echo "Debian-family PAM configuration detected."

        if grep -qE '^[[:space:]]*password.*pam_unix\.so' \
            /etc/pam.d/common-password 2>/dev/null; then

            PAM_LINE="$(grep -E \
                '^[[:space:]]*password.*pam_unix\.so' \
                /etc/pam.d/common-password |
                head -n 1)"

            echo
            echo "Current pam_unix configuration:"
            echo "$PAM_LINE"

            if grep -q "yescrypt" /etc/pam.d/common-password 2>/dev/null; then

                check PASS "yescrypt is already configured in PAM."

            elif grep -q "sha512" /etc/pam.d/common-password 2>/dev/null; then

                check PASS "SHA-512 is already configured in PAM."

            else

                if grep -q "yescrypt" /etc/pam.d/common-password 2>/dev/null; then
                    check PASS "yescrypt configuration detected."
                else
                    echo
                    echo "No explicit yescrypt setting was detected."
                    echo
                    echo "Your

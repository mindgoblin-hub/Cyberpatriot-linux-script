
#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL FTP/SFTP MANAGER
# Debian / Ubuntu / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG_FILE="$LOG_DIR/ftp_manager.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ==========================================
# ROOT CHECK
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "Administrator privileges required."
    echo "Run: sudo bash FTP_Manager.sh"
    exit 1
fi

# ==========================================
# DISTRIBUTION DETECTION
# ==========================================

if [[ ! -f /etc/os-release ]]; then
    echo "Cannot identify Linux distribution."
    exit 1
fi

source /etc/os-release

DISTRO="${ID,,}"
FAMILY="${ID_LIKE:-}"

if [[ "$DISTRO" == "ubuntu" ||
      "$DISTRO" == "debian" ||
      "$DISTRO" == "linuxmint" ||
      "$DISTRO" == "pop" ||
      "$FAMILY" == *debian* ]]; then

    PM="apt"

elif [[ "$DISTRO" == "fedora" ||
        "$DISTRO" == "rhel" ||
        "$DISTRO" == "rocky" ||
        "$DISTRO" == "almalinux" ||
        "$DISTRO" == "ol" ||
        "$FAMILY" == *rhel* ||
        "$FAMILY" == *fedora* ]]; then

    PM="dnf"

elif [[ "$DISTRO" == "arch" ||
        "$DISTRO" == "manjaro" ||
        "$DISTRO" == "endeavouros" ||
        "$FAMILY" == *arch* ]]; then

    PM="pacman"

elif [[ "$DISTRO" == *opensuse* ||
        "$FAMILY" == *suse* ]]; then

    PM="zypper"

else
    echo "Unsupported distribution: $PRETTY_NAME"
    exit 1
fi

# ==========================================
# SERVICE DETECTION
# ==========================================

if [[ "$PM" == "apt" ]]; then
    SSH_SERVICE="ssh"
else
    SSH_SERVICE="sshd"
fi

VSFTPD_CONFIG="/etc/vsftpd.conf"
CERT_DIR="/etc/ssl/private"
CERT_FILE="$CERT_DIR/vsftpd.pem"

# ==========================================
# HEADER
# ==========================================

clear

echo "=========================================="
echo "       CYBERPATRIOT FTP MANAGER"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo "Package Manager: $PM"
echo "=========================================="

log "FTP manager started on $PRETTY_NAME"

# ==========================================
# PACKAGE INSTALLATION
# ==========================================

install_package() {

    PACKAGE="$1"

    echo
    echo "[INFO] Installing $PACKAGE"

    case "$PM" in

        apt)
            apt-get update &&
            apt-get install -y "$PACKAGE"
            ;;

        dnf)
            dnf install -y "$PACKAGE"
            ;;

        pacman)
            pacman -S --needed "$PACKAGE"
            ;;

        zypper)
            zypper --non-interactive install "$PACKAGE"
            ;;

    esac

    return $?
}

# ==========================================
# INSTALL FTP SERVER
# ==========================================

install_ftp() {

    echo
    echo "=========================================="
    echo "       INSTALL FTP SERVER"
    echo "=========================================="

    if command -v vsftpd >/dev/null 2>&1; then
        echo "vsftpd is already installed."
        return
    fi

    echo "This will install vsftpd."
    echo "Traditional FTP will require TLS configuration."

    read -rp "Continue? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        return
    fi

    if install_package vsftpd; then
        echo "FTP server installed."
        log "vsftpd installed."
    else
        echo "Installation failed."
        log "vsftpd installation failed."
    fi

    read -rp "Press Enter to continue..."
}

# ==========================================
# INSTALL SFTP SUPPORT
# ==========================================

install_sftp() {

    echo
    echo "=========================================="
    echo "       INSTALL SFTP SUPPORT"
    echo "=========================================="

    if command -v sshd >/dev/null 2>&1; then
        echo "OpenSSH server is already installed."
    else

        echo "Installing OpenSSH server..."

        if install_package openssh-server; then
            echo "OpenSSH server installed."
        else
            echo "Installation failed."
            return
        fi

    fi

    echo
    echo "SFTP is provided by OpenSSH."
    echo "It normally uses the existing SSH service."

    read -rp "Enable SSH service at startup? (yes/no): " CONFIRM

    if [[ "$CONFIRM" == "yes" ]]; then

        if systemctl enable --now "$SSH_SERVICE"; then
            echo "SSH service enabled."
            log "SSH service enabled."
        else
            echo "Could not enable SSH."
            log "SSH service activation failed."
        fi

    fi

    echo
    echo "SFTP uses the SSH server's configured port."
    echo "No separate FTP port is needed."

    read -rp "Press Enter to continue..."
}

# ==========================================
# BACKUP FTP CONFIGURATION
# ==========================================

backup_ftp() {

    BACKUP="$BACKUP_DIR/ftp_$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$BACKUP"

    if [[ -f "$VSFTPD_CONFIG" ]]; then
        cp -a "$VSFTPD_CONFIG" "$BACKUP/"
    fi

    if [[ -f "$CERT_FILE" ]]; then
        cp -a "$CERT_FILE" "$BACKUP/"
    fi

    log "FTP backup created: $BACKUP"

    echo "Backup created:"
    echo "$BACKUP"
}

# ==========================================
# CONFIGURE FTP TLS
# ==========================================

configure_ftp() {

    echo
    echo "=========================================="
    echo "       CONFIGURE SECURE FTP"
    echo "=========================================="

    if ! command -v vsftpd >/dev/null 2>&1; then
        echo "vsftpd is not installed."
        return
    fi

    if ! command -v openssl >/dev/null 2>&1; then

        echo "OpenSSL is required."

        read -rp "Install OpenSSL? (yes/no): " INSTALL

        if [[ "$INSTALL" != "yes" ]]; then
            return
        fi

        install_package openssl || return

    fi

    if [[ -f "$VSFTPD_CONFIG" ]]; then
        backup_ftp
    fi

    mkdir -p "$CERT_DIR"
    chmod 700 "$CERT_DIR"

    # Create a self-signed certificate if needed.

    if [[ ! -f "$CERT_FILE" ]]; then

        echo
        echo "Creating self-signed TLS certificate..."

        if ! openssl req -x509 -nodes -days 365 \
            -newkey rsa:3072 \
            -keyout "$CERT_FILE" \
            -out "$CERT_FILE" \
            -subj "/CN=Linux-FTP-Server"; then

            echo "Certificate generation failed."
            return
        fi

        chmod 600 "$CERT_FILE"

    fi

    echo
    echo "=========================================="
    echo "       FTP SECURITY SETTINGS"
    echo "=========================================="

    echo "Anonymous access: Disabled"
    echo "TLS encryption: Enabled"
    echo "Local authentication: Enabled"
    echo "User confinement: Enabled"
    echo "Uploads: Disabled"
    echo "Passive ports: 40000-40100"

    echo
    echo "Existing vsftpd configuration will be replaced."
    echo "A backup has been created if one existed."

    read -rp "Apply configuration? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Configuration cancelled."
        return
    fi

    cat > "$VSFTPD_CONFIG" <<EOF
# CyberPatriot Secure FTP Configuration

listen=NO
listen_ipv6=YES

anonymous_enable=NO
local_enable=YES
write_enable=NO

local_umask=077

dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

chroot_local_user=YES
allow_writeable_chroot=NO

secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd

ssl_enable=YES
rsa_cert_file=$CERT_FILE
rsa_private_key_file=$CERT_FILE

force_local_logins_ssl=YES
force_local_data_ssl=YES

ssl_tlsv1=NO
ssl_sslv2=NO
ssl_sslv3=NO

require_ssl_reuse=NO
ssl_ciphers=HIGH

pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

hide_ids=YES
EOF

    chmod 600 "$VSFTPD_CONFIG"

    echo
    echo "FTP configuration written."

    echo
    echo "Checking configuration..."

    if ! vsftpd -olisten=NO "$VSFTPD_CONFIG" </dev/null >/dev/null 2>&1; then
        echo "WARNING: Could not validate FTP configuration."
        log "FTP configuration validation requires review."
    else
        echo "Configuration check completed."
    fi

    echo
    echo "Starting FTP service..."

    if systemctl enable --now vsftpd; then
        echo "FTP service enabled."
        log "FTP service enabled."
    else
        echo "FTP service failed to start."
        echo "Check: systemctl status vsftpd"
        log "FTP service failed to start."
    fi

    read -rp "Press Enter to continue..."
}

# ==========================================
# FTP SERVICE MANAGEMENT
# ==========================================

ftp_service() {

    echo
    echo "=========================================="
    echo "       FTP SERVICE MANAGEMENT"
    echo "=========================================="

    echo
    echo "1. Start FTP"
    echo "2. Stop FTP"
    echo "3. Restart FTP"
    echo "4. Enable at startup"
    echo "5. Disable at startup"
    echo "6. View service status"
    echo "0. Back"

    read -rp "Selection: " OPTION

    case "$OPTION" in

        1)
            systemctl start vsftpd
            ;;

        2)
            systemctl stop vsftpd
            ;;

        3)
            systemctl restart vsftpd
            ;;

        4)
            systemctl enable vsftpd
            ;;

        5)
            systemctl disable vsftpd
            ;;

        6)
            systemctl status vsftpd --no-pager
            ;;

        0)
            return
            ;;

        *)
            echo "Invalid selection."
            ;;

    esac

    read -rp "Press Enter to continue..."
}

# ==========================================
# SFTP SERVICE STATUS
# ==========================================

sftp_status() {

    echo
    echo "=========================================="
    echo "       SFTP / SSH STATUS"
    echo "=========================================="

    systemctl status "$SSH_SERVICE" --no-pager

    echo
    echo "SSH listening ports:"

    if command -v ss >/dev/null 2>&1; then
        ss -lntp | grep -E 'sshd|:22[[:space:]]' || true
    fi

    echo
    echo "SFTP subsystem configuration:"

    grep -RniE '^[[:space:]]*Subsystem[[:space:]]+sftp' \
        /etc/ssh/sshd_config /etc/ssh/sshd_config.d \
        2>/dev/null || true

    read -rp "Press Enter to continue..."
}

# ==========================================
# FTP SECURITY AUDIT
# ==========================================

security_audit() {

    echo
    echo "=========================================="
    echo "       FTP SECURITY AUDIT"
    echo "=========================================="

    if [[ ! -f "$VSFTPD_CONFIG" ]]; then
        echo "vsftpd configuration not found."
        return
    fi

    echo
    echo "Checking important FTP settings..."
    echo

    CHECKS=(
        "anonymous_enable=NO"
        "local_enable=YES"
        "write_enable=NO"
        "ssl_enable=YES"
        "force_local_logins_ssl=YES"
        "force_local_data_ssl=YES"
        "chroot_local_user=YES"
    )

    for SETTING in "${CHECKS[@]}"; do

        if grep -Fxq "$SETTING" "$VSFTPD_CONFIG"; then
            echo "[PASS] $SETTING"
        else
            echo "[REVIEW] $SETTING"
        fi

    done

    echo
    echo "FTP service status:"

    systemctl is-active vsftpd 2>/dev/null ||
        echo "FTP service inactive."

    echo
    echo "FTP startup status:"

    systemctl is-enabled vsftpd 2>/dev/null ||
        echo "FTP service not enabled."

    echo
    echo "Checking anonymous FTP accounts..."

    grep -nE '^[[:space:]]*anonymous_enable=' \
        "$VSFTPD_CONFIG" || true

    echo
    echo "SSH/SFTP service status:"

    systemctl is-active "$SSH_SERVICE" 2>/dev/null ||
        echo "SSH service inactive."

    log "FTP security audit completed."

    echo
    read -rp "Press Enter to continue..."
}

# ==========================================
# FTP USER REVIEW
# ==========================================

user_audit() {

    echo
    echo "=========================================="
    echo "       FTP USER ACCOUNT REVIEW"
    echo "=========================================="

    echo
    echo "Interactive login accounts:"
    echo

    while IFS=: read -r USER _ UID GID GECOS HOME SHELL; do

        [[ -n "$SHELL" ]] || continue

        if [[ -f /etc/shells ]] &&
           grep -Fxq "$SHELL" /etc/shells; then

            printf "%-20s %-10s %-30s\n" \
                "$USER" "$UID" "$SHELL"

        fi

    done < /etc/passwd

    echo
    echo "Note: This lists interactive accounts, not"
    echo "accounts specifically authorized for FTP."

    echo "FTP authorization depends on PAM and"
    echo "the server's account restrictions."

    echo
    read -rp "Press Enter to continue..."
}

# ==========================================
# FIREWALL INFORMATION
# ==========================================

firewall_info() {

    echo
    echo "=========================================="
    echo "       FTP FIREWALL INFORMATION"
    echo "=========================================="

    echo
    echo "FTP requires:"
    echo
    echo "TCP 21          FTP control connection"
    echo "TCP 40000-40100 Passive data connections"
    echo
    echo "SFTP requires:"
    echo
    echo "Your existing SSH TCP port (usually 22)."

    echo
    echo "Detected firewall tools:"

    command -v ufw >/dev/null 2>&1 &&
        echo "- UFW installed"

    command -v firewall-cmd >/dev/null 2>&1 &&
        echo "- firewalld installed"

    command -v nft >/dev/null 2>&1 &&
        echo "- nftables installed"

    echo
    echo "IMPORTANT:"
    echo "Only expose FTP ports on networks where"
    echo "FTP access is actually required."
    echo
    echo "Do not expose FTP directly to the Internet"
    echo "without reviewing NAT, TLS certificates,"
    echo "access controls and firewall policy."

    echo
    echo "For SFTP, permit only the configured SSH port."

    read -rp "Press Enter to continue..."
}

# ==========================================
# VIEW LOG
# ==========================================

view_log() {

    if [[ -f "$LOG_FILE" ]]; then

        if command -v less >/dev/null 2>&1; then
            less "$LOG_FILE"
        else
            cat "$LOG_FILE"
        fi

    else
        echo "No logs available."
    fi

    read -rp "Press Enter to continue..."
}

# ==========================================
# MAIN MENU
# ==========================================

while true; do

    clear

    echo "=========================================="
    echo "       CYBERPATRIOT FTP MANAGER"
    echo "=========================================="
    echo "OS: $PRETTY_NAME"
    echo "Package Manager: $PM"
    echo
    echo "1. Install FTP server"
    echo "2. Install SFTP support"
    echo "3. Configure secure FTP"
    echo "4. Manage FTP service"
    echo "5. View SFTP/SSH status"
    echo "6. FTP security audit"
    echo "7. Review user accounts"
    echo "8. View firewall requirements"
    echo "9. View management log"
    echo "0. Return to main launcher"
    echo
    echo "=========================================="

    read -rp "Select an option: " CHOICE

    case "$CHOICE" in

        1)
            install_ftp
            ;;

        2)
            install_sftp
            ;;

        3)
            configure_ftp
            ;;

        4)
            ftp_service
            ;;

        5)
            sftp_status
            ;;

        6)
            security_audit
            ;;

        7)
            user_audit
            ;;

        8)
            firewall_info
            ;;

        9)
            view_log
            ;;

        0)
            log "FTP manager exited."
            exit 0
            ;;

        *)
            echo "Invalid selection."
            sleep 2
            ;;

    esac

done

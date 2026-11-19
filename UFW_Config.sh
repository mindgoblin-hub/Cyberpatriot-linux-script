#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL FIREWALL MANAGER
# Debian / Ubuntu / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================

# ==========================================
# DIRECTORY CONFIGURATION
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG_FILE="$LOG_DIR/firewall_config.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ==========================================
# ROOT CHECK
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "Administrator privileges required."
    echo "Run: sudo bash Firewall_Config.sh"
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

# ==========================================
# FIREWALL BACKEND SELECTION
# ==========================================

if [[ "$DISTRO" == "ubuntu" ||
      "$DISTRO" == "debian" ||
      "$DISTRO" == "linuxmint" ||
      "$DISTRO" == "pop" ||
      "$FAMILY" == *debian* ]]; then

    FIREWALL="ufw"
    PACKAGE_MANAGER="apt"

elif [[ "$DISTRO" == "fedora" ||
        "$DISTRO" == "rhel" ||
        "$DISTRO" == "rocky" ||
        "$DISTRO" == "almalinux" ||
        "$DISTRO" == "ol" ||
        "$FAMILY" == *rhel* ||
        "$FAMILY" == *fedora* ]]; then

    FIREWALL="firewalld"
    PACKAGE_MANAGER="dnf"

elif [[ "$DISTRO" == "arch" ||
        "$DISTRO" == "manjaro" ||
        "$DISTRO" == "endeavouros" ||
        "$FAMILY" == *arch* ]]; then

    FIREWALL="firewalld"
    PACKAGE_MANAGER="pacman"

elif [[ "$DISTRO" == *opensuse* ||
        "$FAMILY" == *suse* ]]; then

    FIREWALL="firewalld"
    PACKAGE_MANAGER="zypper"

else
    echo "Unsupported distribution: $PRETTY_NAME"
    exit 1
fi

# ==========================================
# HEADER
# ==========================================

clear

echo "=========================================="
echo "       CYBERPATRIOT FIREWALL MANAGER"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo "Firewall:     $FIREWALL"
echo "=========================================="

log "Firewall configuration started: $PRETTY_NAME"

# ==========================================
# INSTALL FIREWALL IF NECESSARY
# ==========================================

if ! command -v "$FIREWALL" >/dev/null 2>&1; then

    echo
    echo "$FIREWALL is not installed."

    read -rp "Install $FIREWALL? (yes/no): " INSTALL

    if [[ "$INSTALL" != "yes" ]]; then
        log "Firewall installation declined."
        exit 0
    fi

    case "$PACKAGE_MANAGER" in

        apt)
            apt-get update &&
            apt-get install -y ufw
            ;;

        dnf)
            dnf install -y firewalld
            ;;

        pacman)
            pacman -S --needed firewalld
            ;;

        zypper)
            zypper --non-interactive install firewalld
            ;;

    esac

    if [[ $? -ne 0 ]]; then
        echo "Firewall installation failed."
        log "Firewall installation failed."
        exit 1
    fi
fi

# ==========================================
# BACKUP CONFIGURATION
# ==========================================

BACKUP="$BACKUP_DIR/firewall_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP"

if [[ "$FIREWALL" == "ufw" ]]; then

    if [[ -d /etc/ufw ]]; then
        cp -a /etc/ufw "$BACKUP/"
    fi

    if [[ -f /etc/default/ufw ]]; then
        cp -a /etc/default/ufw "$BACKUP/"
    fi

else

    if [[ -d /etc/firewalld ]]; then
        cp -a /etc/firewalld "$BACKUP/"
    fi

fi

log "Firewall backup created: $BACKUP"

# ==========================================
# PORT INPUT VALIDATION
# ==========================================

validate_ports() {

    local INPUT="$1"
    local OUTPUT=""

    # Convert commas to spaces
    INPUT="${INPUT//,/ }"

    for PORT in $INPUT; do

        if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
            echo "Invalid port: $PORT"
            return 1
        fi

        if (( PORT < 1 || PORT > 65535 )); then
            echo "Port out of range: $PORT"
            return 1
        fi

        if [[ -z "$OUTPUT" ]]; then
            OUTPUT="$PORT"
        else
            OUTPUT="$OUTPUT,$PORT"
        fi

    done

    echo "$OUTPUT"
}

# ==========================================
# UFW CONFIGURATION
# ==========================================

configure_ufw() {

    echo
    echo "=========================================="
    echo "          CURRENT UFW STATUS"
    echo "=========================================="

    ufw status verbose
    echo
    ufw status numbered

    echo
    echo "Existing firewall rules will be preserved."
    echo

    read -rp "Continue? (yes/no): " CONTINUE

    if [[ "$CONTINUE" != "yes" ]]; then
        log "UFW configuration cancelled."
        return
    fi

    # ======================================
    # TCP PORTS
    # ======================================

    echo
    echo "=========================================="
    echo "              TCP PORTS"
    echo "=========================================="

    echo "Enter TCP ports that should be allowed."
    echo "Examples:"
    echo "  22"
    echo "  22 80 443"
    echo "  22,80,443"
    echo
    echo "Leave blank if no TCP ports should be allowed."

    read -rp "TCP ports: " TCP_INPUT

    if [[ -n "$TCP_INPUT" ]]; then

        TCP_PORTS=$(validate_ports "$TCP_INPUT")

        if [[ $? -ne 0 ]]; then
            echo "Invalid TCP port list."
            log "Invalid TCP port input."
            return
        fi

    else
        TCP_PORTS=""
    fi

    # ======================================
    # UDP PORTS
    # ======================================

    echo
    echo "=========================================="
    echo "              UDP PORTS"
    echo "=========================================="

    echo "Enter UDP ports that should be allowed."
    echo "Examples:"
    echo "  53"
    echo "  53 67 68"
    echo "  53,67,68"
    echo
    echo "Leave blank if no UDP ports should be allowed."

    read -rp "UDP ports: " UDP_INPUT

    if [[ -n "$UDP_INPUT" ]]; then

        UDP_PORTS=$(validate_ports "$UDP_INPUT")

        if [[ $? -ne 0 ]]; then
            echo "Invalid UDP port list."
            log "Invalid UDP port input."
            return
        fi

    else
        UDP_PORTS=""
    fi

    # ======================================
    # SSH DETECTION
    # ======================================

    SSH_PORT=""

    if [[ -n "${SSH_CONNECTION:-}" ]]; then

        SSH_PORT=$(awk '{print $4}' <<< "$SSH_CONNECTION")

        echo
        echo "SSH connection detected."
        echo "Current SSH server port: $SSH_PORT"

        if [[ "$TCP_PORTS" != *"$SSH_PORT"* ]]; then
            echo
            echo "WARNING: Your current SSH port is not in the TCP"
            echo "allow list."
            echo
            read -rp "Automatically add SSH port $SSH_PORT to TCP? (yes/no): " SSH_ADD

            if [[ "$SSH_ADD" == "yes" ]]; then

                if [[ -z "$TCP_PORTS" ]]; then
                    TCP_PORTS="$SSH_PORT"
                else
                    TCP_PORTS="$TCP_PORTS,$SSH_PORT"
                fi

            else
                echo
                echo "WARNING: Continuing without allowing SSH may"
                echo "disconnect your current session."
                read -rp "Continue anyway? (yes/no): " SSH_CONTINUE

                if [[ "$SSH_CONTINUE" != "yes" ]]; then
                    log "UFW configuration cancelled to protect SSH access."
                    return
                fi
            fi
        fi

    fi

    # ======================================
    # SHOW PROPOSED POLICY
    # ======================================

    echo
    echo "=========================================="
    echo "         PROPOSED UFW POLICY"
    echo "=========================================="

    echo
    echo "TCP:"
    echo "  Allowed: ${TCP_PORTS:-NONE}"
    echo "  Everything else: DENY"

    echo
    echo "UDP:"
    echo "  Allowed: ${UDP_PORTS:-NONE}"
    echo "  Everything else: DENY"

    echo
    echo "Incoming: DENY"
    echo "Outgoing: ALLOW"
    echo "Routed:   DENY"
    echo "Logging:  ON"

    echo
    echo "Existing UFW rules are preserved."
    echo
    echo "WARNING: Incorrect port selections may interrupt"
    echo "network services or remote administration."

    read -rp "Apply this firewall policy? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "UFW changes declined."
        return
    fi

    # ======================================
    # DEFAULT DENY POLICY
    # ======================================

    FAILED=0

    echo
    echo "Configuring firewall defaults..."

    ufw default deny incoming || FAILED=1
    ufw default allow outgoing || FAILED=1
    ufw default deny routed || FAILED=1

    # ======================================
    # TCP RULES
    # ======================================

    echo
    echo "Configuring TCP rules..."

    if [[ -n "$TCP_PORTS" ]]; then

        IFS=',' read -ra TCP_ARRAY <<< "$TCP_PORTS"

        for PORT in "${TCP_ARRAY[@]}"; do
            echo "Allowing TCP port $PORT..."
            ufw allow "$PORT/tcp" || FAILED=1
        done

    else
        echo "No TCP ports will be allowed."
    fi

    # ======================================
    # UDP RULES
    # ======================================

    echo
    echo "Configuring UDP rules..."

    if [[ -n "$UDP_PORTS" ]]; then

        IFS=',' read -ra UDP_ARRAY <<< "$UDP_PORTS"

        for PORT in "${UDP_ARRAY[@]}"; do
            echo "Allowing UDP port $PORT..."
            ufw allow "$PORT/udp" || FAILED=1
        done

    else
        echo "No UDP ports will be allowed."
    fi

    # ======================================
    # LOGGING
    # ======================================

    echo
    echo "Enabling firewall logging..."

    ufw logging on || FAILED=1

    if [[ "$FAILED" -ne 0 ]]; then

        echo
        echo "Firewall configuration encountered errors."
        log "UFW configuration failed."

        return

    fi

    # ======================================
    # ENABLE FIREWALL
    # ======================================

    echo
    read -rp "Enable UFW now? (yes/no): " ENABLE

    if [[ "$ENABLE" == "yes" ]]; then

        if ufw --force enable; then

            echo
            echo "UFW enabled successfully."
            log "UFW enabled."

        else

            echo
            echo "UFW activation failed."
            log "UFW activation failed."
            return

        fi

    else

        echo
        echo "UFW rules configured but not enabled."
        log "UFW activation deferred."

    fi

    echo
    echo "=========================================="
    echo "            FINAL UFW RULES"
    echo "=========================================="

    ufw status verbose
}

# ==========================================
# FIREWALLD CONFIGURATION
# ==========================================

configure_firewalld() {

    echo
    echo "=========================================="
    echo "         CURRENT FIREWALLD STATUS"
    echo "=========================================="

    systemctl status firewalld --no-pager 2>/dev/null || true

    echo
    echo "Default zone:"
    firewall-cmd --get-default-zone

    DEFAULT_ZONE=$(firewall-cmd --get-default-zone)

    echo
    echo "Active zones:"
    firewall-cmd --get-active-zones

    echo
    echo "Current firewall configuration:"
    firewall-cmd --zone="$DEFAULT_ZONE" --list-all

    echo
    echo "Existing zones, services and rules will be preserved."
    echo "No firewall zone will be replaced."

    read -rp "Continue? (yes/no): " CONTINUE

    if [[ "$CONTINUE" != "yes" ]]; then
        log "Firewalld configuration cancelled."
        return
    fi

    # ======================================
    # TCP PORTS
    # ======================================

    echo
    echo "=========================================="
    echo "              TCP PORTS"
    echo "=========================================="

    echo "Enter TCP ports that should be allowed."
    echo "Examples:"
    echo "  22"
    echo "  22 80 443"
    echo "  22,80,443"
    echo
    echo "Leave blank if no TCP ports should be allowed."

    read -rp "TCP ports: " TCP_INPUT

    if [[ -n "$TCP_INPUT" ]]; then

        TCP_PORTS=$(validate_ports "$TCP_INPUT")

        if [[ $? -ne 0 ]]; then
            echo "Invalid TCP port list."
            log "Invalid TCP port input."
            return
        fi

    else
        TCP_PORTS=""
    fi

    # ======================================
    # UDP PORTS
    # ======================================

    echo
    echo "=========================================="
    echo "              UDP PORTS"
    echo "=========================================="

    echo "Enter UDP ports that should be allowed."
    echo "Examples:"
    echo "  53"
    echo "  53 67 68"
    echo "  53,67,68"
    echo
    echo "Leave blank if no UDP ports should be allowed."

    read -rp "UDP ports: " UDP_INPUT

    if [[ -n "$UDP_INPUT" ]]; then

        UDP_PORTS=$(validate_ports "$UDP_INPUT")

        if [[ $? -ne 0 ]]; then
            echo "Invalid UDP port list."
            log "Invalid UDP port input."
            return
        fi

    else
        UDP_PORTS=""
    fi

    # ======================================
    # SHOW PROPOSED POLICY
    # ======================================

    echo
    echo "=========================================="
    echo "      PROPOSED FIREWALLD POLICY"
    echo "=========================================="

    echo
    echo "Zone: $DEFAULT_ZONE"

    echo
    echo "TCP:"
    echo "  Allowed: ${TCP_PORTS:-NONE}"
    echo "  Everything else: DENY"

    echo
    echo "UDP:"
    echo "  Allowed: ${UDP_PORTS:-NONE}"
    echo "  Everything else: DENY"

    echo
    echo "Existing firewalld configuration: PRESERVED"

    echo
    echo "WARNING: Incorrect port selections may interrupt"
    echo "network services or remote administration."

    read -rp "Apply this firewall policy? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "Firewalld changes declined."
        return
    fi

    # ======================================
    # START FIREWALLD
    # ======================================

    if ! systemctl enable --now firewalld; then

        echo "Could not start firewalld."
        log "Firewalld activation failed."
        return

    fi

    # ======================================
    # TCP RULES
    # ======================================

    echo
    echo "Configuring TCP rules..."

    if [[ -n "$TCP_PORTS" ]]; then

        IFS=',' read -ra TCP_ARRAY <<< "$TCP_PORTS"

        for PORT in "${TCP_ARRAY[@]}"; do

            echo "Allowing TCP port $PORT..."

            if ! firewall-cmd \
                --zone="$DEFAULT_ZONE" \
                --add-port="$PORT/tcp" \
                --permanent; then

                echo "Failed to allow TCP port $PORT."
                log "Failed to allow TCP port $PORT."
                return

            fi

        done

    else

        echo "No TCP ports will be allowed."

    fi

    # ======================================
    # UDP RULES
    # ======================================

    echo
    echo "Configuring UDP rules..."

    if [[ -n "$UDP_PORTS" ]]; then

        IFS=',' read -ra UDP_ARRAY <<< "$UDP_PORTS"

        for PORT in "${UDP_ARRAY[@]}"; do

            echo "Allowing UDP port $PORT..."

            if ! firewall-cmd \
                --zone="$DEFAULT_ZONE" \
                --add-port="$PORT/udp" \
                --permanent; then

                echo "Failed to allow UDP port $PORT."
                log "Failed to allow UDP port $PORT."
                return

            fi

        done

    else

        echo "No UDP ports will be allowed."

    fi

    # ======================================
    # RELOAD
    # ======================================

    echo
    echo "Reloading firewalld..."

    if ! firewall-cmd --reload; then

        echo "Firewall reload failed."
        log "Firewalld reload failed."
        return

    fi

    echo
    echo "Firewalld configuration completed."

    log "Firewalld configuration completed."

    echo
    echo "=========================================="
    echo "          FINAL FIREWALL RULES"
    echo "=========================================="

    firewall-cmd --zone="$DEFAULT_ZONE" --list-all
}

# ==========================================
# MAIN FIREWALL MENU
# ==========================================

echo
echo "Detected firewall backend: $FIREWALL"

case "$FIREWALL" in

    ufw)
        configure_ufw
        ;;

    firewalld)
        configure_firewalld
        ;;

esac

# ==========================================
# FINAL STATUS
# ==========================================

echo
echo "=========================================="
echo "         FINAL FIREWALL STATUS"
echo "=========================================="

if [[ "$FIREWALL" == "ufw" ]]; then

    ufw status verbose

else

    firewall-cmd --state
    firewall-cmd --list-all

fi

echo
echo "Backup: $BACKUP"
echo "Log: $LOG_FILE"

log "Firewall management finished."

echo
read -rp "Press Enter to return to launcher..."

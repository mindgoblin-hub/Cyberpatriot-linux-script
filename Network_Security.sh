
#!/bin/bash

# ==================================================
# CYBERPATRIOT UNIVERSAL NETWORK SECURITY AUDITOR
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==================================================

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG="$LOG_DIR/network_security.log"
REPORT="$LOG_DIR/network_report_$(date +%Y%m%d_%H%M%S).txt"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

source /etc/os-release 2>/dev/null || true

PASS=0
WARN=0
CRITICAL=0
INFO=0

# ==================================================
# LOGGING
# ==================================================

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

check() {
    local LEVEL="$1"
    local MESSAGE="$2"

    case "$LEVEL" in
        PASS) ((PASS+=1)) ;;
        WARNING) ((WARN+=1)) ;;
        CRITICAL) ((CRITICAL+=1)) ;;
        INFO) ((INFO+=1)) ;;
    esac

    log "[$LEVEL] $MESSAGE"
}

# ==================================================
# HEADER
# ==================================================

echo "=============================================="
echo "      CYBERPATRIOT NETWORK SECURITY AUDIT"
echo "=============================================="

echo "Operating System: ${PRETTY_NAME:-Unknown}"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date)"
echo

# ==================================================
# NETWORK INTERFACE AUDIT
# ==================================================

echo "[1] NETWORK INTERFACES"
echo "----------------------------------------------"

if command -v ip >/dev/null 2>&1; then

    ip -brief address show

    check INFO "Network interface inventory collected."

    echo
    echo "Detailed interface information:"
    ip -details link show

else

    check CRITICAL "ip command unavailable."

fi

echo

# ==================================================
# ACTIVE INTERFACE AUDIT
# ==================================================

echo "[2] ACTIVE NETWORK INTERFACES"
echo "----------------------------------------------"

if command -v ip >/dev/null 2>&1; then

    ACTIVE_INTERFACES="$(ip -o link show up 2>/dev/null)"

    if [[ -n "$ACTIVE_INTERFACES" ]]; then

        echo "$ACTIVE_INTERFACES"
        check PASS "Active network interfaces detected."

    else

        check WARNING "No active network interfaces detected."

    fi

fi

echo

# ==================================================
# PROMISCUOUS MODE AUDIT
# ==================================================

echo "[3] PROMISCUOUS MODE AUDIT"
echo "----------------------------------------------"

if command -v ip >/dev/null 2>&1; then

    PROMISC="$(ip -details link show 2>/dev/null |
        grep -i PROMISC || true)"

    if [[ -n "$PROMISC" ]]; then

        echo "$PROMISC"

        check WARNING "Network interfaces operating in promiscuous mode detected."

    else

        check PASS "No interfaces reported in promiscuous mode."

    fi

fi

echo

# ==================================================
# LISTENING PORT AUDIT
# ==================================================

echo "[4] LISTENING NETWORK PORTS"
echo "----------------------------------------------"

if command -v ss >/dev/null 2>&1; then

    LISTENING="$(ss -tulpen 2>/dev/null)"

    echo "$LISTENING"

    if [[ -n "$LISTENING" ]]; then
        check INFO "Listening network sockets collected."
    else
        check INFO "No listening sockets detected."
    fi

elif command -v netstat >/dev/null 2>&1; then

    netstat -tulpen 2>/dev/null

    check INFO "Network sockets collected using netstat."

else

    check WARNING "Neither ss nor netstat is available."

fi

echo

# ==================================================
# ACTIVE CONNECTION AUDIT
# ==================================================

echo "[5] ACTIVE CONNECTIONS"
echo "----------------------------------------------"

if command -v ss >/dev/null 2>&1; then

    ss -tunap 2>/dev/null | head -n 40

    check INFO "Active network connections reviewed."

else

    check INFO "Connection inspection unavailable."

fi

echo

# ==================================================
# FIREWALL AUDIT
# ==================================================

echo "[6] FIREWALL STATUS"
echo "----------------------------------------------"

FIREWALL_FOUND=0

# UFW

if command -v ufw >/dev/null 2>&1; then

    ((FIREWALL_FOUND+=1))

    UFW_STATUS="$(ufw status 2>/dev/null || true)"

    echo
    echo "UFW:"
    echo "$UFW_STATUS"

    if grep -qi "Status: active" <<< "$UFW_STATUS"; then
        check PASS "UFW firewall is active."
    else
        check WARNING "UFW firewall is inactive."
    fi

fi

# FIREWALLD

if command -v firewall-cmd >/dev/null 2>&1; then

    ((FIREWALL_FOUND+=1))

    FIREWALLD_STATUS="$(firewall-cmd --state 2>/dev/null || true)"

    echo
    echo "Firewalld:"
    echo "$FIREWALLD_STATUS"

    if [[ "$FIREWALLD_STATUS" == "running" ]]; then

        check PASS "Firewalld is running."

        firewall-cmd --get-active-zones 2>/dev/null || true

    else

        check WARNING "Firewalld is not running."

    fi

fi

# NFTABLES

if command -v nft >/dev/null 2>&1; then

    ((FIREWALL_FOUND+=1))

    echo
    echo "Nftables ruleset:"

    nft list ruleset 2>/dev/null | head -n 60

    check INFO "Nftables ruleset reviewed."

fi

# IPTABLES

if command -v iptables >/dev/null 2>&1; then

    ((FIREWALL_FOUND+=1))

    echo
    echo "IPTables policies:"

    iptables -L -n -v 2>/dev/null | head -n 40

    check INFO "IPTables firewall configuration reviewed."

fi

if ((FIREWALL_FOUND == 0)); then

    check WARNING "No recognized firewall management utility found."

fi

echo

# ==================================================
# IP FORWARDING AUDIT
# ==================================================

echo "[7] IP FORWARDING"
echo "----------------------------------------------"

IPV4_FORWARD="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo unavailable)"

echo "IPv4 forwarding: $IPV4_FORWARD"

if [[ "$IPV4_FORWARD" == "0" ]]; then

    check PASS "IPv4 forwarding disabled."

elif [[ "$IPV4_FORWARD" == "1" ]]; then

    check WARNING "IPv4 forwarding enabled. Verify whether routing is required."

else

    check INFO "IPv4 forwarding unavailable."

fi

IPV6_FORWARD="$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo unavailable)"

echo "IPv6 forwarding: $IPV6_FORWARD"

if [[ "$IPV6_FORWARD" == "0" ]]; then

    check PASS "IPv6 forwarding disabled."

elif [[ "$IPV6_FORWARD" == "1" ]]; then

    check WARNING "IPv6 forwarding enabled. Verify whether routing is required."

else

    check INFO "IPv6 forwarding unavailable."

fi

echo

# ==================================================
# ROUTING TABLE AUDIT
# ==================================================

echo "[8] ROUTING TABLE"
echo "----------------------------------------------"

if command -v ip >/dev/null 2>&1; then

    echo "IPv4 routes:"
    ip route show

    echo
    echo "IPv6 routes:"
    ip -6 route show

    check INFO "Network routing tables collected."

else

    check WARNING "Cannot inspect routing tables."

fi

echo

# ==================================================
# DNS CONFIGURATION AUDIT
# ==================================================

echo "[9] DNS CONFIGURATION"
echo "----------------------------------------------"

if [[ -f /etc/resolv.conf ]]; then

    echo "DNS configuration:"
    cat /etc/resolv.conf

    OWNER="$(stat -c '%U' /etc/resolv.conf)"
    MODE="$(stat -c '%a' /etc/resolv.conf)"

    if [[ "$OWNER" == "root" ]]; then

        check PASS "DNS configuration file owned by root."

    else

        check WARNING "DNS configuration owned by $OWNER."

    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then

        check PASS "DNS configuration is not writable by group or others."

    else

        check WARNING "DNS configuration permissions require review."

    fi

else

    check WARNING "/etc/resolv.conf missing."

fi

echo

# ==================================================
# NETWORK SERVICE AUDIT
# ==================================================

echo "[10] NETWORK SERVICE AUDIT"
echo "----------------------------------------------"

NETWORK_SERVICES=(
    NetworkManager.service
    systemd-networkd.service
    networking.service
    wpa_supplicant.service
    ssh.service
    sshd.service
    avahi-daemon.service
    rpcbind.service
    nfs-server.service
    smbd.service
    nmb.service
)

for SERVICE in "${NETWORK_SERVICES[@]}"; do

    LOAD_STATE="$(systemctl show "$SERVICE" \
        -p LoadState --value 2>/dev/null || true)"

    [[ "$LOAD_STATE" == "loaded" ]] || continue

    ACTIVE="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"

    ENABLED="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

    echo
    echo "Service: $SERVICE"
    echo "Status: $ACTIVE"
    echo "Enabled: $ENABLED"

    check INFO "$SERVICE network service reviewed."

done

echo

# ==================================================
# HOSTS FILE AUDIT
# ==================================================

echo "[11] HOSTS FILE AUDIT"
echo "----------------------------------------------"

if [[ -f /etc/hosts ]]; then

    stat -c '%A %U:%G %n' /etc/hosts

    OWNER="$(stat -c '%U' /etc/hosts)"
    MODE="$(stat -c '%a' /etc/hosts)"

    if [[ "$OWNER" == "root" ]]; then
        check PASS "/etc/hosts owned by root."
    else
        check WARNING "/etc/hosts owned by $OWNER."
    fi

    if [[ "$MODE" =~ ^[0-7]+$ ]] &&
       (( (8#$MODE & 8#022) == 0 )); then
        check PASS "/etc/hosts not writable by group or others."
    else
        check WARNING "/etc/hosts has unsafe write permissions."
    fi

    echo
    cat /etc/hosts

else

    check WARNING "/etc/hosts missing."

fi

echo

# ==================================================
# NETWORK MANAGER AUDIT
# ==================================================

echo "[12] NETWORK MANAGER"
echo "----------------------------------------------"

if command -v nmcli >/dev/null 2>&1; then

    nmcli general status 2>/dev/null || true

    echo
    nmcli connection show --active 2>/dev/null || true

    check INFO "NetworkManager configuration reviewed."

else

    check INFO "NetworkManager utility unavailable."

fi

echo

# ==================================================
# REPORT GENERATION
# ==================================================

{
    echo "CYBERPATRIOT NETWORK SECURITY REPORT"
    echo "Operating System: ${PRETTY_NAME:-Unknown}"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Date: $(date)"

    echo
    echo "NETWORK INTERFACES"
    ip -brief address show 2>/dev/null || true

    echo
    echo "LISTENING PORTS"
    ss -tulpen 2>/dev/null || true

    echo
    echo "ACTIVE CONNECTIONS"
    ss -tunap 2>/dev/null || true

    echo
    echo "ROUTING TABLE"
    ip route show 2>/dev/null || true

    echo
    echo "DNS CONFIGURATION"
    cat /etc/resolv.conf 2>/dev/null || true

    echo
    echo "FIREWALL STATUS"
    ufw status 2>/dev/null || true
    firewall-cmd --state 2>/dev/null || true
    nft list ruleset 2>/dev/null || true

    echo
    echo "IPTABLES"
    iptables -L -n -v 2>/dev/null || true

} > "$REPORT"

check PASS "Network security report generated."

# ==================================================
# AUDIT SUMMARY
# ==================================================

echo
echo "=============================================="
echo "             AUDIT SUMMARY"
echo "=============================================="

echo "Passed:   $PASS"
echo "Warnings: $WARN"
echo "Critical: $CRITICAL"
echo "Info:     $INFO"

echo
echo "Log: $LOG"
echo "Report: $REPORT"

log "Network audit completed: PASS=$PASS WARNING=$WARN CRITICAL=$CRITICAL INFO=$INFO"

# ==================================================
# INTERACTIVE NETWORK SECURITY MENU
# ==================================================

echo
read -rp "Would you like to review network security options? (y/n): " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    echo "No changes made."
    exit 0
fi

echo
echo "=============================================="
echo "         NETWORK SECURITY MENU"
echo "=============================================="
echo
echo "1. Review firewall status."
echo "2. Review listening ports."
echo "3. Review network interfaces."
echo "4. Review routing tables."
echo "5. Review DNS configuration."
echo "6. Review network services."
echo "7. Review firewall rules."
echo "8. Display network security report."
echo "0. Exit."
echo

read -rp "Select an option: " OPTION

case "$OPTION" in

    1)

        echo
        echo "UFW:"
        ufw status verbose 2>/dev/null || true

        echo
        echo "Firewalld:"
        firewall-cmd --list-all 2>/dev/null || true

        ;;

    2)

        ss -tulpen 2>/dev/null || \
            netstat -tulpen 2>/dev/null || \
            echo "No network inspection utility found."

        ;;

    3)

        ip -details address show 2>/dev/null

        ;;

    4)

        echo "IPv4 routes:"
        ip route show

        echo
        echo "IPv6 routes:"
        ip -6 route show

        ;;

    5)

        echo "DNS configuration:"
        cat /etc/resolv.conf

        ;;

    6)

        for SERVICE in "${NETWORK_SERVICES[@]}"; do

            if systemctl show "$SERVICE" \
                -p LoadState --value 2>/dev/null |
                grep -q loaded; then

                systemctl status "$SERVICE" \
                    --no-pager 2>/dev/null || true

            fi

        done

        ;;

    7)

        echo "UFW:"
        ufw status verbose 2>/dev/null || true

        echo
        echo "Firewalld:"
        firewall-cmd --list-all 2>/dev/null || true

        echo
        echo "Nftables:"
        nft list ruleset 2>/dev/null || true

        echo
        echo "IPTables:"
        iptables -L -n -v 2>/dev/null || true

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

# ==================================================
# FINAL VERIFICATION
# ==================================================

echo
echo "=============================================="
echo "       FINAL NETWORK VERIFICATION"
echo "=============================================="

echo "Network interfaces:"
ip -brief address show 2>/dev/null || true

echo
echo "Listening ports:"
ss -tulpen 2>/dev/null || true

echo
echo "Firewall status:"
ufw status 2>/dev/null || \
    firewall-cmd --state 2>/dev/null || \
    echo "No recognized firewall status available."

echo
echo "Network security session completed."
echo "Log: $LOG"
echo "Report: $REPORT"

log "Network security session completed."

exit 0

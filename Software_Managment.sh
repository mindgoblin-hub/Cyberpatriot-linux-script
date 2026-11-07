
#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL SOFTWARE MANAGEMENT
# Ubuntu / Debian / Mint / Pop!_OS
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

LOG_FILE="$LOG_DIR/software_management.log"
INVENTORY="$BACKUP_DIR/installed_software.tsv"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

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

elif [[ "$DISTRO" == "opensuse" ||
        "$DISTRO" == "opensuse-leap" ||
        "$DISTRO" == "opensuse-tumbleweed" ||
        "$FAMILY" == *suse* ]]; then

    PM="zypper"

else
    echo "Unsupported distribution: $PRETTY_NAME"
    exit 1
fi

# ==========================================
# PACKAGE MANAGER VERIFICATION
# ==========================================

if ! command -v "$PM" >/dev/null 2>&1; then
    echo "Required package manager not found: $PM"
    exit 1
fi

# ==========================================
# ROOT / SUDO HANDLING
# ==========================================

if [[ $EUID -eq 0 ]]; then
    SUDO=()
else
    if ! command -v sudo >/dev/null 2>&1; then
        echo "Sudo is required for package management."
        exit 1
    fi

    SUDO=(sudo)
fi

run_root() {
    "${SUDO[@]}" "$@"
}

# ==========================================
# HEADER
# ==========================================

echo
echo "=========================================="
echo "    CYBERPATRIOT SOFTWARE MANAGEMENT"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo "Package Manager: $PM"
echo "=========================================="

log "Software management started: $PRETTY_NAME ($PM)"

# ==========================================
# INVENTORY
# ==========================================

inventory() {

    echo
    echo "[INFO] Creating installed software inventory..."

    case "$PM" in

        apt)
            dpkg-query -W \
                -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' \
                2>/dev/null |
                awk -F '\t' '$3 == "installed" {
                    print $1 "\t" $2
                }' | sort > "$INVENTORY"
            ;;

        dnf|zypper)
            rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' \
                2>/dev/null | sort > "$INVENTORY"
            ;;

        pacman)
            pacman -Q 2>/dev/null | sort > "$INVENTORY"
            ;;

    esac

    log "Software inventory created."

    echo
    echo "Inventory saved to:"
    echo "$INVENTORY"

    echo
    echo "Installed package count:"
    wc -l < "$INVENTORY"

    if [[ "$PM" == "apt" ]]; then
        echo
        echo "Manually installed packages:"
        apt-mark showmanual | sort
    fi

    echo
    read -rp "Press Enter to continue..."
}

# ==========================================
# HARDENING SOFTWARE INSTALLATION
# ==========================================

install_hardening() {

    echo
    echo "=========================================="
    echo "       SECURITY SOFTWARE INSTALLER"
    echo "=========================================="

    case "$PM" in

        apt)
            PACKAGES=(
                auditd
                aide
                fail2ban
                lynis
                apparmor
                apparmor-utils
            )
            ;;

        dnf)
            PACKAGES=(
                audit
                aide
                fail2ban
                lynis
                policycoreutils-python-utils
            )
            ;;

        pacman)
            PACKAGES=(
                audit
                aide
                fail2ban
                lynis
                apparmor
            )
            ;;

        zypper)
            PACKAGES=(
                audit
                aide
                fail2ban
                lynis
                apparmor-parser
            )
            ;;

    esac

    echo
    echo "The following security packages will be attempted:"
    echo

    for PACKAGE in "${PACKAGES[@]}"; do
        echo "- $PACKAGE"
    done

    echo
    echo "WARNING:"
    echo "Some packages may not exist in every repository."
    echo "Services will NOT automatically be enabled."
    echo

    read -rp "Install these security packages? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "Hardening software installation declined."
        return
    fi

    echo
    echo "[INFO] Refreshing package information..."

    case "$PM" in
        apt)
            run_root apt-get update || {
                echo "Repository update failed."
                return
            }
            ;;
        dnf)
            run_root dnf makecache || {
                echo "Repository refresh failed."
                return
            }
            ;;
        zypper)
            run_root zypper refresh || {
                echo "Repository refresh failed."
                return
            }
            ;;
        pacman)
            echo "Using the existing Arch package database."
            echo "No partial system upgrade will be performed."
            ;;
    esac

    INSTALLED=0
    FAILED=0

    echo
    echo "=========================================="
    echo "       INSTALLING SECURITY SOFTWARE"
    echo "=========================================="

    for PACKAGE in "${PACKAGES[@]}"; do

        echo
        echo "[INFO] Installing: $PACKAGE"

        case "$PM" in

            apt)
                run_root apt-get install -y "$PACKAGE"
                ;;

            dnf)
                run_root dnf install -y "$PACKAGE"
                ;;

            pacman)
                run_root pacman -S --needed "$PACKAGE"
                ;;

            zypper)
                run_root zypper --non-interactive install "$PACKAGE"
                ;;

        esac

        if [[ $? -eq 0 ]]; then
            echo "[SUCCESS] $PACKAGE"
            log "Installed or already present: $PACKAGE"
            INSTALLED=$((INSTALLED + 1))
        else
            echo "[FAILED] $PACKAGE"
            log "Installation failed: $PACKAGE"
            FAILED=$((FAILED + 1))
        fi

    done

    echo
    echo "=========================================="
    echo "       INSTALLATION SUMMARY"
    echo "=========================================="

    echo "Successful: $INSTALLED"
    echo "Failed:     $FAILED"

    log "Hardening installation finished. Success: $INSTALLED Failed: $FAILED"

    echo
    echo "IMPORTANT:"
    echo "Review and configure security services separately."
    echo "AIDE requires an initial trusted database."
    echo "Fail2ban and auditd have not been enabled automatically."

    echo
    read -rp "Press Enter to continue..."
}

# ==========================================
# PACKAGE REMOVAL
# ==========================================

remove_package() {

    echo
    echo "=========================================="
    echo "       REVIEW SOFTWARE REMOVAL"
    echo "=========================================="

    read -rp "Enter exact package name: " PACKAGE

    if [[ ! "$PACKAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._:-]*$ ]]; then
        echo "Invalid package name."
        return
    fi

    # Protect important system components.
    case "$PACKAGE" in
        bash|coreutils|systemd|glibc|libc6|sudo|\
        apt|dpkg|rpm|pacman|zypper|dnf|\
        openssh|openssh-server|linux|linux-firmware|\
        grub|grub2|networkmanager|NetworkManager)

            echo "BLOCKED: Protected system package."
            log "Blocked removal attempt: $PACKAGE"
            return
            ;;
    esac

    echo
    echo "[INFO] Checking package installation..."

    case "$PM" in

        apt)
            STATUS=$(dpkg-query -W -f='${db:Status-Status}' \
                "$PACKAGE" 2>/dev/null)
            [[ "$STATUS" == "installed" ]] || {
                echo "Package is not installed."
                return
            }
            ;;

        dnf)
            rpm -q "$PACKAGE" >/dev/null 2>&1 || {
                echo "Package is not installed."
                return
            }
            ;;

        pacman)
            pacman -Q "$PACKAGE" >/dev/null 2>&1 || {
                echo "Package is not installed."
                return
            }
            ;;

        zypper)
            rpm -q "$PACKAGE" >/dev/null 2>&1 || {
                echo "Package is not installed."
                return
            }
            ;;

    esac

    echo
    echo "[INFO] Simulating package removal..."

    case "$PM" in

        apt)
            run_root apt-get -s remove -- "$PACKAGE"
            ;;

        dnf)
            run_root dnf remove --assumeno "$PACKAGE"
            ;;

        pacman)
            run_root pacman -R --print "$PACKAGE"
            ;;

        zypper)
            run_root zypper --dry-run remove "$PACKAGE"
            ;;

    esac

    if [[ $? -ne 0 ]]; then
        echo "Removal review failed. Nothing changed."
        log "Removal simulation failed: $PACKAGE"
        return
    fi

    echo
    echo "Review the removal information above."
    echo "Dependencies and other packages may be affected."

    read -rp "Authorize removal? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "Removal declined: $PACKAGE"
        return
    fi

    read -rp "Type REMOVE to confirm: " FINAL

    if [[ "$FINAL" != "REMOVE" ]]; then
        echo "Removal cancelled."
        return
    fi

    echo
    echo "[INFO] Removing package..."

    case "$PM" in

        apt)
            run_root apt-get remove -- "$PACKAGE"
            ;;

        dnf)
            run_root dnf remove "$PACKAGE"
            ;;

        pacman)
            run_root pacman -R "$PACKAGE"
            ;;

        zypper)
            run_root zypper remove "$PACKAGE"
            ;;

    esac

    if [[ $? -eq 0 ]]; then
        echo "Removal command completed."
        log "Removal completed: $PACKAGE"
    else
        echo "Removal failed."
        log "Removal failed: $PACKAGE"
    fi

    echo
    read -rp "Press Enter to continue..."
}

# ==========================================
# MAIN MENU
# ==========================================

while true; do

    clear

    echo "=========================================="
    echo "    CYBERPATRIOT SOFTWARE MANAGEMENT"
    echo "=========================================="
    echo
    echo "OS: $PRETTY_NAME"
    echo "Package Manager: $PM"
    echo
    echo "1. Audit installed software"
    echo "2. Review and remove software"
    echo "3. View software inventory"
    echo "4. View management log"
    echo "5. Install security hardening software"
    echo "0. Return to main launcher"
    echo
    echo "=========================================="

    read -rp "Select an option: " CHOICE

    case "$CHOICE" in

        1)
            inventory
            ;;

        2)
            remove_package
            ;;

        3)
            if [[ -f "$INVENTORY" ]]; then
                if command -v less >/dev/null 2>&1; then
                    less "$INVENTORY"
                else
                    cat "$INVENTORY"
                    read -rp "Press Enter to continue..."
                fi
            else
                echo "Run an audit first."
                read -rp "Press Enter to continue..."
            fi
            ;;

        4)
            if [[ -f "$LOG_FILE" ]]; then
                if command -v less >/dev/null 2>&1; then
                    less "$LOG_FILE"
                else
                    cat "$LOG_FILE"
                    read -rp "Press Enter to continue..."
                fi
            else
                echo "No logs available."
                read -rp "Press Enter to continue..."
            fi
            ;;

        5)
            install_hardening
            ;;

        0)
            log "Software management exited."
            exit 0
            ;;

        *)
            echo "Invalid selection."
            sleep 2
            ;;

    esac

done

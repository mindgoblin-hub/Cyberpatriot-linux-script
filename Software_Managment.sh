
#!/bin/bash

# ==========================================
# CYBERPATRIOT SOFTWARE MANAGEMENT
# Debian / Ubuntu / APT distributions
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG_FILE="$LOG_DIR/software_management.log"
INVENTORY="$BACKUP_DIR/installed_software.tsv"

# Logging
log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# Check distribution
if [ ! -f /etc/os-release ]; then
    echo "Cannot identify Linux distribution."
    exit 1
fi

source /etc/os-release

if [[ " ${ID} ${ID_LIKE:-} " != *" debian "* ]] &&
   [[ "$ID" != "ubuntu" ]] &&
   [[ "$ID" != "linuxmint" ]] &&
   [[ "$ID" != "pop" ]]; then
    echo "This script is designed for Debian-based APT distributions."
    exit 1
fi

# Check APT tools
if ! command -v dpkg-query >/dev/null ||
   ! command -v apt-get >/dev/null; then
    echo "Required APT tools are missing."
    exit 1
fi

# Require sudo for package operations
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

echo
echo "=========================================="
echo "     CYBERPATRIOT SOFTWARE MANAGEMENT"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo "=========================================="

log "Software management started on $PRETTY_NAME"

# ------------------------------------------
# INVENTORY
# ------------------------------------------

inventory() {
    echo
    echo "[INFO] Creating installed software inventory..."

    dpkg-query -W \
        -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' \
        2>/dev/null |
        awk -F '\t' '$3 == "installed" {
            print $1 "\t" $2
        }' | sort > "$INVENTORY"

    log "Software inventory created: $INVENTORY"

    echo
    echo "Inventory saved to:"
    echo "$INVENTORY"

    echo
    echo "Installed package count:"
    wc -l < "$INVENTORY"

    echo
    echo "Manually installed packages:"
    apt-mark showmanual | sort

    echo
    read -rp "Press Enter to continue..."
}

# ------------------------------------------
# PACKAGE REMOVAL
# ------------------------------------------

remove_package() {
    echo
    echo "=========================================="
    echo "       REVIEW SOFTWARE REMOVAL"
    echo "=========================================="

    read -rp "Enter exact package name to review: " PACKAGE

    # Validate package name
    if [[ ! "$PACKAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9+.:~-]*$ ]]; then
        echo "Invalid package name."
        return
    fi

    # Verify package is installed
    STATUS=$(dpkg-query -W -f='${db:Status-Status}' "$PACKAGE" 2>/dev/null)

    if [[ "$STATUS" != "installed" ]]; then
        echo "Package is not currently installed."
        return
    fi

    # Protect essential packages
    ESSENTIAL=$(dpkg-query -W -f='${Essential}' "$PACKAGE" 2>/dev/null)

    if [[ "$ESSENTIAL" == "yes" ]]; then
        echo "BLOCKED: This is an essential system package."
        log "BLOCKED removal of essential package: $PACKAGE"
        return
    fi

    echo
    echo "Package information:"
    dpkg-query -W -f='Name: ${binary:Package}\nVersion: ${Version}\nDescription: ${binary:Summary}\nEssential: ${Essential}\n' "$PACKAGE"

    echo
    echo "[INFO] Checking removal impact..."

    SIMULATION=$($SUDO apt-get -s remove -- "$PACKAGE" 2>&1)
    SIM_STATUS=$?

    if [ "$SIM_STATUS" -ne 0 ]; then
        echo "Unable to simulate removal. Nothing changed."
        log "Removal simulation failed: $PACKAGE"
        return
    fi

    echo "$SIMULATION"

    echo
    echo "WARNING: Review all packages marked for removal above."
    echo "Removing a package may affect other software."

    read -rp "Do you authorize removal of $PACKAGE? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Removal cancelled."
        log "Removal declined: $PACKAGE"
        return
    fi

    echo
    echo "A second confirmation is required."
    read -rp "Type REMOVE to proceed: " FINAL_CONFIRM

    if [[ "$FINAL_CONFIRM" != "REMOVE" ]]; then
        echo "Removal cancelled."
        log "Final removal confirmation declined: $PACKAGE"
        return
    fi

    echo
    echo "[INFO] Starting APT removal..."

    # No -y: APT will still display its own confirmation.
    if $SUDO apt-get remove -- "$PACKAGE"; then
        echo "Removal command completed."
        log "APT removal completed: $PACKAGE"
    else
        echo "Removal failed or was interrupted."
        log "APT removal failed: $PACKAGE"
    fi

    echo
    read -rp "Press Enter to continue..."
}

# ------------------------------------------
# MAIN MENU
# ------------------------------------------

while true; do

    clear

    echo "=========================================="
    echo "     CYBERPATRIOT SOFTWARE MANAGEMENT"
    echo "=========================================="
    echo
    echo "1. Audit installed software"
    echo "2. Review and remove software"
    echo "3. View software inventory"
    echo "4. View management log"
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
            if [ -f "$INVENTORY" ]; then
                less "$INVENTORY"
            else
                echo "Run an audit first."
                read -rp "Press Enter to continue..."
            fi
            ;;

        4)
            if [ -f "$LOG_FILE" ]; then
                less "$LOG_FILE"
            else
                echo "No logs available."
                read -rp "Press Enter to continue..."
            fi
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


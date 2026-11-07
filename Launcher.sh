
#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL SCRIPT LOADER
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================

# Ensure Bash is being used
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "ERROR: This launcher requires Bash."
    exit 1
fi

# ==========================================
# DIRECTORY CONFIGURATION
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$BASE_DIR"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/cyberpatriot.log"

# ==========================================
# DISTRIBUTION DETECTION
# ==========================================

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DISTRO="${PRETTY_NAME:-Unknown Linux}"
else
    DISTRO="Unknown Linux"
fi

# ==========================================
# LOGGING
# ==========================================

log() {
    echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"
}

# ==========================================
# SCRIPT DISCOVERY
# ==========================================

get_scripts() {
    find "$SCRIPT_DIR" \
        -maxdepth 1 \
        -type f \
        -name "*.sh" \
        ! -name "$(basename "${BASH_SOURCE[0]}")" \
        ! -name "common.sh" \
        -print | sort
}

# ==========================================
# MAIN MENU
# ==========================================

while true; do

    clear

    mapfile -t SCRIPTS < <(get_scripts)

    echo "=========================================="
    echo "       CYBERPATRIOT SCRIPT LOADER"
    echo "=========================================="
    echo
    echo "Operating System: $DISTRO"
    echo "Running as: $(whoami)"
    echo

    echo "Available Scripts:"
    echo "------------------------------------------"

    if [[ "${#SCRIPTS[@]}" -eq 0 ]]; then
        echo "No scripts found."
    else
        for i in "${!SCRIPTS[@]}"; do
            NAME=$(basename "${SCRIPTS[$i]}" .sh)
            printf "%2d. %s\n" "$((i + 1))" "$NAME"
        done
    fi

    echo
    echo "------------------------------------------"
    echo "R. Refresh menu"
    echo "0. Exit"
    echo "=========================================="

    read -rp "Select a script: " choice

    # EXIT
    if [[ "$choice" == "0" ]]; then
        log "Launcher exited."
        echo "Exiting CyberPatriot Toolkit."
        exit 0
    fi

    # REFRESH
    if [[ "$choice" =~ ^[Rr]$ ]]; then
        continue
    fi

    # SCRIPT SELECTION
    if [[ "$choice" =~ ^[0-9]+$ ]]; then

        if (( choice >= 1 && choice <= ${#SCRIPTS[@]} )); then

            SELECTED="${SCRIPTS[$((choice - 1))]}"

            echo
            echo "=========================================="
            echo "Running: $(basename "$SELECTED")"
            echo "=========================================="

            log "Started script: $SELECTED"

            # Execute selected script
            bash "$SELECTED"
            RESULT=$?

            echo

            if [[ "$RESULT" -eq 0 ]]; then
                echo "[SUCCESS] Script completed."
                log "Script completed successfully: $SELECTED"
            else
                echo "[WARNING] Script exited with code $RESULT."
                log "Script failed with exit code $RESULT: $SELECTED"
            fi

            echo
            read -rp "Press Enter to return to menu..."

        else
            echo "Invalid selection."
            sleep 2
        fi

    else
        echo "Invalid selection."
        sleep 2
    fi

done

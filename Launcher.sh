
#!/bin/bash

# ==========================================
# CYBERPATRIOT MODULAR SCRIPT LOADER
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$BASE_DIR/scripts"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$SCRIPT_DIR" "$LOG_DIR"

LOG_FILE="$LOG_DIR/cyberpatriot.log"

# Discover scripts automatically
get_scripts() {
    find "$SCRIPT_DIR" -maxdepth 1 -type f -name "*.sh" ! -name "common.sh" | sort
}

while true; do
    clear

    # Load available scripts
    mapfile -t SCRIPTS < <(get_scripts)

    echo "======================================"
    echo "       CYBERPATRIOT SCRIPT LOADER"
    echo "======================================"
    echo

    if [ "${#SCRIPTS[@]}" -eq 0 ]; then
        echo "No scripts found."
    else
        for i in "${!SCRIPTS[@]}"; do
            NAME=$(basename "${SCRIPTS[$i]}" .sh)
            echo "$((i + 1)). $NAME"
        done
    fi

    echo
    echo "R. Refresh menu"
    echo "0. Exit"
    echo "======================================"

    read -rp "Select a script: " choice

    if [[ "$choice" == "0" ]]; then
        echo "Exiting CyberPatriot Toolkit."
        exit 0
    fi

    if [[ "$choice" == "r" || "$choice" == "R" ]]; then
        continue
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if (( choice >= 1 && choice <= ${#SCRIPTS[@]} )); then

            SELECTED="${SCRIPTS[$((choice - 1))]}"

            echo
            echo "[INFO] Running $(basename "$SELECTED")"
            echo "[$(date)] Running $SELECTED" >> "$LOG_FILE"

            bash "$SELECTED"

            echo
            echo "[INFO] Script finished."
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


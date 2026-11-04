
#!/bin/bash

# ==========================================
# CYBERPATRIOT USER ACCOUNT AUDIT
# Debian / Ubuntu / APT distributions
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/user_audit.log"
REPORT="$LOG_DIR/user_inventory.txt"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

if [[ $EUID -ne 0 ]]; then
    echo "Run with administrator privileges:"
    echo "sudo bash User_Audit.sh"
    exit 1
fi

clear

echo "=========================================="
echo "       CYBERPATRIOT USER ACCOUNT AUDIT"
echo "=========================================="

log "User audit started."

# ------------------------------------------
# FIND USERS WITH HOME DIRECTORIES
# ------------------------------------------

echo
echo "[INFO] Searching for accounts with existing home directories..."
echo

printf "%-20s %-10s %-30s %-25s\n" \
    "USERNAME" "UID" "HOME DIRECTORY" "LOGIN SHELL"

printf '%s\n' "------------------------------------------------------------------------------------------"

# Create report
{
    echo "CYBERPATRIOT USER ACCOUNT INVENTORY"
    echo "Date: $(date)"
    echo
    printf "%-20s %-10s %-30s %-25s\n" \
        "USERNAME" "UID" "HOME DIRECTORY" "LOGIN SHELL"
    printf '%s\n' "------------------------------------------------------------------------------------------"
} > "$REPORT"

COUNT=0

while IFS=: read -r USER _ UID GID _ HOME SHELL; do

    # Skip accounts without a home directory
    [[ -z "$HOME" ]] && continue

    # Check if home directory exists
    if [[ -d "$HOME" ]]; then

        printf "%-20s %-10s %-30s %-25s\n" \
            "$USER" "$UID" "$HOME" "$SHELL"

        printf "%-20s %-10s %-30s %-25s\n" \
            "$USER" "$UID" "$HOME" "$SHELL" >> "$REPORT"

        COUNT=$((COUNT + 1))

    fi

done < /etc/passwd

# ------------------------------------------
# SUMMARY
# ------------------------------------------

echo
echo "=========================================="
echo "              AUDIT SUMMARY"
echo "=========================================="

echo "Accounts with existing home directories: $COUNT"

log "Found $COUNT accounts with existing home directories."

# ------------------------------------------
# INTERACTIVE USERS
# ------------------------------------------

echo
echo "=========================================="
echo "       INTERACTIVE LOGIN ACCOUNTS"
echo "=========================================="

while IFS=: read -r USER _ UID GID _ HOME SHELL; do

    if [[ "$SHELL" != */nologin && "$SHELL" != */false ]] &&
       [[ -d "$HOME" ]] &&
       [[ -x "$SHELL" ]]; then

        echo "$USER (UID: $UID) - $SHELL"

    fi

done < /etc/passwd

# ------------------------------------------
# SAVE RESULTS
# ------------------------------------------

echo
echo "=========================================="
echo "              REPORT SAVED"
echo "=========================================="

echo "Inventory: $REPORT"
echo "Log:       $LOG_FILE"

log "User audit completed."

echo
read -rp "Press Enter to return to launcher..."

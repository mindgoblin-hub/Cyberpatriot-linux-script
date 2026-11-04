
#!/bin/bash

# ==========================================
# CYBERPATRIOT PASSWORD POLICY CONFIGURATION
# Debian / Ubuntu / APT distributions
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG_FILE="$LOG_DIR/password_config.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ------------------------------------------
# ROOT CHECK
# ------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Run with administrator privileges:"
    echo "sudo bash password_config.sh"
    exit 1
fi

# ------------------------------------------
# DISTRIBUTION CHECK
# ------------------------------------------

source /etc/os-release

if [[ "$ID" != "ubuntu" && "$ID" != "debian" &&
      "$ID" != "linuxmint" && "$ID" != "pop" &&
      " ${ID_LIKE:-} " != *" debian "* ]]; then
    echo "Unsupported distribution."
    exit 1
fi

echo "=========================================="
echo "    CYBERPATRIOT PASSWORD CONFIGURATION"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"

# ------------------------------------------
# BACKUP CONFIGURATION
# ------------------------------------------

BACKUP="$BACKUP_DIR/password_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP"

cp -a /etc/login.defs "$BACKUP/"
cp -a /etc/security/pwquality.conf "$BACKUP/" 2>/dev/null || true
cp -a /etc/pam.d/common-password "$BACKUP/" 2>/dev/null || true

log "Password configuration backup created: $BACKUP"

# ------------------------------------------
# INSTALL PASSWORD QUALITY
# ------------------------------------------

if ! dpkg -s libpam-pwquality >/dev/null 2>&1; then

    echo
    echo "Password quality package is missing."

    read -rp "Install libpam-pwquality? (yes/no): " INSTALL

    if [[ "$INSTALL" != "yes" ]]; then
        echo "Installation cancelled."
        exit 1
    fi

    apt-get update &&
        apt-get install -y libpam-pwquality || {
        echo "Installation failed."
        log "Password quality installation failed."
        exit 1
    }

fi

# ------------------------------------------
# CONFIGURE PASSWORD AGING DEFAULTS
# ------------------------------------------

echo
echo "Configuring password expiration policy..."

sed -i -E \
    '/^[[:space:]]*PASS_MAX_DAYS[[:space:]]/d;
     /^[[:space:]]*PASS_MIN_DAYS[[:space:]]/d;
     /^[[:space:]]*PASS_WARN_AGE[[:space:]]/d' \
    /etc/login.defs

cat >> /etc/login.defs <<'EOF'

# CyberPatriot Password Policy
PASS_MAX_DAYS 30
PASS_MIN_DAYS 10
PASS_WARN_AGE 20
EOF

log "Configured password aging defaults."

# ------------------------------------------
# CONFIGURE PASSWORD COMPLEXITY
# ------------------------------------------

echo "Configuring password complexity..."

PWQUALITY="/etc/security/pwquality.conf"

touch "$PWQUALITY"

sed -i -E \
    '/^[[:space:]]*minlen[[:space:]]*=/d;
     /^[[:space:]]*ucredit[[:space:]]*=/d;
     /^[[:space:]]*lcredit[[:space:]]*=/d;
     /^[[:space:]]*dcredit[[:space:]]*=/d;
     /^[[:space:]]*ocredit[[:space:]]*=/d;
     /^[[:space:]]*enforce_for_root([[:space:]]|$)/d' \
    "$PWQUALITY"

cat >> "$PWQUALITY" <<'EOF'

# CyberPatriot Password Complexity Policy
minlen = 12
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1
enforce_for_root
EOF

log "Configured password complexity requirements."

# ------------------------------------------
# ENABLE PAM PASSWORD QUALITY MODULE
# ------------------------------------------

echo
echo "Enabling PAM password quality enforcement..."

if command -v pam-auth-update >/dev/null 2>&1; then

    if ! pam-auth-update --enable pwquality; then
        echo "Could not enable PAM pwquality automatically."
        echo "Review /etc/pam.d/common-password manually."
        log "PAM pwquality activation requires manual review."
    else
        log "Enabled PAM pwquality."
    fi

else
    echo "pam-auth-update not found."
    echo "PAM configuration requires manual review."
    log "PAM activation unavailable."
fi

# ------------------------------------------
# APPLY POLICY TO EXISTING HUMAN ACCOUNTS
# ------------------------------------------

echo
echo "Existing account password aging settings:"
echo

read -rp "Apply 30/10/20 aging policy to existing human accounts? (yes/no): " APPLY

if [[ "$APPLY" == "yes" ]]; then

    while IFS=: read -r USER _ UID GID _ HOME SHELL; do

        if [[ "$UID" -ge 1000 ]] &&
           [[ "$USER" != "nobody" ]] &&
           [[ -d "$HOME" ]] &&
           [[ "$SHELL" != */nologin ]] &&
           [[ "$SHELL" != */false ]]; then

            chage -M 30 -m 10 -W 20 "$USER"

            log "Applied password aging policy to $USER"

            echo "Updated: $USER"

        fi

    done < /etc/passwd

else
    log "Existing account aging changes declined."
fi

# ------------------------------------------
# OPTIONAL FORCE PASSWORD CHANGE
# ------------------------------------------

echo
echo "Force users to change their passwords at next login?"
echo "This will affect interactive accounts with home directories."

read -rp "Require password changes at next login? (yes/no): " FORCE

if [[ "$FORCE" == "yes" ]]; then

    while IFS=: read -r USER _ UID GID _ HOME SHELL; do

        if [[ "$UID" -ge 1000 ]] &&
           [[ "$USER" != "nobody" ]] &&
           [[ -d "$HOME" ]] &&
           [[ "$SHELL" != */nologin ]] &&
           [[ "$SHELL" != */false ]]; then

            chage -d 0 "$USER"

            log "Required password change at next login for $USER"

            echo "Password change required: $USER"

        fi

    done < /etc/passwd

fi

# ------------------------------------------
# FINAL REPORT
# ------------------------------------------

echo
echo "=========================================="
echo "       PASSWORD POLICY SUMMARY"
echo "=========================================="

echo "Maximum password age:       30 days"
echo "Minimum password age:       10 days"
echo "Expiration warning:        20 days"
echo "Minimum password length:  12 characters"
echo "Uppercase required:        1"
echo "Lowercase required:        1"
echo "Number required:           1"
echo "Symbol required:           1"

echo
echo "=========================================="
echo "       CURRENT ACCOUNT AGING"
echo "=========================================="

for USER in $(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd); do
    echo
    echo "Account: $USER"
    chage -l "$USER" | grep -E \
        'Minimum|Maximum|Warning|Last password change'
done

echo
echo "Backup: $BACKUP"
echo "Log: $LOG_FILE"

log "Password configuration completed."

echo
read -rp "Press Enter to return to launcher..."

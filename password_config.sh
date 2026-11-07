
#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL PASSWORD MANAGER
# Debian / Ubuntu / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================

# ==========================================
# DIRECTORY CONFIGURATION
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

LOG_FILE="$LOG_DIR/password_config.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ==========================================
# ROOT CHECK
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "Administrator privileges required."
    echo "Run: sudo bash Password_Config.sh"
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
# HEADER
# ==========================================

clear

echo "=========================================="
echo "    CYBERPATRIOT PASSWORD MANAGER"
echo "=========================================="
echo "Distribution: $PRETTY_NAME"
echo "Package Manager: $PM"
echo "=========================================="

log "Password management started: $PRETTY_NAME"

# ==========================================
# BACKUP CONFIGURATION
# ==========================================

BACKUP="$BACKUP_DIR/password_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP"

[[ -f /etc/login.defs ]] &&
    cp -a /etc/login.defs "$BACKUP/"

[[ -f /etc/security/pwquality.conf ]] &&
    cp -a /etc/security/pwquality.conf "$BACKUP/"

[[ -d /etc/pam.d ]] &&
    cp -a /etc/pam.d "$BACKUP/"

[[ -d /etc/authselect ]] &&
    cp -a /etc/authselect "$BACKUP/"

log "Configuration backup created: $BACKUP"

# ==========================================
# INSTALL PASSWORD QUALITY
# ==========================================

install_pwquality() {

    echo
    echo "=========================================="
    echo "       PASSWORD QUALITY INSTALLATION"
    echo "=========================================="

    case "$PM" in

        apt)
            PACKAGE="libpam-pwquality"
            ;;

        dnf)
            PACKAGE="libpwquality"
            ;;

        pacman)
            PACKAGE="libpwquality"
            ;;

        zypper)
            PACKAGE="pam_pwquality"
            ;;

    esac

    echo "Required package: $PACKAGE"

    read -rp "Install or update password quality software? (yes/no): " INSTALL

    if [[ "$INSTALL" != "yes" ]]; then
        log "Password quality installation declined."
        return 1
    fi

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

    if [[ $? -eq 0 ]]; then
        echo "Password quality package installed."
        log "Installed password quality package: $PACKAGE"
        return 0
    else
        echo "Installation failed."
        log "Password quality installation failed: $PACKAGE"
        return 1
    fi
}

# ==========================================
# CHECK PASSWORD QUALITY
# ==========================================

check_pwquality() {

    if command -v pwscore >/dev/null 2>&1; then
        echo "pwquality utilities detected."
    else
        echo "Warning: pwscore utility not found."
    fi

}

# ==========================================
# CONFIGURE PASSWORD AGING
# ==========================================

configure_aging() {

    echo
    echo "=========================================="
    echo "       PASSWORD AGING POLICY"
    echo "=========================================="

    echo "Proposed policy:"
    echo "Maximum password age: 30 days"
    echo "Minimum password age: 10 days"
    echo "Expiration warning:   20 days"

    read -rp "Apply password aging defaults? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "Password aging configuration declined."
        return
    fi

    if [[ ! -f /etc/login.defs ]]; then
        echo "login.defs not found."
        return
    fi

    sed -i -E \
        '/^[[:space:]]*PASS_MAX_DAYS[[:space:]]/d;
         /^[[:space:]]*PASS_MIN_DAYS[[:space:]]/d;
         /^[[:space:]]*PASS_WARN_AGE[[:space:]]/d' \
        /etc/login.defs

    cat >> /etc/login.defs <<'EOF'

# CyberPatriot Password Aging Policy
PASS_MAX_DAYS 30
PASS_MIN_DAYS 10
PASS_WARN_AGE 20
EOF

    log "Configured password aging defaults."

    echo "Password aging defaults updated."

}

# ==========================================
# CONFIGURE PASSWORD COMPLEXITY
# ==========================================

configure_complexity() {

    echo
    echo "=========================================="
    echo "       PASSWORD COMPLEXITY"
    echo "=========================================="

    echo "Minimum length: 12"
    echo "Uppercase:      Required"
    echo "Lowercase:      Required"
    echo "Number:         Required"
    echo "Special:        Required"

    read -rp "Apply password complexity policy? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "Password complexity configuration declined."
        return
    fi

    PWQUALITY="/etc/security/pwquality.conf"

    mkdir -p /etc/security
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

    log "Password complexity configuration updated."

    echo "Password complexity settings saved."

}

# ==========================================
# ENABLE PAM PASSWORD QUALITY
# ==========================================

enable_pam() {

    echo
    echo "=========================================="
    echo "       PAM CONFIGURATION"
    echo "=========================================="

    case "$PM" in

        apt)

            if command -v pam-auth-update >/dev/null 2>&1; then

                echo "Enabling pwquality through pam-auth-update."

                if pam-auth-update --enable pwquality; then
                    log "PAM pwquality enabled."
                else
                    echo "PAM activation failed."
                    log "PAM activation failed."
                fi

            else
                echo "pam-auth-update unavailable."
            fi
            ;;

        dnf)

            if command -v authselect >/dev/null 2>&1; then

                echo "Checking authselect configuration."

                if authselect check; then

                    if authselect enable-feature with-pwquality &&
                       authselect apply-changes; then

                        log "Enabled PAM pwquality through authselect."

                    else
                        echo "Could not enable pwquality automatically."
                        log "Authselect pwquality activation failed."
                    fi

                else
                    echo "Authselect configuration requires manual review."
                    log "Authselect check failed."
                fi

            else
                echo "Authselect not found."
                echo "Review PAM configuration manually."
            fi
            ;;

        zypper)

            if command -v pam-config >/dev/null 2>&1; then

                read -rp "Enable pwquality through pam-config? (yes/no): " ENABLE

                if [[ "$ENABLE" == "yes" ]]; then
                    pam-config --add --pwquality
                    log "Attempted pwquality PAM configuration."
                fi

            else
                echo "pam-config unavailable."
                echo "Review PAM configuration manually."
            fi
            ;;

        pacman)

            echo "Arch Linux PAM configuration varies by installation."
            echo "Review /etc/pam.d/system-auth manually."
            echo "Do not overwrite existing PAM configuration."
            ;;

    esac

    echo
    echo "Checking PAM configuration..."

    if grep -RqsE 'pam_pwquality\.so' /etc/pam.d 2>/dev/null; then
        echo "A pwquality PAM module reference was found."
        log "PAM pwquality reference detected."
    else
        echo "WARNING: No pwquality PAM reference detected."
        echo "Password complexity may not be enforced."
        log "PAM pwquality reference not detected."
    fi

}

# ==========================================
# IDENTIFY INTERACTIVE ACCOUNTS
# ==========================================

get_interactive_users() {

    while IFS=: read -r USER _ UID GID GECOS HOME SHELL; do

        [[ "$USER" == "root" ]] && continue
        [[ "$USER" == "nobody" ]] && continue

        [[ -n "$SHELL" && -x "$SHELL" ]] || continue

        if [[ -f /etc/shells ]] &&
           grep -Fxq "$SHELL" /etc/shells; then

            printf '%s\n' "$USER"

        fi

    done < /etc/passwd

}

# ==========================================
# APPLY AGING TO EXISTING ACCOUNTS
# ==========================================

configure_existing_users() {

    echo
    echo "=========================================="
    echo "       EXISTING ACCOUNT AGING"
    echo "=========================================="

    echo "Interactive accounts detected:"
    echo

    mapfile -t USERS < <(get_interactive_users)

    if [[ ${#USERS[@]} -eq 0 ]]; then
        echo "No interactive accounts detected."
        return
    fi

    printf '%s\n' "${USERS[@]}"

    echo
    echo "This does not rely on UID >= 1000."
    echo "Accounts are identified using their login shells."

    read -rp "Apply 30/10/20 aging policy to these accounts? (yes/no): " APPLY

    if [[ "$APPLY" != "yes" ]]; then
        log "Existing account aging declined."
        return
    fi

    for USER in "${USERS[@]}"; do

        if chage -M 30 -m 10 -W 20 "$USER"; then

            echo "Updated: $USER"
            log "Password aging updated: $USER"

        else

            echo "Failed: $USER"
            log "Password aging failed: $USER"

        fi

    done

}

# ==========================================
# FORCE PASSWORD CHANGES
# ==========================================

force_password_changes() {

    echo
    echo "=========================================="
    echo "       FORCE PASSWORD CHANGES"
    echo "=========================================="

    mapfile -t USERS < <(get_interactive_users)

    if [[ ${#USERS[@]} -eq 0 ]]; then
        echo "No interactive accounts detected."
        return
    fi

    echo "The following accounts were detected:"
    printf '%s\n' "${USERS[@]}"

    echo
    echo "WARNING:"
    echo "All selected users will need to change"
    echo "their passwords at their next login."

    read -rp "Continue? (yes/no): " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log "Forced password changes declined."
        return
    fi

    read -rp "Type FORCE to confirm: " FINAL

    if [[ "$FINAL" != "FORCE" ]]; then
        echo "Operation cancelled."
        return
    fi

    for USER in "${USERS[@]}"; do

        if chage -d 0 "$USER"; then

            echo "Password change required: $USER"
            log "Forced password change: $USER"

        else

            echo "Failed: $USER"
            log "Forced password change failed: $USER"

        fi

    done

}

# ==========================================
# VIEW ACCOUNT AGING
# ==========================================

view_account_aging() {

    echo
    echo "=========================================="
    echo "       ACCOUNT PASSWORD AGING"
    echo "=========================================="

    mapfile -t USERS < <(get_interactive_users)

    for USER in "${USERS[@]}"; do

        echo
        echo "Account: $USER"

        chage -l "$USER" 2>/dev/null |
            grep -E 'Minimum|Maximum|Warning|Last password change|Password expires'

    done

    echo
    read -rp "Press Enter to continue..."

}

# ==========================================
# MAIN MENU
# ==========================================

while true; do

    clear

    echo "=========================================="
    echo "    CYBERPATRIOT PASSWORD MANAGER"
    echo "=========================================="
    echo "OS: $PRETTY_NAME"
    echo "Package Manager: $PM"
    echo
    echo "1. Install password quality software"
    echo "2. Configure password aging defaults"
    echo "3. Configure password complexity"
    echo "4. Enable PAM password quality"
    echo "5. Apply aging to existing accounts"
    echo "6. Force password changes"
    echo "7. View account password aging"
    echo "8. View password configuration log"
    echo "0. Return to main launcher"
    echo
    echo "=========================================="

    read -rp "Select an option: " CHOICE

    case "$CHOICE" in

        1)
            install_pwquality
            check_pwquality
            read -rp "Press Enter to continue..."
            ;;

        2)
            configure_aging
            read -rp "Press Enter to continue..."
            ;;

        3)
            configure_complexity
            read -rp "Press Enter to continue..."
            ;;

        4)
            enable_pam
            read -rp "Press Enter to continue..."
            ;;

        5)
            configure_existing_users
            read -rp "Press Enter to continue..."
            ;;

        6)
            force_password_changes
            read -rp "Press Enter to continue..."
            ;;

        7)
            view_account_aging
            ;;

        8)
            if [[ -f "$LOG_FILE" ]]; then
                less "$LOG_FILE" 2>/dev/null ||
                    cat "$LOG_FILE"
            else
                echo "No logs available."
            fi
            read -rp "Press Enter to continue..."
            ;;

        0)
            log "Password manager exited."
            exit 0
            ;;

        *)
            echo "Invalid selection."
            sleep 2
            ;;

    esac

done

#!/bin/bash

# ==========================================
# CYBERPATRIOT UNIVERSAL MEDIA FILE AUDIT
# Ubuntu / Debian / Mint / Pop!_OS
# Fedora / RHEL / Rocky / AlmaLinux
# Arch / Manjaro / openSUSE
# ==========================================

# ==========================================
# DIRECTORY CONFIGURATION
# ==========================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/media_audit.log"

log() {
    echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"
}

# ==========================================
# ROOT CHECK
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "Administrator privileges required."
    echo "Run: sudo bash Media_Audit.sh"
    exit 1
fi

# ==========================================
# DISTRIBUTION DETECTION
# ==========================================

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DISTRO="$PRETTY_NAME"
else
    DISTRO="Unknown Linux"
fi

# ==========================================
# MEDIA EXTENSIONS
# ==========================================

EXTENSIONS=(
    mp3 wav flac aac ogg m4a wma
    mp4 mkv avi mov wmv webm mpeg mpg
    jpg jpeg png gif bmp webp tiff
    iso
)

# ==========================================
# SEARCH LOCATION
# ==========================================

clear

echo "=========================================="
echo "     CYBERPATRIOT MEDIA FILE AUDIT"
echo "=========================================="
echo "Distribution: $DISTRO"
echo

echo "Choose search location:"
echo
echo "1. Home directories"
echo "2. Entire filesystem"
echo "3. Custom directory"
echo "0. Exit"

read -rp "Selection: " OPTION

case "$OPTION" in

    1)
        SEARCH_DIR="/home"
        ;;

    2)
        SEARCH_DIR="/"
        ;;

    3)
        read -rp "Enter directory path: " SEARCH_DIR

        if [[ ! -d "$SEARCH_DIR" ]]; then
            echo "Directory does not exist."
            exit 1
        fi

        SEARCH_DIR="$(realpath -e -- "$SEARCH_DIR")"
        ;;

    0)
        exit 0
        ;;

    *)
        echo "Invalid selection."
        exit 1
        ;;

esac

# ==========================================
# FIND MEDIA FILES
# ==========================================

echo
echo "[INFO] Searching for media files..."
echo "Location: $SEARCH_DIR"

log "Media audit started on $DISTRO"
log "Search location: $SEARCH_DIR"

TEMP_FILE=$(mktemp) || exit 1
trap 'rm -f "$TEMP_FILE"' EXIT

FIND_ARGS=()

for EXT in "${EXTENSIONS[@]}"; do
    FIND_ARGS+=( -iname "*.$EXT" -o )
done

unset 'FIND_ARGS[${#FIND_ARGS[@]}-1]'

# Exclude virtual filesystems and toolkit directory
find "$SEARCH_DIR" \
    \( \
        -path /proc -o \
        -path /sys -o \
        -path /dev -o \
        -path /run -o \
        -path /tmp -o \
        -path /snap -o \
        -path /var/lib -o \
        -path "$BASE_DIR" \
    \) -prune -o \
    -type f \( "${FIND_ARGS[@]}" \) \
    -print0 2>/dev/null > "$TEMP_FILE"

# ==========================================
# REVIEW FILES
# ==========================================

COUNT=0
DELETED=0
KEPT=0
FAILED=0

echo
echo "=========================================="
echo "         MEDIA FILE REVIEW"
echo "=========================================="

while IFS= read -r -d '' FILE; do

    COUNT=$((COUNT + 1))

    echo
    echo "------------------------------------------"
    echo "File #$COUNT"
    echo "Name: $(basename "$FILE")"
    echo "Location: $FILE"

    SIZE=$(du -h -- "$FILE" 2>/dev/null | cut -f1)
    echo "Size: ${SIZE:-Unknown}"

    echo "------------------------------------------"

    echo
    echo "1. Delete this file"
    echo "2. Keep this file"
    echo "3. Stop reviewing"

    read -rp "Choose an action: " ACTION

    case "$ACTION" in

        1)
            echo
            echo "WARNING: This permanently deletes the file."

            read -rp "Confirm deletion? Type DELETE: " CONFIRM

            if [[ "$CONFIRM" == "DELETE" ]]; then

                if [[ -f "$FILE" && ! -L "$FILE" ]] &&
                   rm -i -- "$FILE"; then

                    if [[ ! -e "$FILE" ]]; then
                        echo "File removed."
                        log "DELETED: $FILE"
                        DELETED=$((DELETED + 1))
                    else
                        echo "File retained."
                        log "REMOVAL DECLINED: $FILE"
                        KEPT=$((KEPT + 1))
                    fi

                else
                    echo "File could not be removed."
                    log "REMOVAL FAILED: $FILE"
                    FAILED=$((FAILED + 1))
                fi

            else
                echo "Deletion cancelled."
                log "DELETION DECLINED: $FILE"
                KEPT=$((KEPT + 1))
            fi
            ;;

        2)
            echo "File retained."
            log "KEPT: $FILE"
            KEPT=$((KEPT + 1))
            ;;

        3)
            echo "Review stopped."
            break
            ;;

        *)
            echo "Invalid selection. File retained."
            log "INVALID SELECTION: $FILE"
            KEPT=$((KEPT + 1))
            ;;

    esac

done < "$TEMP_FILE"

# ==========================================
# SUMMARY
# ==========================================

echo
echo "=========================================="
echo "         MEDIA AUDIT SUMMARY"
echo "=========================================="

echo "Distribution:    $DISTRO"
echo "Files reviewed:  $COUNT"
echo "Files deleted:   $DELETED"
echo "Files retained:  $KEPT"
echo "Removal failures: $FAILED"

echo
echo "Log saved to:"
echo "$LOG_FILE"

log "Audit finished."
log "Found: $COUNT | Deleted: $DELETED | Kept: $KEPT | Failed: $FAILED"

echo
read -rp "Press Enter to return to launcher..."

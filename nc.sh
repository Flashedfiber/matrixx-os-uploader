#!/usr/bin/env bash

# ─────────────────────────────────────────────
#        Matrixx-OS Nextcloud CLI Tool
# ─────────────────────────────────────────────

NC_URL="https://files.dataheaven.space"
BASE_DIR="Matrixx-OS"

set -euo pipefail

# ─────────────────────────────────────────────
# Load .env if present
# ─────────────────────────────────────────────
if [[ -f .env ]]; then
    source .env
fi

# ─────────────────────────────────────────────
# Validate environment
# ─────────────────────────────────────────────
if [[ -z "${NC_USER:-}" || -z "${NC_PASS:-}" ]]; then
    echo ""
    echo "❌ Matrixx-OS Uploader: Missing credentials!"
    echo ""
    echo "👉 Option 1 (recommended):"
    echo "   Create .env file:"
    echo "     NC_USER=your_username"
    echo "     NC_PASS=your_app_password"
    echo ""
    echo "👉 Option 2:"
    echo '   NC_USER="user" NC_PASS="pass" ./nc.sh upload file.zip'
    echo ""
    exit 1
fi

echo ""
echo "┌─────────────────────────────────────────┐"
echo "│        Matrixx-OS Upload Utility        │"
echo "└─────────────────────────────────────────┘"
echo "[INFO] Logged in as: ${NC_USER}"
echo "[INFO] Server: ${NC_URL}"
echo ""

WEBDAV_ROOT="${NC_URL}/remote.php/dav/files/${NC_USER}"

# ─────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────
LOG_FILE="matrixx_upload.log"

log_action() {
    local ACTION="$1"
    local TARGET="$2"
    local STATUS="$3"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${NC_USER} | ${ACTION} | ${TARGET} | ${STATUS}" >> "$LOG_FILE"
}

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
propfind_status() {
    curl -s -o /dev/null -w "%{http_code}" \
        -u "${NC_USER}:${NC_PASS}" \
        -X PROPFIND \
        "${WEBDAV_ROOT}/$1"
}

mkcol() {
    curl -s -o /dev/null \
        -u "${NC_USER}:${NC_PASS}" \
        -X MKCOL \
        "${WEBDAV_ROOT}/$1"
}

list_dir() {
    echo ""
    echo "📂 Listing: $1"
    echo "────────────────────────────"
    curl -s -u "${NC_USER}:${NC_PASS}" \
        -X PROPFIND \
        "${WEBDAV_ROOT}/$1" \
        | grep "<d:displayname>" \
        | sed 's/.*<d:displayname>//;s/<\/d:displayname>//'
    echo ""

    log_action "LIST" "$1" "OK"
}

delete_file() {
    local PATH="$1"

    echo ""
    echo "⚠️  Delete: ${PATH}"
    read -rp "Confirm delete? [y/N]: " CONFIRM

    [[ "$CONFIRM" != "y" ]] && { echo "❌ Cancelled."; exit 1; }

    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${NC_USER}:${NC_PASS}" \
        -X DELETE \
        "${WEBDAV_ROOT}/${PATH}")

    if [[ "$HTTP" == "204" ]]; then
        echo "✅ Deleted successfully"
        log_action "DELETE" "${PATH}" "SUCCESS"
    else
        echo "❌ Delete failed (HTTP $HTTP)"
        log_action "DELETE" "${PATH}" "FAILED ($HTTP)"
    fi
}

upload_file() {
    local FILE="$1"

    if [[ ! -f "$FILE" ]]; then
        echo "❌ File not found: $FILE"
        exit 1
    fi

    echo "Select Android version:"
    OPTIONS=("A16")
    for i in "${!OPTIONS[@]}"; do
        echo "  $((i+1))) ${OPTIONS[$i]}"
    done

    read -rp "Choice: " CHOICE
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#OPTIONS[@]} )); then
        echo "❌ Invalid selection"
        exit 1
    fi

    ANDROID="${OPTIONS[$((CHOICE-1))]}"
    ANDROID_PATH="${BASE_DIR}/${ANDROID}"

    [[ "$(propfind_status "$ANDROID_PATH")" == "404" ]] && mkcol "$ANDROID_PATH"

    echo ""
    read -rp "Device name (e.g. lemonadep): " DEVICE

    if [[ -z "$DEVICE" ]]; then
        echo "❌ Device name cannot be empty"
        exit 1
    fi

    DEVICE_PATH="${ANDROID_PATH}/${DEVICE}"
    [[ "$(propfind_status "$DEVICE_PATH")" == "404" ]] && mkcol "$DEVICE_PATH"

    FILENAME="$(basename "$FILE")"
    TARGET="${WEBDAV_ROOT}/${DEVICE_PATH}/${FILENAME}"

    echo ""
    echo "🚀 Uploading:"
    echo "   File   : $FILENAME"
    echo "   Path   : ${DEVICE_PATH}"
    echo "─────────────────────────────────────────"

    HTTP=$(curl -s -# \
        -u "${NC_USER}:${NC_PASS}" \
        -T "$FILE" \
        -w "%{http_code}" \
        -o /dev/null \
        "$TARGET")

    echo ""
    echo "HTTP Status: $HTTP"

    if [[ "$HTTP" == "201" || "$HTTP" == "204" ]]; then
        echo "✅ Upload successful"
        log_action "UPLOAD" "${DEVICE_PATH}/${FILENAME}" "SUCCESS"
    else
        echo "❌ Upload failed"
        log_action "UPLOAD" "${DEVICE_PATH}/${FILENAME}" "FAILED ($HTTP)"
    fi

    echo ""
    echo "📁 View:"
    echo "${NC_URL}/apps/files/?dir=/${DEVICE_PATH}"
    echo ""
}

# ─────────────────────────────────────────────
# CLI Commands
# ─────────────────────────────────────────────
CMD="${1:-}"

case "$CMD" in
    upload)
        shift
        upload_file "${1:-}"
        ;;
    delete)
        shift
        delete_file "${BASE_DIR}/$1/$2/$3"
        ;;
    list)
        shift
        list_dir "${BASE_DIR}/$1/$2"
        ;;
    *)
        echo "Matrixx-OS CLI Usage:"
        echo ""
        echo "  Upload:"
        echo "    ./nc.sh upload file.zip"
        echo ""
        echo "  List:"
        echo "    ./nc.sh list A16 device"
        echo ""
        echo "  Delete:"
        echo "    ./nc.sh delete A16 device file.zip"
        echo ""
        ;;
esac

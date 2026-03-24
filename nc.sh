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

ensure_extras_folder() {
    local DEVICE_PATH="$1"
    local EXTRAS_PATH="${DEVICE_PATH}/extras"

    if [[ "$(propfind_status "$EXTRAS_PATH")" == "404" ]]; then
        mkcol "$EXTRAS_PATH"
        echo "[OK] Created extras folder: ${EXTRAS_PATH}"
    fi
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

# ─────────────────────────────────────────────
# Share (Direct Download Link)
# ─────────────────────────────────────────────
get_download_link() {
    local FILE_PATH="$1"

    RESPONSE=$(curl -s \
        -u "${NC_USER}:${NC_PASS}" \
        -X POST \
        -H "OCS-APIRequest: true" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "${NC_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares" \
        --data-urlencode "path=/${FILE_PATH}" \
        --data "shareType=3" \
        --data "permissions=1")

    URL=$(echo "$RESPONSE" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)

    if [[ -n "$URL" ]]; then
        echo "${URL}/download"
    else
        echo ""
    fi
}

# ─────────────────────────────────────────────
# Upload
# ─────────────────────────────────────────────
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

    if [[ "$(propfind_status "$DEVICE_PATH")" == "404" ]]; then
        mkcol "$DEVICE_PATH"
        echo "[OK] Created device folder: ${DEVICE_PATH}"
        ensure_extras_folder "$DEVICE_PATH"
    fi

    echo ""
    echo "Upload type:"
    echo "  1) ROM (default)"
    echo "  2) Extras"
    read -rp "Choice [1/2]: " TYPE

    if [[ "$TYPE" == "2" ]]; then
        TARGET_PATH="${DEVICE_PATH}/extras"
    else
        TARGET_PATH="${DEVICE_PATH}"
    fi

    FILENAME="$(basename "$FILE")"
    TARGET="${WEBDAV_ROOT}/${TARGET_PATH}/${FILENAME}"

    echo ""
    echo "🚀 Uploading:"
    echo "   File   : $FILENAME"
    echo "   Path   : ${TARGET_PATH}"
    echo "─────────────────────────────────────────"

    HTTP=$(curl --progress-bar \
        -u "${NC_USER}:${NC_PASS}" \
        -T "$FILE" \
        -w "%{http_code}" \
        -o /dev/null \
        "$TARGET")

    echo ""
    echo "HTTP Status: $HTTP"

    # ⚠️ Warn if unexpected HTTP
    if [[ "$HTTP" != "201" && "$HTTP" != "204" ]]; then
        echo "⚠️ Server returned HTTP $HTTP — verifying upload..."
    fi

    # ✅ Verify file exists on server
    FILE_CHECK=$(propfind_status "${TARGET_PATH}/${FILENAME}")

    if [[ "$FILE_CHECK" == "207" ]]; then
        echo "✅ Upload successful (verified)"
        log_action "UPLOAD" "${TARGET_PATH}/${FILENAME}" "SUCCESS"

        echo -n "🔗 Generating download link... "
        LINK=$(get_download_link "${TARGET_PATH}/${FILENAME}")

        if [[ -n "$LINK" ]]; then
            echo "OK"
            echo "📥 Direct Link: $LINK"
        else
            echo "FAILED (share API issue)"
        fi
    else
        echo "❌ Upload failed (file not found on server)"
        log_action "UPLOAD" "${TARGET_PATH}/${FILENAME}" "FAILED ($HTTP)"
    fi

    echo ""
    echo "📁 View:"
    echo "${NC_URL}/apps/files/?dir=/${TARGET_PATH}"
    echo ""
}

# ─────────────────────────────────────────────
# CLI Commands
# ─────────────────────────────────────────────
CMD="${1:-}"

show_help() {
    echo ""
    echo "❌ Invalid or incomplete command"
    echo ""
    echo "👉 Available commands:"
    echo ""
    echo "  Upload:"
    echo "    ./nc.sh upload <file>"
    echo ""
    echo "  List:"
    echo "    ./nc.sh list <android> <device>"
    echo "    ./nc.sh list extras <android> <device>"
    echo ""
    echo "  Delete:"
    echo "    ./nc.sh delete <android> <device> <file>"
    echo "    ./nc.sh delete extras <android> <device> <file>"
    echo ""
    echo "💡 Examples:"
    echo "  ./nc.sh upload build.zip"
    echo "  ./nc.sh list A16 lemonadep"
    echo "  ./nc.sh delete A16 lemonadep old.zip"
    echo ""
}

case "$CMD" in
    upload)
        shift
        if [[ -z "${1:-}" ]]; then
            show_help
            exit 1
        fi
        upload_file "$1"
        ;;
    delete)
        shift
        if [[ "$1" == "extras" ]]; then
            [[ $# -lt 4 ]] && { show_help; exit 1; }
            delete_file "${BASE_DIR}/$2/$3/extras/$4"
        else
            [[ $# -lt 3 ]] && { show_help; exit 1; }
            delete_file "${BASE_DIR}/$1/$2/$3"
        fi
        ;;
    list)
        shift
        if [[ "$1" == "extras" ]]; then
            [[ $# -lt 3 ]] && { show_help; exit 1; }
            list_dir "${BASE_DIR}/$2/$3/extras"
        else
            [[ $# -lt 2 ]] && { show_help; exit 1; }
            list_dir "${BASE_DIR}/$1/$2"
        fi
        ;;
    *)
        show_help
        ;;
esac
#!/usr/bin/env bash

# ─────────────────────────────────────────────
#        Matrixx-OS Nextcloud CLI Tool
# ─────────────────────────────────────────────

NC_URL="https://files.dataheaven.space"
BASE_DIR="Matrixx-OS"
DRY_RUN=0

set -euo pipefail

# ─────────────────────────────────────────────
# Dry-run flag (must be parsed before set -u kicks in)
# ─────────────────────────────────────────────
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done

# ─────────────────────────────────────────────
# Load .env if present
# ─────────────────────────────────────────────
if [[ -f .env ]]; then
    PERMS=$(stat -c '%a' .env)
    if [[ "$PERMS" != "600" ]]; then
        echo "⚠️  Warning: .env permissions are ${PERMS}, recommend: chmod 600 .env" >&2
    fi
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
echo "[INFO] Server:       ${NC_URL}"
[[ $DRY_RUN -eq 1 ]] && echo "[INFO] Mode:         DRY-RUN (no changes will be made)"
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
        --connect-timeout 15 \
        -u "${NC_USER}:${NC_PASS}" \
        -X PROPFIND \
        "${WEBDAV_ROOT}/$1"
}

mkcol() {
    local FOLDER="$1"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would create folder: ${FOLDER}"
        return 0
    fi

    local HTTP
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 15 \
        -u "${NC_USER}:${NC_PASS}" \
        -X MKCOL \
        "${WEBDAV_ROOT}/${FOLDER}")

    # 201 = created, 405 = already exists (both are fine)
    if [[ "$HTTP" != "201" && "$HTTP" != "405" ]]; then
        echo "❌ Failed to create folder: ${FOLDER} (HTTP $HTTP)"
        exit 1
    fi
}

ensure_dir() {
    local DIR_PATH="$1"
    local STATUS
    STATUS=$(propfind_status "$DIR_PATH")

    if [[ "$STATUS" == "404" ]]; then
        mkcol "$DIR_PATH"
        echo "[OK] Created folder: ${DIR_PATH}"
    elif [[ "$STATUS" != "207" ]]; then
        echo "❌ Cannot access folder: ${DIR_PATH} (HTTP $STATUS)"
        exit 1
    fi
}

ensure_extras_folder() {
    local DEVICE_PATH="$1"
    ensure_dir "${DEVICE_PATH}/extras"
}

list_dir() {
    local DIR="$1"
    echo ""
    echo "📂 Listing: ${DIR}"
    echo "────────────────────────────"

    local HTTP_STATUS
    HTTP_STATUS=$(propfind_status "$DIR")
    if [[ "$HTTP_STATUS" != "207" ]]; then
        echo "❌ Cannot list directory (HTTP $HTTP_STATUS)"
        return 1
    fi

    curl -s -u "${NC_USER}:${NC_PASS}" \
        --connect-timeout 15 \
        -X PROPFIND \
        "${WEBDAV_ROOT}/${DIR}" \
        | grep -i "<[^:>]*:displayname>" \
        | sed 's/.*<[^>]*>//;s/<\/[^>]*//' \
        | tail -n +2  # skip parent dir entry

    echo ""
    log_action "LIST" "$DIR" "OK"
}

delete_file() {
    local REMOTE_PATH="$1"

    echo ""
    echo "⚠️  Delete: ${REMOTE_PATH}"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would delete: ${REMOTE_PATH}"
        return 0
    fi

    read -rp "Confirm delete? [y/N]: " CONFIRM
    [[ "$CONFIRM" != "y" ]] && { echo "❌ Cancelled."; exit 1; }

    local HTTP
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 15 \
        -u "${NC_USER}:${NC_PASS}" \
        -X DELETE \
        "${WEBDAV_ROOT}/${REMOTE_PATH}")

    if [[ "$HTTP" == "204" ]]; then
        echo "✅ Deleted successfully"
        log_action "DELETE" "${REMOTE_PATH}" "SUCCESS"
    else
        echo "❌ Delete failed (HTTP $HTTP)"
        log_action "DELETE" "${REMOTE_PATH}" "FAILED ($HTTP)"
    fi
}

move_file() {
    local SRC="$1"
    local DST="$2"

    echo ""
    echo "📦 Move/Rename:"
    echo "   From: ${SRC}"
    echo "   To:   ${DST}"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would move: ${SRC} → ${DST}"
        return 0
    fi

    local HTTP
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 15 \
        -u "${NC_USER}:${NC_PASS}" \
        -X MOVE \
        -H "Destination: ${WEBDAV_ROOT}/${DST}" \
        "${WEBDAV_ROOT}/${SRC}")

    if [[ "$HTTP" == "201" || "$HTTP" == "204" ]]; then
        echo "✅ Moved successfully"
        log_action "MOVE" "${SRC} → ${DST}" "SUCCESS"
    else
        echo "❌ Move failed (HTTP $HTTP)"
        log_action "MOVE" "${SRC} → ${DST}" "FAILED ($HTTP)"
    fi
}

# ─────────────────────────────────────────────
# Share (Direct Download Link)
# ─────────────────────────────────────────────
get_download_link() {
    local FILE_PATH="$1"

    local RESPONSE
    RESPONSE=$(curl -s \
        --connect-timeout 15 \
        -u "${NC_USER}:${NC_PASS}" \
        -X POST \
        -H "OCS-APIRequest: true" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "${NC_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares" \
        --data-urlencode "path=/${FILE_PATH}" \
        --data "shareType=3" \
        --data "permissions=1")

    # Try python3 JSON parse first, fall back to grep
    local URL
    URL=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['ocs']['data']['url'])
except Exception:
    pass
" 2>/dev/null)

    # Fallback grep if python3 not available or parse failed
    if [[ -z "$URL" ]]; then
        URL=$(echo "$RESPONSE" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)
    fi

    if [[ -n "$URL" ]]; then
        echo "${URL}/download"
    else
        echo ""
    fi
}

# ─────────────────────────────────────────────
# Upload with retry
# ─────────────────────────────────────────────
upload_with_retry() {
    local TARGET="$1"
    local FILE="$2"
    local LOCAL_MD5
    LOCAL_MD5=$(md5sum "$FILE" | cut -d' ' -f1)

    local MAX_ATTEMPTS=3
    local DELAY=5
    local HTTP=""

    for ((i=1; i<=MAX_ATTEMPTS; i++)); do
        echo "   Attempt ${i}/${MAX_ATTEMPTS}..."
        HTTP=$(curl --progress-bar \
            --connect-timeout 30 \
            -u "${NC_USER}:${NC_PASS}" \
            -H "OC-Checksum: MD5:${LOCAL_MD5}" \
            -T "$FILE" \
            -w "%{http_code}" \
            -o /dev/null \
            "$TARGET")

        if [[ "$HTTP" == "201" || "$HTTP" == "204" ]]; then
            echo "$HTTP"
            return 0
        fi

        echo "   ⚠️ Attempt ${i} failed (HTTP $HTTP)"
        (( i < MAX_ATTEMPTS )) && echo "   Retrying in ${DELAY}s..." && sleep "$DELAY"
    done

    echo "$HTTP"
    return 1
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

    local FILE_SIZE
    FILE_SIZE=$(du -sh "$FILE" | cut -f1)

    echo "Select Android version:"
    local OPTIONS=("A16")
    for i in "${!OPTIONS[@]}"; do
        echo "  $((i+1))) ${OPTIONS[$i]}"
    done

    read -rp "Choice: " CHOICE
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#OPTIONS[@]} )); then
        echo "❌ Invalid selection"
        exit 1
    fi

    local ANDROID="${OPTIONS[$((CHOICE-1))]}"
    local ANDROID_PATH="${BASE_DIR}/${ANDROID}"

    ensure_dir "$ANDROID_PATH"

    echo ""
    read -rp "Device name (e.g. lemonadep): " DEVICE

    if [[ -z "$DEVICE" ]]; then
        echo "❌ Device name cannot be empty"
        exit 1
    fi

    local DEVICE_PATH="${ANDROID_PATH}/${DEVICE}"
    ensure_dir "$DEVICE_PATH"
    ensure_extras_folder "$DEVICE_PATH"

    echo ""
    echo "Upload type:"
    echo "  1) ROM (default)"
    echo "  2) Extras"
    read -rp "Choice [1/2]: " TYPE

    local TARGET_PATH
    if [[ "$TYPE" == "2" ]]; then
        TARGET_PATH="${DEVICE_PATH}/extras"
    else
        TARGET_PATH="${DEVICE_PATH}"
    fi

    local FILENAME
    FILENAME="$(basename "$FILE")"
    local TARGET="${WEBDAV_ROOT}/${TARGET_PATH}/${FILENAME}"

    echo ""
    echo "🚀 Uploading:"
    echo "   File   : ${FILENAME}"
    echo "   Size   : ${FILE_SIZE}"
    echo "   Path   : ${TARGET_PATH}"
    echo "─────────────────────────────────────────"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would upload: ${FILENAME} → ${TARGET_PATH}"
        return 0
    fi

    local HTTP
    HTTP=$(upload_with_retry "$TARGET" "$FILE") || true

    echo ""
    echo "HTTP Status: $HTTP"

    # Verify file exists on server
    local FILE_CHECK
    FILE_CHECK=$(propfind_status "${TARGET_PATH}/${FILENAME}")

    if [[ "$FILE_CHECK" == "207" ]]; then
        echo "✅ Upload successful (verified)"
        log_action "UPLOAD" "${TARGET_PATH}/${FILENAME}" "SUCCESS"

        echo -n "🔗 Generating download link... "
        local LINK
        LINK=$(get_download_link "${TARGET_PATH}/${FILENAME}")

        if [[ -n "$LINK" ]]; then
            echo "OK"
            echo ""
            echo "📥 Direct Link:"
            echo "   ${LINK}"
        else
            echo "FAILED (share API issue)"
        fi
    else
        echo "❌ Upload failed (file not found on server after ${MAX_ATTEMPTS:-3} attempts)"
        log_action "UPLOAD" "${TARGET_PATH}/${FILENAME}" "FAILED ($HTTP)"
        exit 1
    fi

    echo ""
    echo "📁 View in browser:"
    echo "   ${NC_URL}/apps/files/?dir=/${TARGET_PATH}"
    echo ""
}

# ─────────────────────────────────────────────
# CLI Commands
# ─────────────────────────────────────────────
# Strip --dry-run from positional args
ARGS=()
for arg in "$@"; do
    [[ "$arg" != "--dry-run" ]] && ARGS+=("$arg")
done
set -- "${ARGS[@]:-}"

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
    echo "  Move/Rename:"
    echo "    ./nc.sh move <android> <device> <oldname> <newname>"
    echo "    ./nc.sh move extras <android> <device> <oldname> <newname>"
    echo ""
    echo "💡 Examples:"
    echo "  ./nc.sh upload build.zip"
    echo "  ./nc.sh list A16 lemonadep"
    echo "  ./nc.sh delete A16 lemonadep old.zip"
    echo "  ./nc.sh move A16 lemonadep old.zip new.zip"
    echo "  ./nc.sh --dry-run upload build.zip"
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
        if [[ "${1:-}" == "extras" ]]; then
            [[ $# -lt 4 ]] && { show_help; exit 1; }
            delete_file "${BASE_DIR}/$2/$3/extras/$4"
        else
            [[ $# -lt 3 ]] && { show_help; exit 1; }
            delete_file "${BASE_DIR}/$1/$2/$3"
        fi
        ;;
    list)
        shift
        if [[ "${1:-}" == "extras" ]]; then
            [[ -z "${2:-}" || -z "${3:-}" ]] && { show_help; exit 1; }
            list_dir "${BASE_DIR}/$2/$3/extras"
        else
            [[ -z "${1:-}" || -z "${2:-}" ]] && { show_help; exit 1; }
            list_dir "${BASE_DIR}/$1/$2"
        fi
        ;;
    move)
        shift
        if [[ "${1:-}" == "extras" ]]; then
            [[ $# -lt 5 ]] && { show_help; exit 1; }
            move_file "${BASE_DIR}/$2/$3/extras/$4" "${BASE_DIR}/$2/$3/extras/$5"
        else
            [[ $# -lt 4 ]] && { show_help; exit 1; }
            move_file "${BASE_DIR}/$1/$2/$3" "${BASE_DIR}/$1/$2/$4"
        fi
        ;;
    *)
        show_help
        ;;
esac

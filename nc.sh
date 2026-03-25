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
        --http1.1 \
        -u "${NC_USER}:${NC_PASS}" \
        -X PROPFIND \
        -H "Content-Type: application/xml" \
        -d '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>' \
        "${WEBDAV_ROOT}/$1"
}

mkcol() {
    local FOLDER="$1"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would create folder: ${FOLDER}"
        return 0
    fi

    curl -s -o /dev/null \
        --connect-timeout 15 \
        --http1.1 \
        -u "${NC_USER}:${NC_PASS}" \
        -X MKCOL \
        "${WEBDAV_ROOT}/${FOLDER}" || true

    # Verify folder actually exists regardless of what HTTP code MKCOL returned
    local VERIFY
    VERIFY=$(propfind_status "$FOLDER")
    if [[ "$VERIFY" != "207" ]]; then
        echo "❌ Failed to create folder: ${FOLDER} (PROPFIND returned $VERIFY)"
        exit 1
    fi
}

ensure_dir() {
    local DIR_PATH="$1"
    local PARTS=()
    local CURRENT=""

    # Split path into components and ensure each one exists top-down
    IFS='/' read -ra PARTS <<< "$DIR_PATH"
    for PART in "${PARTS[@]}"; do
        [[ -z "$PART" ]] && continue
        CURRENT="${CURRENT:+${CURRENT}/}${PART}"
        local STATUS
        STATUS=$(propfind_status "$CURRENT")
        if [[ "$STATUS" == "404" ]]; then
            mkcol "$CURRENT"
            echo "[OK] Created folder: ${CURRENT}"
        elif [[ "$STATUS" != "207" ]]; then
            echo "❌ Cannot access folder: ${CURRENT} (HTTP $STATUS)"
            exit 1
        fi
    done
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
        --http1.1 \
        -X PROPFIND \
        -H "Depth: 1" \
        -H "Content-Type: application/xml" \
        -d '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>' \
        "${WEBDAV_ROOT}/${DIR}" \
        | grep -o '<d:displayname>[^<]*</d:displayname>' \
        | sed 's/<d:displayname>//;s/<\/d:displayname>//' \
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

    # Extract URL from XML response
    _extract_url() {
        echo "$1" | grep -oP '(?<=<url>).*?(?=</url>)'
    }

    # Create share
    local RESPONSE
    RESPONSE=$(curl -s \
        --connect-timeout 15 \
        -u "${NC_USER}:${NC_PASS}" \
        -X POST \
        -H "OCS-APIRequest: true" \
        "${NC_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares" \
        --data-urlencode "path=/${FILE_PATH}" \
        --data "shareType=3" \
        --data "permissions=1")

    local URL
    URL=$(_extract_url "$RESPONSE")

    # If share already exists → fetch it
    if [[ -z "$URL" ]]; then
        local EXISTING
        EXISTING=$(curl -s \
            --connect-timeout 15 \
            -u "${NC_USER}:${NC_PASS}" \
            -X GET \
            -H "OCS-APIRequest: true" \
            "${NC_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares?path=/${FILE_PATH}&reshares=false")

        URL=$(_extract_url "$EXISTING")
    fi

    # Return clean download link
    [[ -n "$URL" ]] && echo "${URL}" || echo ""
}


# ─────────────────────────────────────────────
# Upload
# ─────────────────────────────────────────────
do_upload() {
    local TARGET="$1"
    local FILE="$2"
    local TMP_HTTP
    TMP_HTTP=$(mktemp)

    # curl writes progress bar to stderr → stays on terminal
    # -o /dev/null discards response body → no XML error leaking
    # -w "%{http_code}" goes to stdout → captured into tmpfile
    curl --progress-bar \
        --connect-timeout 30 \
        -u "${NC_USER}:${NC_PASS}" \
        -T "$FILE" \
        -o /dev/null \
        -w "%{http_code}" \
        "$TARGET" > "$TMP_HTTP" || true

    echo ""
    local HTTP
    HTTP=$(cat "$TMP_HTTP")
    rm -f "$TMP_HTTP"
    echo "$HTTP"
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

    echo "Fetching available Android versions..."
    local OPTIONS=()
    local RAW_VERSIONS
    RAW_VERSIONS=$(curl -s \
        --connect-timeout 15 \
        --http1.1 \
        -u "${NC_USER}:${NC_PASS}" \
        -X PROPFIND \
        -H "Depth: 1" \
        -H "Content-Type: application/xml" \
        -d '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>' \
        "${WEBDAV_ROOT}/${BASE_DIR}")

    while IFS= read -r line; do
        [[ -n "$line" && "$line" != "${BASE_DIR}" && "$line" != "$(basename "$BASE_DIR")" ]] && OPTIONS+=("$line")
    done < <(echo "$RAW_VERSIONS" \
        | grep -o '<d:displayname>[^<]*</d:displayname>' \
        | sed 's/<d:displayname>//;s/<\/d:displayname>//' \
        | tail -n +2)

    if [[ ${#OPTIONS[@]} -eq 0 ]]; then
        echo "❌ No Android version folders found in ${BASE_DIR}"
        exit 1
    fi

    echo ""
    echo "Select Android version:"
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

    echo ""
    read -rp "Device name (e.g. lemonadep): " DEVICE

    if [[ -z "$DEVICE" ]]; then
        echo "❌ Device name cannot be empty"
        exit 1
    fi

    local DEVICE_PATH="${ANDROID_PATH}/${DEVICE}"

    echo ""
    echo "  Android : ${ANDROID}"
    echo "  Device  : ${DEVICE}"
    read -rp "Confirm? [y/N]: " CONFIRM_DEVICE
    [[ "$CONFIRM_DEVICE" != "y" ]] && { echo "❌ Cancelled."; exit 1; }
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
    HTTP=$(do_upload "$TARGET" "$FILE")

    echo ""

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
        echo "❌ Upload failed (file not found on server)"
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
    echo "  Versions:"
    echo "    ./nc.sh versions"
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
    versions)
        list_dir "$BASE_DIR"
        ;;
    versions-debug)
        source .env 2>/dev/null || true
        WEBDAV_ROOT_DBG="${NC_URL}/remote.php/dav/files/${NC_USER}"
        echo "Raw PROPFIND output for ${BASE_DIR}:"
        curl -s \
            --connect-timeout 15 \
            --http1.1 \
            -u "${NC_USER}:${NC_PASS}" \
            -X PROPFIND \
            -H "Depth: 1" \
            -H "Content-Type: application/xml" \
            -d '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>' \
            "${WEBDAV_ROOT_DBG}/${BASE_DIR}" \
            | grep -o '<d:displayname>[^<]*</d:displayname>' \
            | sed 's/<d:displayname>//;s/<\/d:displayname>//'
        ;;
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
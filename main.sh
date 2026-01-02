#!/bin/bash

# =====================
# CONFIGURATION
# =====================
CREDENTIALS_FILE="$HOME/.yc_autostart_credentials"
CHECK_INTERVAL=60  # seconds

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =====================
# LOGGING
# =====================
log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GRAY}${ts}${NC} $1"
}

ok() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
err() { echo -e "${RED}$1${NC}"; }
info() { echo -e "${BLUE}$1${NC}"; }
dim() { echo -e "${GRAY}$1${NC}"; }

# =====================
# CREDENTIALS
# =====================
INSTANCE_ID="your-instance-id-here"
IAM_TOKEN="your-iam-token-here"

load_credentials() {
    if [ -f "$CREDENTIALS_FILE" ]; then
        source "$CREDENTIALS_FILE"
        log "$(ok "Credentials loaded from $CREDENTIALS_FILE")"
    else
        log "$(warn "No credentials file found, using globals")"
    fi
}

save_credentials() {
    echo "INSTANCE_ID=\"$INSTANCE_ID\"" > "$CREDENTIALS_FILE"
    echo "IAM_TOKEN=\"$IAM_TOKEN\"" >> "$CREDENTIALS_FILE"
    log "$(ok "Credentials saved to $CREDENTIALS_FILE")"
}

# =====================
# API FUNCTIONS
# =====================
exchange_oauth_to_iam() {
    local oauth="$1"
    local resp
    resp=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"yandexPassportOauthToken\":\"$oauth\"}" \
        https://iam.api.cloud.yandex.net/iam/v1/tokens)
    IAM_TOKEN=$(echo "$resp" | jq -r '.iamToken')
}

get_clouds() {
    local resp
    resp=$(curl -s -H "Authorization: Bearer $IAM_TOKEN" \
        https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds)
    echo "$resp" | jq -c '.clouds[]'
}

get_folders() {
    local cloud_id="$1"
    local resp
    resp=$(curl -s -H "Authorization: Bearer $IAM_TOKEN" \
        "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders?cloudId=$cloud_id")
    echo "$resp" | jq -c '.folders[]'
}

get_instances() {
    local folder_id="$1"
    local resp
    resp=$(curl -s -H "Authorization: Bearer $IAM_TOKEN" \
        "https://compute.api.cloud.yandex.net/compute/v1/instances?folderId=$folder_id")
    echo "$resp" | jq -c '.instances[]'
}

# =====================
# SELECT HELPERS
# =====================
select_item() {
    local items=("$@")
    if [ "${#items[@]}" -eq 1 ]; then
        echo "${items[0]}"
    else
        for i in "${!items[@]}"; do
            name=$(echo "${items[$i]}" | jq -r '.name')
            id=$(echo "${items[$i]}" | jq -r '.id')
            echo " $((i+1))) $name $(ok "$id")"
        done
        read -p "Select number or press Enter for ALL [default: all]: " choice
        if [ -z "$choice" ] || [ "$choice" == "0" ]; then
            echo "${items[@]}"
        else
            idx=$((choice-1))
            echo "${items[$idx]}"
        fi
    fi
}

# =====================
# GETMYINFO
# =====================
get_my_info() {
    echo -e "${BOLD}Yandex Cloud authorization required${NC}"
    echo -e "$(ok "https://yandex.cloud/ru/docs/iam/concepts/authorization/oauth-token")"
    read -p "Paste OAuth token: " oauth
    if [ -z "$oauth" ]; then
        err "OAuth token is empty"
        exit 1
    fi

    log "$(info "Exchanging OAuth → IAM")"
    exchange_oauth_to_iam "$oauth"
    log "$(ok "IAM token received")"

    mapfile -t clouds < <(get_clouds)
    declare -a selected_clouds
    if [ "${#clouds[@]}" -eq 1 ]; then
        selected_clouds=("${clouds[0]}")
    else
        echo
        echo -e "${BOLD}Available Clouds:${NC}"
        selected_clouds=($(select_item "${clouds[@]}"))
    fi

    declare -a all_instances
    for cloud in "${selected_clouds[@]}"; do
        cloud_name=$(echo "$cloud" | jq -r '.name')
        cloud_id=$(echo "$cloud" | jq -r '.id')
        log "$(info "Processing Cloud $cloud_name")"

        mapfile -t folders < <(get_folders "$cloud_id")
        declare -a selected_folders
        if [ "${#folders[@]}" -eq 1 ]; then
            selected_folders=("${folders[0]}")
        else
            echo
            echo -e "${BOLD}Available Folders:${NC}"
            selected_folders=($(select_item "${folders[@]}"))
        fi

        for folder in "${selected_folders[@]}"; do
            folder_name=$(echo "$folder" | jq -r '.name')
            folder_id=$(echo "$folder" | jq -r '.id')
            log "$(info "Fetching instances from folder $folder_name")"
            mapfile -t instances < <(get_instances "$folder_id")
            for inst in "${instances[@]}"; do
                inst_cloud="$cloud_name"
                inst_folder="$folder_name"
                all_instances+=("$(echo "$inst" | jq --arg c "$inst_cloud" --arg f "$inst_folder" '. + {cloud:$c, folder:$f}')")
            done
        done
    done

    echo
    echo -e "${BOLD}Available instances:${NC}"
    for inst in "${all_instances[@]}"; do
        name=$(echo "$inst" | jq -r '.name')
        id=$(echo "$inst" | jq -r '.id')
        pre=$(echo "$inst" | jq -r '.schedulingPolicy.preemptible')
        pflag=$( [ "$pre" == "true" ] && echo "$(ok YES)" || echo "$(warn NO)" )
        cloud=$(echo "$inst" | jq -r '.cloud')
        folder=$(echo "$inst" | jq -r '.folder')
        echo "$name"
        echo "  ID:           $(ok $id)"
        echo "  Preemptible:  $pflag"
        echo "  Cloud:        $cloud"
        echo "  Folder:       $folder"
        echo
    done

    echo "================================================================"
    echo -e "${BOLD}CONFIGURATION SUMMARY${NC}"
    echo "IAM_TOKEN = $(ok $IAM_TOKEN)"
    echo -e "${BOLD}Available instances:${NC}"
    for inst in "${all_instances[@]}"; do
        name=$(echo "$inst" | jq -r '.name')
        id=$(echo "$inst" | jq -r '.id')
        echo "$name"
        echo "  ID:           $(ok $id)"
        echo
    done

    read -p "Do you want to save IAM_TOKEN and INSTANCE_ID to file for future runs? [y/N]: " save
    if [[ "$save" =~ ^[Yy]$ ]]; then
        if [ "${#all_instances[@]}" -eq 1 ]; then
            INSTANCE_ID=$(echo "${all_instances[0]}" | jq -r '.id')
        else
            echo "Select INSTANCE_ID to save:"
            for i in "${!all_instances[@]}"; do
                name=$(echo "${all_instances[$i]}" | jq -r '.name')
                id=$(echo "${all_instances[$i]}" | jq -r '.id')
                echo " $((i+1))) $name $(ok $id)"
            done
            read -p "Select number [default 1]: " choice
            idx=$((choice-1))
            idx=${idx:-0}
            INSTANCE_ID=$(echo "${all_instances[$idx]}" | jq -r '.id')
        fi
        save_credentials
    fi
}

# =====================
# MONITORING
# =====================
start_instance_monitor() {
    local ts url response http_code body
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    url="https://compute.api.cloud.yandex.net/compute/v1/instances/${INSTANCE_ID}:start"

    response=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${IAM_TOKEN}" -H "Content-Type: application/json" "$url")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 202 ]; then
        echo -e "[$ts] $(ok "Start command sent successfully")"
    else
        echo -e "[$ts] $(err "Failed to start instance: HTTP $http_code")"
        echo "[$ts] Response: $body"
    fi
}

check_instance_status_monitor() {
    local ts url response http_code body status name
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    url="https://compute.api.cloud.yandex.net/compute/v1/instances/${INSTANCE_ID}"

    response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer ${IAM_TOKEN}" "$url")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" -eq 200 ]; then
        status=$(echo "$body" | jq -r '.status')
        name=$(echo "$body" | jq -r '.name')
        echo "[$ts] Instance: $name (ID: $INSTANCE_ID)"
        echo "[$ts] Status: $status"

        if [ "$status" == "RUNNING" ]; then
            echo -e "[$ts] $(ok "✓ Instance is RUNNING")"
        elif [ "$status" == "STOPPED" ]; then
            echo -e "[$ts] $(warn "⚠ Instance is STOPPED - attempting to start...")"
            start_instance_monitor
        else
            echo -e "[$ts] $(info "⏳ Instance status: $status")"
        fi
    else
        echo -e "[$ts] $(err "HTTP $http_code")"
    fi

    echo "------------------------------------------------------------"
}

# =====================
# MAIN
# =====================
load_credentials

if [[ "$1" == "--getmyinfo" ]]; then
    get_my_info
    exit 0
fi

if [[ "$INSTANCE_ID" == "your-instance-id-here" ]] || [[ "$IAM_TOKEN" == "your-iam-token-here" ]]; then
    echo -e "$(err "INSTANCE_ID and IAM_TOKEN must be set or saved in $CREDENTIALS_FILE")"
    exit 1
fi

echo "Starting instance status monitoring with auto-start..."
echo "Instance ID: $INSTANCE_ID"
echo "Check interval: $CHECK_INTERVAL seconds"
echo "============================================================"

trap 'echo -e "\n$(warn "Monitoring stopped by user")"; exit 0' INT

while true; do
    check_instance_status_monitor
    sleep "$CHECK_INTERVAL"
done

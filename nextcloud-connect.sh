#!/bin/bash
# Nextcloud WebDAV skill for OpenClaw

if [[ -f "$HOME/.openclaw/nextcloud.env" ]]; then
    source "$HOME/.openclaw/nextcloud.env"
fi

check_config() {
    if [[ -z "$NEXTCLOUD_URL" || -z "$NEXTCLOUD_USERNAME" || -z "$NEXTCLOUD_APP_PASSWORD" ]]; then
        echo '{"error": "Missing config"}'
        exit 1
    fi
}

get_workspace_path() {
    printf '%s' "${NEXTCLOUD_WORKSPACE:-Mark}"
}

get_dav_url() {
    echo "${NEXTCLOUD_URL}/remote.php/dav/files/${NEXTCLOUD_USERNAME}"
}

get_full_remote_path() {
    local relativePath="$1"
    local workspace
    workspace=$(get_workspace_path)
    local encodedWorkspace
    encodedWorkspace=$(echo "$workspace" | sed 's/ /%20/g; s/'"'"'/%27/g')
    [[ "$relativePath" != /* ]] && relativePath="/${relativePath}"
    echo "/${encodedWorkspace}${relativePath}"
}

upload() {
    local localPath="$1"
    local remotePath="$2"
    
    check_config
    
    if [[ ! -f "$localPath" ]]; then
        echo '{"error": "Local file not found"}'
        exit 1
    fi
    
    local fullRemotePath
    fullRemotePath=$(get_full_remote_path "$remotePath")
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${fullRemotePath}"
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        -T "$localPath" \
        "$fullUrl")
    
    if [[ "$response" == "201" || "$response" == "204" ]]; then
        echo "{\"success\": true, \"path\": \"${remotePath}\", \"status\": \"uploaded\"}"
    else
        echo "{\"error\": \"Upload failed with HTTP $response\"}"
    fi
}

download() {
    local remotePath="$1"
    local localPath="${2:-./$(basename "$remotePath")}"
    
    check_config
    
    local fullRemotePath
    fullRemotePath=$(get_full_remote_path "$remotePath")
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${fullRemotePath}"
    
    local httpCode
    httpCode=$(curl -s -o "$localPath" -w "%{http_code}" \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        --url "$fullUrl")
    
    if [[ "$httpCode" == "200" ]]; then
        echo "{\"success\": true, \"localPath\": \"${localPath}\", \"remotePath\": \"${remotePath}\"}"
    else
        rm -f "$localPath" 2>/dev/null
        echo "{\"error\": \"Download failed with HTTP $httpCode\"}"
    fi
}

list() {
    local path="${1:-/}"
    
    check_config
    
    local fullRemotePath
    fullRemotePath=$(get_full_remote_path "$path")
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${fullRemotePath}/"
    
    local response
    response=$(curl -s \
        -X PROPFIND \
        -H "Depth: 1" \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        --url "${fullUrl}")
    
    local files="["
    local first=true
    local tempFile
    tempFile=$(mktemp)
    
    echo "$response" | grep -oP '<d:href>[^<]+</d:href>' > "$tempFile"
    
    while IFS= read -r href; do
        local entry
        entry=$(echo "$href" | sed 's|<d:href>\(.*\)</d:href>|\1|')
        
        local filename
        filename=$(basename "$entry")
        [[ "$filename" == "." || "$filename" == ".." || "$filename" == "$(basename "$path")" ]] && continue
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            files="${files},"
        fi
        
        if [[ "$entry" == */ ]]; then
            files="${files}{\"name\": \"${filename%/}\", \"type\": \"folder\"}"
        else
            files="${files}{\"name\": \"${filename}\", \"type\": \"file\"}"
        fi
    done < "$tempFile"
    
    rm -f "$tempFile"
    files="${files}]"
    
    echo "{\"path\": \"${path:-/}\", \"files\": ${files}}"
}

mkdir() {
    local path="$1"
    
    check_config
    
    local fullRemotePath
    fullRemotePath=$(get_full_remote_path "$path")
    
    [[ "$fullRemotePath" != */ ]] && fullRemotePath="${fullRemotePath}/"
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${fullRemotePath}"
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X MKCOL \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        --url "$fullUrl")
    
    if [[ "$response" == "201" ]]; then
        echo "{\"success\": true, \"path\": \"${path}\", \"status\": \"created\"}"
    else
        echo "{\"error\": \"Failed to create folder (HTTP $response)\"}"
    fi
}

delete() {
    local path="$1"
    
    check_config
    
    local fullRemotePath
    fullRemotePath=$(get_full_remote_path "$path")
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${fullRemotePath}"
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X DELETE \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        --url "$fullUrl")
    
    if [[ "$response" == "204" ]]; then
        echo "{\"success\": true, \"path\": \"${path}\", \"status\": \"deleted\"}"
    else
        echo "{\"error\": \"Delete failed (HTTP $response)\"}"
    fi
}

main() {
    if [[ $# -lt 2 ]]; then
        echo '{"error": "Usage: $0 <action> <args...>"}'
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "$action" in
        upload) upload "$@" ;;
        download) download "$@" ;;
        list) list "$@" ;;
        mkdir) mkdir "$@" ;;
        delete) delete "$@" ;;
        *) echo '{"error": "Unknown action"}' ;;
    esac
}

main "$@"

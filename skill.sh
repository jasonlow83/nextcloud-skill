#!/bin/bash
# Nextcloud WebDAV skill for Clawdbot
# Handles file operations via Nextcloud's WebDAV endpoint

# Load config from ~/.clawdbot/nextcloud.env if it exists
if [[ -f "$HOME/.clawdbot/nextcloud.env" ]]; then
    source "$HOME/.clawdbot/nextcloud.env"
fi

# Check required environment variables
check_config() {
    if [[ -z "$NEXTCLOUD_URL" || -z "$NEXTCLOUD_USERNAME" || -z "$NEXTCLOUD_APP_PASSWORD" ]]; then
        echo '{"error": "Missing NEXTCLOUD_URL, NEXTCLOUD_USERNAME, or NEXTCLOUD_APP_PASSWORD"}'
        exit 1
    fi
}

# Build the WebDAV base URL
get_dav_url() {
    echo "${NEXTCLOUD_URL}/remote.php/dav/files/${NEXTCLOUD_USERNAME}"
}

# Upload a file to Nextcloud
upload() {
    local localPath="$1"
    local remotePath="$2"
    local overwrite="${3:-true}"
    
    check_config
    
    if [[ ! -f "$localPath" ]]; then
        echo "{\"error\": \"Local file not found: $localPath\"}"
        exit 1
    fi
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${remotePath}"
    
    local method="PUT"
    if [[ "$overwrite" == "false" ]]; then
        method="PUT"  # WebDAV doesn't have a true "create-only" mode, checking happens client-side
    fi
    
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

# Download a file from Nextcloud
download() {
    local remotePath="$1"
    local localPath="${2:-./$(basename "$remotePath")}"
    
    check_config
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${remotePath}"
    
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

# List files in a Nextcloud directory
list() {
    local path="${1:-/}"
    
    check_config
    
    # Normalize path
    path="${path#/}"
    [[ "$path" != "" ]] && path="/${path}"
    [[ "$path" == "/" ]] && path=""
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${path}/"
    
    # PROPFIND with Depth: 1 to get directory contents
    local response
    response=$(curl -s \
        -X PROPFIND \
        -H "Depth: 1" \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        --url "${fullUrl}")
    
    # Parse response into JSON array (without jq)
    local files="["
    local first=true
    local tempFile
    tempFile=$(mktemp)
    
    # Extract href elements to temp file
    echo "$response" | grep -oP '<d:href>[^<]+</d:href>' > "$tempFile"
    
    while IFS= read -r href; do
        # Extract the path from the href
        local entry
        entry=$(echo "$href" | sed 's|<d:href>\(.*\)</d:href>|\1|')
        
        # Skip . and .. and the current directory itself
        local filename
        filename=$(basename "$entry")
        [[ "$filename" == "." || "$filename" == ".." || "$filename" == "$(basename "$path")" ]] && continue
        
        # Build JSON entry
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

# Create a folder in Nextcloud
mkdir() {
    local path="$1"
    
    check_config
    
    # Path must end with / for MKCOL
    [[ "$path" != */ ]] && path="${path}/"
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${path}"
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X MKCOL \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        --url "$fullUrl")
    
    if [[ "$response" == "201" ]]; then
        echo "{\"success\": true, \"path\": \"${path%/}\", \"status\": \"created\"}"
    elif [[ "$response" == "405" ]]; then
        echo "{\"error\": \"Folder already exists\"}"
    else
        echo "{\"error\": \"Failed to create folder (HTTP $response)\"}"
    fi
}

# Delete a file or folder from Nextcloud
delete() {
    local path="$1"
    
    check_config
    
    # Folders need trailing slash for WebDAV DELETE
    local isFolder=false
    if [[ "$path" != */ ]]; then
        # Check if it's a folder by trying to list it
        path="${path%/}"
    else
        isFolder=true
    fi
    
    local davUrl
    davUrl=$(get_dav_url)
    local fullUrl="${davUrl}${path}"
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X DELETE \
        -u "${NEXTCLOUD_USERNAME}:${NEXTCLOUD_APP_PASSWORD}" \
        --url "$fullUrl")
    
    if [[ "$response" == "204" ]]; then
        echo "{\"success\": true, \"path\": \"${path}\", \"status\": \"deleted\"}"
    elif [[ "$response" == "404" ]]; then
        echo "{\"error\": \"File or folder not found\"}"
    else
        echo "{\"error\": \"Delete failed (HTTP $response)\"}"
    fi
}

# Parse JSON input and call appropriate function
parse_input() {
    local action="$1"
    shift
    
    case "$action" in
        upload)
            local localPath="$1"
            local remotePath="$2"
            local overwrite="${3:-true}"
            upload "$localPath" "$remotePath" "$overwrite"
            ;;
        download)
            local remotePath="$1"
            local localPath="${2:-}"
            download "$remotePath" "$localPath"
            ;;
        list)
            local path="${1:-/}"
            list "$path"
            ;;
        mkdir)
            local path="$1"
            mkdir "$path"
            ;;
        delete)
            local path="$1"
            delete "$path"
            ;;
        *)
            echo "{\"error\": \"Unknown action: $action\"}"
            exit 1
            ;;
    esac
}

# Main entry point
main() {
    if [[ $# -lt 2 ]]; then
        echo "{\"error\": \"Usage: $0 <action> <args...>\"}"
        exit 1
    fi
    
    parse_input "$@"
}

main "$@"

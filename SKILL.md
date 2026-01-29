# Nextcloud Skill

Upload, download, and manage files on a self-hosted Nextcloud instance via WebDAV.

## Overview

This skill enables Clawdbot to interact with Nextcloud file storage using the WebDAV protocol. Perfect for:
- Backing up workspace files to Nextcloud
- Syncing documents between local and cloud storage
- Automating file management tasks

## Tools

### nextcloud_upload
Upload a local file to Nextcloud.

**Parameters:**
- `localPath` (required): Path to the local file to upload
- `remotePath` (required): Destination path in Nextcloud (e.g., "/Documents/file.txt")
- `overwrite` (optional): Whether to overwrite if file exists (default: true)

**Example:**
```json
{
  "localPath": "/home/user/docs/report.pdf",
  "remotePath": "/Work/reports/2024/report.pdf"
}
```

### nextcloud_download
Download a file from Nextcloud to local storage.

**Parameters:**
- `remotePath` (required): Source path in Nextcloud (e.g., "/Documents/file.txt")
- `localPath` (optional): Local destination path (defaults to current directory with filename)

**Example:**
```json
{
  "remotePath": "/Documents/notes.md",
  "localPath": "/home/user/downloads/notes.md"
}
```

### nextcloud_list
List files and folders in a Nextcloud directory.

**Parameters:**
- `path` (optional): Remote path to list (default: "/")

**Example:**
```json
{
  "path": "/Work"
}
```

### nextcloud_mkdir
Create a new folder in Nextcloud.

**Parameters:**
- `path` (required): Full path of the new folder to create

**Example:**
```json
{
  "path": "/Backups/clawd-workspace"
}
```

### nextcloud_delete
Delete a file or folder from Nextcloud.

**Parameters:**
- `path` (required): Path to delete

**Example:**
```json
{
  "path": "/Old/notes.txt"
}
```

## Installation

### Option 1: ClawdHub (Recommended)
```bash
npx clawdhub@latest install nextcloud
```

### Option 2: Manual
Copy the `nextcloud` folder to your skills directory:
```bash
cp -r nextcloud ~/.clawdbot/skills/
```

## Configuration

Requires environment variables or config file at `~/.clawdbot/nextcloud.env`:

| Variable | Description |
|----------|-------------|
| `NEXTCLOUD_URL` | Full Nextcloud URL (e.g., "https://cloud.example.com") |
| `NEXTCLOUD_USERNAME` | Your Nextcloud username |
| `NEXTCLOUD_APP_PASSWORD` | App-specific password (NOT your main password) |

### Create Config File
```bash
# Create the config file
cat > ~/.clawdbot/nextcloud.env << EOF
NEXTCLOUD_URL="https://your-nextcloud.example.com"
NEXTCLOUD_USERNAME="your-username"
NEXTCLOUD_APP_PASSWORD="your-app-password"
EOF
chmod 600 ~/.clawdbot/nextcloud.env
```

## Setup Nextcloud App Password

1. Log into your Nextcloud instance (web interface)
2. Click your profile picture → **Settings**
3. Go to **Security** (left sidebar)
4. Under "App passwords", enter "Clawdbot" as the name
5. Click **Create new app password**
6. Copy the generated password and use it as `NEXTCLOUD_APP_PASSWORD`

## Usage Notes

- Paths are relative to your Nextcloud root (starts with `/`)
- Folders must exist before uploading files into them (use `nextcloud_mkdir` first)
- The WebDAV endpoint is automatically constructed as `{NEXTCLOUD_URL}/remote.php/dav/files/{USERNAME}/`
- No external dependencies required (uses standard `curl`)

## Example Workflow

```bash
# List files in root directory
clawdhub skill run nextcloud list '/'

# Create a workspace folder
clawdhub skill run nextcloud mkdir '/MyWorkspace'

# Upload a file
clawdhub skill run nextcloud upload '/local/file.md' '/MyWorkspace/file.md'

# Download a file
clawdhub skill run nextcloud download '/MyWorkspace/file.md' '/local/downloads/'

# Delete when done
clawdhub skill run nextcloud delete '/MyWorkspace'
```

## Requirements

- Self-hosted Nextcloud instance (v18+ recommended)
- App password enabled in Nextcloud security settings
- `curl` installed on the system

## Troubleshooting

- **HTTP 000**: Usually a connection issue - check URL and network connectivity
- **HTTP 401**: Authentication failed - verify username and app password
- **HTTP 405**: Resource already exists (for mkdir)
- **HTTP 404**: Resource not found (for download/delete)

## License

MIT - Feel free to use and modify for your needs.


#!/bin/bash
# Support Bundle Download Script
# Usage: ./support_bundle_download.sh <REMOTE_SERVER> <REMOTE_PATH> <LOCAL_DIR>

REMOTE_SERVER="$1"
REMOTE_PATH="$2"
LOCAL_DIR="$3"

if [[ -z "$REMOTE_SERVER" || -z "$REMOTE_PATH" || -z "$LOCAL_DIR" ]]; then
    echo "Usage: $0 <REMOTE_SERVER> <REMOTE_PATH> <LOCAL_DIR>"
    exit 1
fi

mkdir -p "$LOCAL_DIR"

# SSH options for non-interactive key-based authentication
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=30"

# Use rsync as the primary transfer method so only missing/changed files are copied.
if rsync -az --partial --human-readable --itemize-changes -e "ssh $SSH_OPTS" "$REMOTE_SERVER:$REMOTE_PATH/" "$LOCAL_DIR/"; then
    echo "✅ Incremental sync complete via rsync"
else
    echo "⚠️  rsync failed, trying scp..."
    if scp -r $SSH_OPTS "$REMOTE_SERVER:$REMOTE_PATH/*" "$LOCAL_DIR/"; then
        echo "✅ Download complete via scp (non-incremental fallback)"
    else
        echo "❌ Download failed!"
        exit 1
    fi
fi

#!/bin/bash
# Extract case number and remote path from JIRA ticket
# Usage: ./jira_extract_case_path.sh <TICKET_ID>

TICKET_ID="$1"
JIRA_URL="https://infoblox.atlassian.net"
JIRA_API="$JIRA_URL/rest/api/3"

# Load credentials (supports both key=value and user:token formats)
if [[ -f ~/.jira-credentials ]]; then
    source ~/.jira-credentials 2>/dev/null
    if [[ -z "$JIRA_USER" || -z "$JIRA_TOKEN" ]]; then
        CRED_LINE=$(head -1 ~/.jira-credentials)
        if [[ "$CRED_LINE" =~ ^([^:]+):(.+)$ ]]; then
            export JIRA_USER="${BASH_REMATCH[1]}"
            export JIRA_TOKEN="${BASH_REMATCH[2]}"
        fi
    fi
fi

if [[ -z "$JIRA_USER" || -z "$JIRA_TOKEN" ]]; then
    echo "JIRA credentials not found."
    exit 1
fi

RESPONSE=$(curl -s -u "$JIRA_USER:$JIRA_TOKEN" -H "Accept: application/json" \
    "$JIRA_API/issue/$TICKET_ID?fields=summary,description,comment")

# Build searchable text from summary + full description + all comments.
SEARCH_TEXT=$(echo "$RESPONSE" | jq -r '
    [
      .fields.summary,
      (.fields.description | .. | strings),
      (.fields.comment.comments[]?.body | .. | strings)
    ] | .[] | select(. != null and . != "")')

# Prefer an explicit remote path from ticket body/comments when available.
EXPLICIT_PATH=$(echo "$SEARCH_TEXT" | grep -oE '/import[^[:space:]"'"'"'<>)]+' | head -1)
if [[ -z "$EXPLICIT_PATH" ]]; then
    EXPLICIT_PATH=$(echo "$SEARCH_TEXT" | grep -oE '/mnt/working/cases/C[0-9]{6,}/[A-Za-z0-9._-]+' | head -1)
fi

# Trim trailing punctuation often present in prose.
EXPLICIT_PATH=$(echo "$EXPLICIT_PATH" | sed 's/[),.;:]$//')

if [[ -n "$EXPLICIT_PATH" ]]; then
    echo "$EXPLICIT_PATH"
    exit 0
fi

# Fallback: derive case number from summary/description/comments.
CASE_NUM=$(echo "$SEARCH_TEXT" | grep -oE 'C[0-9]{6,}' | head -1 | sed 's/^C//')
if [[ -z "$CASE_NUM" ]]; then
    CASE_NUM=$(echo "$SEARCH_TEXT" | grep -oE '[0-9]{6,}' | head -1)
fi
if [[ -z "$CASE_NUM" ]]; then
    echo "Could not extract case number from JIRA."
    exit 2
fi
REMOTE_PATH="/mnt/working/cases/C${CASE_NUM}/${TICKET_ID}"
echo "$REMOTE_PATH"

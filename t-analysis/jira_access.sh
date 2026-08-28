#!/bin/bash
# JIRA Access Script - Fetch ticket summary, description, and comments
# Usage: ./jira_access.sh <TICKET_ID>

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

SUMMARY=$(echo "$RESPONSE" | jq -r '.fields.summary // "N/A"')
DESCRIPTION=$(echo "$RESPONSE" | jq -r '[.fields.description | .. | strings] | join(" ") // "N/A"')
COMMENT_COUNT=$(echo "$RESPONSE" | jq -r '.fields.comment.comments | length // 0')

echo "Summary: $SUMMARY"
echo "Description: $DESCRIPTION"
echo "Comments Count: $COMMENT_COUNT"

if [[ "$COMMENT_COUNT" -gt 0 ]]; then
    echo "Comments:"
    echo "$RESPONSE" | jq -r '.fields.comment.comments[] |
        "- [" + (.created // "unknown-time") + "] " + ([.body | .. | strings] | join(" "))'
fi

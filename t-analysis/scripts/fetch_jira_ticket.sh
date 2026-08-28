#!/bin/bash
# Usage: fetch_jira_ticket.sh <TICKET_ID>
# Fetches JIRA ticket details using credentials from ~/.jira-credential
# Example: ./fetch_jira_ticket.sh NIOSSPT-XXXXX

if [ -z "$1" ]; then
  echo "Usage: $0 <TICKET_ID>"
  exit 1
fi

TICKET_ID="$1"
if [ -f "$HOME/.jira-credential" ]; then
  CRED_FILE="$HOME/.jira-credential"
elif [ -f "$HOME/.jira-credentials" ]; then
  CRED_FILE="$HOME/.jira-credentials"
else
  echo "JIRA credential file not found at $HOME/.jira-credential or $HOME/.jira-credentials"
  exit 2
fi
JIRA_URL="https://infoblox.atlassian.net/rest/api/2/issue/$TICKET_ID"

if [ ! -f "$CRED_FILE" ]; then
  echo "JIRA credential file not found at $CRED_FILE"
  exit 2
fi

# Expecting ~/.jira-credential to have: username:password or username:api_token
CRED=$(cat "$CRED_FILE" | tr -d '\n')

curl -s -u "$CRED" -H "Content-Type: application/json" "$JIRA_URL" | jq .

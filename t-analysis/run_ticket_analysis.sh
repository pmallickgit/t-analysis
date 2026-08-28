#!/bin/bash
# Main Ticket Analysis Orchestrator
# Usage: ./run_ticket_analysis.sh <TICKET_ID>

TICKET_ID="$1"
if [[ -z "$TICKET_ID" ]]; then
    echo "Usage: $0 <TICKET_ID>"
    exit 1
fi

# Step 1: Fetch JIRA details
./jira_access.sh "$TICKET_ID"


# Step 2: Download support bundles (auto-populate REMOTE_PATH from JIRA)
REMOTE_SERVER="pmallick@sup-xfer-01.inca.infoblox.com"
REMOTE_PATH=$(./jira_extract_case_path.sh "$TICKET_ID")
if [[ -z "$REMOTE_PATH" ]]; then
    echo "Could not determine remote path from JIRA."
    exit 2
fi
LOCAL_DIR="$HOME/analysis_support_tickets/$TICKET_ID/remote_files"

./support_bundle_download.sh "$REMOTE_SERVER" "$REMOTE_PATH" "$LOCAL_DIR"

echo "Analysis preparation complete. Proceed with extraction and error analysis as per workflow."

#!/bin/bash

################################################################################
# t-analysis Entry Point for NIOSSPT 7-Point Workflow
#
# Usage:
#   bash t-analysis/analyze-ticket.sh NIOSSPT-XXXXX
#   bash t-analysis/analyze-ticket.sh "https://infoblox.atlassian.net/browse/NIOSSPT-XXXXX"
#   bash t-analysis/analyze-ticket.sh NIOSSPT-XXXXX --skip-download --verbose
################################################################################

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <ticket-id-or-url> [--skip-download] [--verbose] [.]"
    echo ""
    echo "Examples:"
    echo "  $0 NIOSSPT-XXXXX"
    echo "  $0 'https://infoblox.atlassian.net/browse/NIOSSPT-XXXXX'"
    echo "  $0 NIOSSPT-XXXXX --skip-download"
    echo ""
    exit 1
fi

TA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RAW_INPUT="$1"
shift

# Accept slash-command style prompts and Jira URLs by extracting a NIOSSPT ticket.
shopt -s nocasematch
NORMALIZED_TICKET=""

if [[ "$RAW_INPUT" =~ (NIOSSPT-[0-9]+) ]]; then
    NORMALIZED_TICKET="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
elif [[ $# -gt 0 && "$1" =~ ^NIOSSPT-[0-9]+$ ]]; then
    NORMALIZED_TICKET="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    shift
else
    NORMALIZED_TICKET="$RAW_INPUT"
fi

# Ignore optional trailing '.' arguments.
FORWARDED_ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "." ]]; then
        continue
    fi
    FORWARDED_ARGS+=("$arg")
done

bash "$TA_DIR/run-complete-analysis.sh" "$NORMALIZED_TICKET" "${FORWARDED_ARGS[@]}"

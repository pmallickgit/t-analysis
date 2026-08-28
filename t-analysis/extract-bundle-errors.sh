#!/bin/bash
# Extract Errors from Support Bundle Log Files
# Usage: ./extract-bundle-errors.sh <TICKET_ID>

TICKET_ID="${1}"

if [[ -z "$TICKET_ID" ]]; then
    echo "❌ Error: Ticket ID required"
    echo "Usage: bash extract-bundle-errors.sh NIOSSPT-XXXXX"
    exit 1
fi

# Prefer canonical ticket directory from ticket id, fallback to current directory.
if [[ -d "$HOME/analysis_support_tickets/$TICKET_ID" ]]; then
    TICKET_DIR="$HOME/analysis_support_tickets/$TICKET_ID"
else
    TICKET_DIR="$(pwd)"
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          EXTRACTING ERRORS FROM BUNDLE LOG FILES          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Ticket ID: $TICKET_ID"
echo "Directory: $TICKET_DIR"
echo ""

# Create generated directory
GENERATED_DIR="${TICKET_DIR}/generated"
mkdir -p "$GENERATED_DIR"
echo "📁 Created output directory: generated/"
echo ""

# Find all potential bundle directories (exclude common system directories)
BUNDLE_COUNT=0
ERROR_COUNT=0

# Derive problem-specific keywords from the Jira problem summary for targeted extraction.
# Keep defaults generic; add license-specific terms only when ticket text indicates license scope.
PROBLEM_KEYWORDS="error|fail|exception|critical|warn|alert|timeout|dns|named|dca|vdca|fastpath|replica|clusterd|database|reset_node"
if [[ -f "$TICKET_DIR/02_jira_problem_summary.md" ]]; then
    if grep -qiE 'license|licens|sw_tp|tp_licens|tp_license' "$TICKET_DIR/02_jira_problem_summary.md"; then
        PROBLEM_KEYWORDS="${PROBLEM_KEYWORDS}|sw_tp|licens|delet|tp_license|addlicense|invalid"
    fi

    EXTRA_KW=$(grep -oiE '\b[a-z][a-z0-9_]{4,}\b' "$TICKET_DIR/02_jira_problem_summary.md" 2>/dev/null \
        | grep -viE '^(analysis|support|bundle|ticket|system|infoblox|error|warning|summary|description|content|block|level|heading|strong)$' \
        | sort -u | head -20 | tr '\n' '|' | sed 's/|$//')
    [[ -n "$EXTRA_KW" ]] && PROBLEM_KEYWORDS="${PROBLEM_KEYWORDS}|${EXTRA_KW}"
fi
echo "🔑 Problem keywords for targeted search: $PROBLEM_KEYWORDS"
echo ""

# Find the root directory containing support bundle logs.
# Actual bundle logs live at: remote_files/BUNDLE_EXTRACT/{active,passive}/infoblox.log
LOG_SEARCH_ROOT="$TICKET_DIR/remote_files"
[[ ! -d "$LOG_SEARCH_ROOT" ]] && LOG_SEARCH_ROOT="$TICKET_DIR"

# Iterate over every infoblox.log found under the support bundle directories
while IFS= read -r FOUND_LOG; do
    LOG_DIR=$(dirname "$FOUND_LOG")

    # Derive a stable bundle name from the path relative to the search root
    REL_PATH="${LOG_DIR#$LOG_SEARCH_ROOT/}"
    BUNDLE_NAME=$(echo "$REL_PATH" | tr '/' '_')
    [[ -z "$BUNDLE_NAME" ]] && BUNDLE_NAME="root_bundle"

    LOG_LOCATIONS=("$LOG_DIR")
    LOGS_FOUND=1
    BUNDLE_DIR="$LOG_DIR"

    echo "🔍 Processing Bundle: $BUNDLE_NAME"
    ((BUNDLE_COUNT++))

    # Create error file for this bundle
    ERROR_FILE="${GENERATED_DIR}/${BUNDLE_NAME}_errors_warnings.txt"
    SYSTEM_FILE="${GENERATED_DIR}/${BUNDLE_NAME}_system_summary.txt"

    # Extract errors and warnings
    {
        echo "=========================================="
        echo "ERRORS AND WARNINGS SUMMARY"
        echo "Bundle: $BUNDLE_NAME"
        echo "Ticket: $TICKET_ID"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo ""

        FOUND_ERRORS=0

        # Search for infoblox.log in multiple locations
        echo "--- INFOBLOX LOG ERRORS ---"
        for LOG_LOC in "${LOG_LOCATIONS[@]}"; do
            if [[ -f "$LOG_LOC/infoblox.log" ]]; then
                echo "Source: $LOG_LOC/infoblox.log"
                grep -iE "error|fail|exception|critical" "$LOG_LOC/infoblox.log" 2>/dev/null | head -100
                FOUND_ERRORS=1
            fi
            # Also check compressed logs
            if ls "$LOG_LOC/infoblox.log"*.gz 2>/dev/null | head -1 >/dev/null; then
                echo "Source: $LOG_LOC/infoblox.log*.gz"
                zgrep -iE "error|fail|exception|critical" "$LOG_LOC/infoblox.log"*.gz 2>/dev/null | head -100
                FOUND_ERRORS=1
            fi
        done
        echo ""

        # Search for warnings in infoblox.log
        echo "--- INFOBLOX LOG WARNINGS ---"
        for LOG_LOC in "${LOG_LOCATIONS[@]}"; do
            if [[ -f "$LOG_LOC/infoblox.log" ]]; then
                grep -iE "warn|alert" "$LOG_LOC/infoblox.log" 2>/dev/null | head -50
                FOUND_ERRORS=1
            fi
            if ls "$LOG_LOC/infoblox.log"*.gz 2>/dev/null | head -1 >/dev/null; then
                zgrep -iE "warn|alert" "$LOG_LOC/infoblox.log"*.gz 2>/dev/null | head -50
                FOUND_ERRORS=1
            fi
        done
        echo ""

        # Search for syslog errors
        echo "--- SYSLOG ERRORS ---"
        for LOG_LOC in "${LOG_LOCATIONS[@]}"; do
            # Check plain syslog files
            if ls "$LOG_LOC"/syslog* 2>/dev/null | grep -v "\.gz$" | head -1 >/dev/null; then
                echo "Source: $LOG_LOC/syslog*"
                grep -iE "error|fail|critical|panic" "$LOG_LOC"/syslog* 2>/dev/null | grep -v "\.gz:" | head -50
                FOUND_ERRORS=1
            fi
            # Check compressed syslog files
            if ls "$LOG_LOC"/syslog*.gz 2>/dev/null | head -1 >/dev/null; then
                echo "Source: $LOG_LOC/syslog*.gz"
                zgrep -iE "error|fail|critical|panic" "$LOG_LOC"/syslog*.gz 2>/dev/null | head -50
                FOUND_ERRORS=1
            fi
        done
        echo ""

        # Search for messages errors
        echo "--- MESSAGES LOG ERRORS ---"
        for LOG_LOC in "${LOG_LOCATIONS[@]}"; do
            # Check plain messages files
            if ls "$LOG_LOC"/messages* 2>/dev/null | grep -v "\.gz$" | head -1 >/dev/null; then
                echo "Source: $LOG_LOC/messages*"
                grep -iE "error|fail|critical|panic" "$LOG_LOC"/messages* 2>/dev/null | grep -v "\.gz:" | head -50
                FOUND_ERRORS=1
            fi
            # Check compressed messages files
            if ls "$LOG_LOC"/messages*.gz 2>/dev/null | head -1 >/dev/null; then
                echo "Source: $LOG_LOC/messages*.gz"
                zgrep -iE "error|fail|critical|panic" "$LOG_LOC"/messages*.gz 2>/dev/null | head -50
                FOUND_ERRORS=1
            fi
        done
        echo ""

        if [[ $FOUND_ERRORS -eq 0 ]]; then
            echo "✅ No errors or warnings found in this bundle"
        fi

        # Problem-specific keyword extraction against all log types
        echo "--- PROBLEM-SPECIFIC KEYWORD MATCHES ---"
        for LOG_LOC in "${LOG_LOCATIONS[@]}"; do
            for LOGFILE in infoblox.log audit.log infoblox_stderr.log upgrade.log; do
                if [[ -f "$LOG_LOC/$LOGFILE" ]]; then
                    MATCHES=$(grep -iE "$PROBLEM_KEYWORDS" "$LOG_LOC/$LOGFILE" 2>/dev/null | head -200)
                    if [[ -n "$MATCHES" ]]; then
                        echo "Source: $LOG_LOC/$LOGFILE"
                        echo "$MATCHES"
                        FOUND_ERRORS=1
                    fi
                fi
                # Compressed variants
                for GZ in "$LOG_LOC/${LOGFILE}"*.gz; do
                    [[ -f "$GZ" ]] || continue
                    MATCHES=$(zgrep -iE "$PROBLEM_KEYWORDS" "$GZ" 2>/dev/null | head -100)
                    if [[ -n "$MATCHES" ]]; then
                        echo "Source: $GZ"
                        echo "$MATCHES"
                        FOUND_ERRORS=1
                    fi
                done
            done
        done
        echo ""

        echo "=========================================="
        echo "END OF ERROR SUMMARY"
        echo "=========================================="

    } > "$ERROR_FILE"

    # Create system summary
    {
        echo "=========================================="
        echo "SYSTEM INFORMATION SUMMARY"
        echo "Bundle: $BUNDLE_NAME"
        echo "Ticket: $TICKET_ID"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo ""

        # Find version info
        echo "--- SYSTEM VERSION ---"
        for LOG_LOC in "${LOG_LOCATIONS[@]}"; do
            # Check for version files in bundle root
            BUNDLE_ROOT=$(dirname "$LOG_LOC")
            if [[ -f "$BUNDLE_ROOT/VERSION" ]]; then
                cat "$BUNDLE_ROOT/VERSION" 2>/dev/null
            elif [[ -f "$BUNDLE_ROOT/version.txt" ]]; then
                cat "$BUNDLE_ROOT/version.txt" 2>/dev/null
            fi
        done
        echo ""

        # Check for hardware info
        echo "--- HARDWARE INFO ---"
        for LOG_LOC in "${LOG_LOCATIONS[@]}"; do
            if [[ -f "$LOG_LOC/../proc/cpuinfo" ]]; then
                grep -E "model name|cpu cores|siblings" "$LOG_LOC/../proc/cpuinfo" 2>/dev/null | head -5
            fi
        done
        echo ""

    } > "$SYSTEM_FILE"

    # Check sizes and report
    ERROR_SIZE=$(wc -c < "$ERROR_FILE" 2>/dev/null || echo "0")
    if [[ $ERROR_SIZE -gt 2000 ]]; then
        echo "   ✅ Created: ${BUNDLE_NAME}_errors_warnings.txt (${ERROR_SIZE} bytes)"
        ((ERROR_COUNT++))
    else
        echo "   ℹ️  Created: ${BUNDLE_NAME}_errors_warnings.txt (minimal errors)"
    fi
    echo "   ✅ Created: ${BUNDLE_NAME}_system_summary.txt"
    echo ""

done < <(find "$LOG_SEARCH_ROOT" -name "infoblox.log" -type f 2>/dev/null | sort)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ EXTRACTION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Summary:"
echo "   • Bundles processed: $BUNDLE_COUNT"
echo "   • Bundles with errors: $ERROR_COUNT"
echo "   • Output directory: generated/"
echo ""
echo "📁 Generated files:"
ls -lh "$GENERATED_DIR"/*.txt 2>/dev/null | awk '{print "   •", $9, "("$5")"}'
echo ""
echo "🎯 Next step: Generate RCA reports"
echo "   cd ~/analysis_support_tickets/$TICKET_ID"
echo "   python3 ~/Downloads/old_mac/analysis_data/skills_desk/generate-final-rca.py ."
echo ""

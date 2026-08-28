#!/bin/bash
# Run Scripts from Extracted Support Bundles and Generate Analysis
# Usage: ./run-bundle-scripts.sh <TICKET_ID> [--skip-extraction]

TICKET_ID="${1}"
SKIP_EXTRACTION="${2:-}"

if [[ -z "$TICKET_ID" ]]; then
    echo "❌ Error: Ticket ID required"
    echo "Usage: bash run-bundle-scripts.sh NIOSSPT-XXXXX [--skip-extraction]"
    exit 1
fi

# Set up directories
if [[ -d "$HOME/analysis_support_tickets/$TICKET_ID" ]]; then
    TICKET_DIR="$HOME/analysis_support_tickets/$TICKET_ID"
else
    TICKET_DIR="$(pwd)"
fi

SCRIPT_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$SCRIPT_BASE_DIR/scripts"
GENERATED_DIR="${TICKET_DIR}/generated"
BUNDLE_ANALYSIS_DIR="${GENERATED_DIR}/bundle_script_analysis"

# Create directories
mkdir -p "$GENERATED_DIR"
mkdir -p "$BUNDLE_ANALYSIS_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     RUNNING BUNDLE SCRIPTS AND GENERATING ANALYSIS        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Ticket ID: $TICKET_ID"
echo "Ticket Directory: $TICKET_DIR"
echo "Scripts Base: $SCRIPTS_DIR"
echo ""

# Count statistics
BUNDLES_PROCESSED=0
SCRIPTS_RUN=0
SCRIPTS_FAILED=0
TOTAL_ANALYSIS_SIZE=0
SEEN_BUNDLE_DIRS=""

# Track all results for summary report
SUMMARY_FILE="${GENERATED_DIR}/bundle_scripts_summary.txt"

{
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     BUNDLE SCRIPTS EXECUTION SUMMARY REPORT               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Ticket ID: $TICKET_ID"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Script Base Directory: $SCRIPTS_DIR"
    echo ""
    echo "Available Analysis Scripts:"
    if [[ -d "$SCRIPTS_DIR" ]]; then
        ls -1 "$SCRIPTS_DIR"/*.sh 2>/dev/null | xargs -I {} basename {} | nl
    fi
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo ""
} > "$SUMMARY_FILE"

process_bundle_dir() {
    local BUNDLE_DIR="$1"
    local BUNDLE_NAME="$2"
    local VAR_LOG_DIR="$3"
    local BUNDLE_OUTPUT_DIR
    local BUNDLE_REPORT
    local SCRIPT
    local SCRIPT_NAME
    local SCRIPT_OUTPUT
    local OUTPUT_SIZE
    local LINES
    local ANALYSIS_SCRIPT

    # Keep compatibility with macOS bash 3 (no associative arrays)
    if printf '%s\n' "$SEEN_BUNDLE_DIRS" | grep -Fxq "$BUNDLE_DIR"; then
        return
    fi
    SEEN_BUNDLE_DIRS+="$BUNDLE_DIR"$'\n'

    echo "🔍 Processing Bundle: $BUNDLE_NAME"
    ((BUNDLES_PROCESSED++))

    # Create bundle-specific output directory
    BUNDLE_OUTPUT_DIR="$BUNDLE_ANALYSIS_DIR/$BUNDLE_NAME"
    mkdir -p "$BUNDLE_OUTPUT_DIR"

    # Create bundle analysis report
    BUNDLE_REPORT="${BUNDLE_OUTPUT_DIR}/analysis_report.txt"
    {
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║     BUNDLE SCRIPT ANALYSIS REPORT                         ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Bundle Name: $BUNDLE_NAME"
        echo "Analysis Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "VAR/LOG Directory: $VAR_LOG_DIR"
        echo ""
    } > "$BUNDLE_REPORT"

    # Check for scripts in var/log directory
    if [[ -n "$VAR_LOG_DIR" ]]; then
        echo "  📂 Checking for scripts in: $VAR_LOG_DIR"

        # Check for scripts subdirectory
        if [[ -d "$VAR_LOG_DIR/scripts" ]]; then
            echo "  ✓ Found scripts directory: $VAR_LOG_DIR/scripts"
            
            # Run each script found in bundle's scripts directory
            for SCRIPT in "$VAR_LOG_DIR/scripts"/*.sh; do
                [[ ! -f "$SCRIPT" ]] && continue

                SCRIPT_NAME=$(basename "$SCRIPT")
                echo "  ⚙️  Running: $SCRIPT_NAME"
                ((SCRIPTS_RUN++))

                # Create output file for this script
                SCRIPT_OUTPUT="${BUNDLE_OUTPUT_DIR}/${SCRIPT_NAME%.*}_output.txt"

                # Run script and capture output
                if bash "$SCRIPT" > "$SCRIPT_OUTPUT" 2>&1; then
                    OUTPUT_SIZE=$(du -h "$SCRIPT_OUTPUT" | awk '{print $1}')
                    LINES=$(wc -l < "$SCRIPT_OUTPUT")
                    echo "    ✅ Success - $LINES lines, $OUTPUT_SIZE"
                    
                    {
                        echo "---"
                        echo "Script: $SCRIPT_NAME"
                        echo "Status: ✅ Success"
                        echo "Output Lines: $LINES"
                        echo "Output File: $SCRIPT_OUTPUT"
                        echo "---"
                        echo ""
                    } >> "$BUNDLE_REPORT"
                else
                    ((SCRIPTS_FAILED++))
                    echo "    ❌ Failed"
                    
                    {
                        echo "---"
                        echo "Script: $SCRIPT_NAME"
                        echo "Status: ❌ Failed"
                        echo "---"
                        echo ""
                    } >> "$BUNDLE_REPORT"
                fi
            done
        else
            echo "  ℹ️  No scripts directory found in $VAR_LOG_DIR"
        fi
    fi

    # Run scripts from base scripts directory against this bundle's logs
    echo "  📂 Running base analysis scripts against logs..."
    
    if [[ -d "$SCRIPTS_DIR" ]]; then
        for ANALYSIS_SCRIPT in "$SCRIPTS_DIR"/*.sh; do
            [[ ! -f "$ANALYSIS_SCRIPT" ]] && continue

            SCRIPT_NAME=$(basename "$ANALYSIS_SCRIPT")
            echo "  ⚙️  Running: $SCRIPT_NAME"
            ((SCRIPTS_RUN++))

            # Create output file
            SCRIPT_OUTPUT="${BUNDLE_OUTPUT_DIR}/${SCRIPT_NAME%.*}_analysis.txt"

            # Run script with bundle directory as context
            # Scripts can use environment variables to know where logs are
            if VAR_LOG="$VAR_LOG_DIR" BUNDLE_DIR="$BUNDLE_DIR" BUNDLE_NAME="$BUNDLE_NAME" bash "$ANALYSIS_SCRIPT" > "$SCRIPT_OUTPUT" 2>&1; then
                OUTPUT_SIZE=$(du -h "$SCRIPT_OUTPUT" | awk '{print $1}')
                LINES=$(wc -l < "$SCRIPT_OUTPUT")
                echo "    ✅ Success - $LINES lines, $OUTPUT_SIZE"
                FILE_BYTES=$(wc -c < "$SCRIPT_OUTPUT" 2>/dev/null | tr -d '[:space:]')
                [[ "$FILE_BYTES" =~ ^[0-9]+$ ]] || FILE_BYTES=0
                TOTAL_ANALYSIS_SIZE=$((TOTAL_ANALYSIS_SIZE + FILE_BYTES))
                
                {
                    echo "---"
                    echo "Script: $SCRIPT_NAME"
                    echo "Status: ✅ Success"
                    echo "Output Lines: $LINES"
                    echo "Output File: $SCRIPT_OUTPUT"
                    echo "---"
                    echo ""
                } >> "$BUNDLE_REPORT"
            else
                ((SCRIPTS_FAILED++))
                echo "    ❌ Failed"
                
                {
                    echo "---"
                    echo "Script: $SCRIPT_NAME"
                    echo "Status: ❌ Failed"
                    echo "---"
                    echo ""
                } >> "$BUNDLE_REPORT"
            fi
        done
    fi

    # Generate bundle-level summary
    echo "" >> "$BUNDLE_REPORT"
    echo "════════════════════════════════════════════════════════════" >> "$BUNDLE_REPORT"
    echo "Generated Files:" >> "$BUNDLE_REPORT"
    ls -1 "$BUNDLE_OUTPUT_DIR"/*.txt 2>/dev/null | xargs -I {} basename {} | nl >> "$BUNDLE_REPORT"
    
    echo ""
}

# Process top-level bundle directories
for BUNDLE_DIR in "$TICKET_DIR"/*/; do
    [[ ! -d "$BUNDLE_DIR" ]] && continue

    BUNDLE_NAME=$(basename "$BUNDLE_DIR")

    [[ "$BUNDLE_NAME" == "generated" ]] && continue
    [[ "$BUNDLE_NAME" == "metric_dashboards" ]] && continue
    [[ "$BUNDLE_NAME" == "skill_based" ]] && continue
    [[ "$BUNDLE_NAME" == "bundle_reports" ]] && continue
    [[ "$BUNDLE_NAME" == "remote_files" ]] && continue
    [[ "$BUNDLE_NAME" =~ ^\. ]] && continue

    VAR_LOG_DIR=""
    if [[ -d "$BUNDLE_DIR/var/log" ]]; then
        VAR_LOG_DIR="$BUNDLE_DIR/var/log"
    elif [[ -d "$BUNDLE_DIR/host/var/log" ]]; then
        VAR_LOG_DIR="$BUNDLE_DIR/host/var/log"
    fi

    [[ -z "$VAR_LOG_DIR" && ! -f "$BUNDLE_DIR/infoblox.log" ]] && continue
    process_bundle_dir "$BUNDLE_DIR" "$BUNDLE_NAME" "$VAR_LOG_DIR"
done

# Process extracted bundles under remote_files recursively
while IFS= read -r VAR_LOG_DIR; do
    [[ -z "$VAR_LOG_DIR" ]] && continue

    if [[ "$VAR_LOG_DIR" == */host/var/log ]]; then
        BUNDLE_DIR="$(dirname "$(dirname "$(dirname "$VAR_LOG_DIR")")")"
    else
        BUNDLE_DIR="$(dirname "$(dirname "$VAR_LOG_DIR")")"
    fi

    BUNDLE_NAME="${BUNDLE_DIR#$TICKET_DIR/remote_files/}"
    BUNDLE_NAME="${BUNDLE_NAME%/}"
    BUNDLE_NAME="${BUNDLE_NAME//\//__}"

    process_bundle_dir "$BUNDLE_DIR" "$BUNDLE_NAME" "$VAR_LOG_DIR"
done < <(find "$TICKET_DIR/remote_files" -type d \( -path '*/var/log' -o -path '*/host/var/log' \) 2>/dev/null | sort)

# Generate overall summary
{
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "OVERALL EXECUTION SUMMARY"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Total Bundles Processed: $BUNDLES_PROCESSED"
    echo "Total Scripts Run: $SCRIPTS_RUN"
    echo "Scripts Failed: $SCRIPTS_FAILED"
    echo "Scripts Succeeded: $((SCRIPTS_RUN - SCRIPTS_FAILED))"
    echo "Total Analysis Size: $(numfmt --to=iec-i --suffix=B $TOTAL_ANALYSIS_SIZE 2>/dev/null || echo $TOTAL_ANALYSIS_SIZE bytes)"
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "Output Location: $BUNDLE_ANALYSIS_DIR"
    echo "════════════════════════════════════════════════════════════"
} >> "$SUMMARY_FILE"

# Display summary
cat "$SUMMARY_FILE"

echo ""
echo "✅ Bundle script analysis complete!"
echo ""
echo "📊 Results Summary:"
echo "   📁 Output Directory: $BUNDLE_ANALYSIS_DIR"
echo "   📄 Summary Report: $SUMMARY_FILE"
echo "   🔍 Bundles Processed: $BUNDLES_PROCESSED"
echo "   ⚙️  Scripts Run: $SCRIPTS_RUN"
echo "   ✅ Succeeded: $((SCRIPTS_RUN - SCRIPTS_FAILED))"
echo "   ❌ Failed: $SCRIPTS_FAILED"
echo ""
echo "To view results:"
echo "   ls -la $BUNDLE_ANALYSIS_DIR"
echo "   cat $SUMMARY_FILE"
echo ""

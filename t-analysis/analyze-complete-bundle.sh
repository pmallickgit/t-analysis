#!/bin/bash
# Master Script: Complete Bundle Analysis Workflow
# Usage: ./analyze-complete-bundle.sh <TICKET_ID> [--skip-extraction]

TICKET_ID="${1}"
SKIP_EXTRACTION="${2:-}"

if [[ -z "$TICKET_ID" ]]; then
    echo "❌ Error: Ticket ID required"
    echo "Usage: bash analyze-complete-bundle.sh NIOSSPT-XXXXX [--skip-extraction]"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set up directories
if [[ -d "$HOME/analysis_support_tickets/$TICKET_ID" ]]; then
    TICKET_DIR="$HOME/analysis_support_tickets/$TICKET_ID"
else
    TICKET_DIR="$(pwd)"
fi

MASTER_LOG="${TICKET_DIR}/analysis_workflow.log"

# Initialize logging
{
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     MASTER BUNDLE ANALYSIS WORKFLOW                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Ticket ID: $TICKET_ID"
    echo "Ticket Directory: $TICKET_DIR"
    echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
} | tee "$MASTER_LOG"

# Step 1: Extract bundle files (unless skipped)
if [[ "$SKIP_EXTRACTION" != "--skip-extraction" ]]; then
    {
        echo "════════════════════════════════════════════════════════════"
        echo "STEP 1: Extracting Support Bundle Files"
        echo "════════════════════════════════════════════════════════════"
        echo ""
    } | tee -a "$MASTER_LOG"
    
    if [[ -f "$SCRIPT_DIR/extract-bundle-errors.sh" ]]; then
        bash "$SCRIPT_DIR/extract-bundle-errors.sh" "$TICKET_ID" 2>&1 | tee -a "$MASTER_LOG"
        EXTRACT_STATUS=${PIPESTATUS[0]}
    else
        {
            echo "⚠️  extract-bundle-errors.sh not found - skipping extraction"
            echo "   Looking in: $SCRIPT_DIR"
        } | tee -a "$MASTER_LOG"
        EXTRACT_STATUS=0
    fi
    
    {
        echo ""
        echo "✅ Extraction Complete (Status: $EXTRACT_STATUS)"
        echo ""
    } | tee -a "$MASTER_LOG"
else
    EXTRACT_STATUS=0
    {
        echo "════════════════════════════════════════════════════════════"
        echo "STEP 1: Skipped (--skip-extraction)"
        echo "════════════════════════════════════════════════════════════"
        echo ""
    } | tee -a "$MASTER_LOG"
fi

# Step 2: Run bundle scripts
{
    echo "════════════════════════════════════════════════════════════"
    echo "STEP 2: Running Scripts from Extracted Bundles"
    echo "════════════════════════════════════════════════════════════"
    echo ""
} | tee -a "$MASTER_LOG"

if [[ -f "$SCRIPT_DIR/run-bundle-scripts.sh" ]]; then
    bash "$SCRIPT_DIR/run-bundle-scripts.sh" "$TICKET_ID" 2>&1 | tee -a "$MASTER_LOG"
    SCRIPT_STATUS=${PIPESTATUS[0]}
else
    {
        echo "❌ Error: run-bundle-scripts.sh not found"
        echo "   Looking in: $SCRIPT_DIR"
    } | tee -a "$MASTER_LOG"
    SCRIPT_STATUS=1
fi

{
    echo ""
    echo "✅ Script Execution Complete (Status: $SCRIPT_STATUS)"
    echo ""
} | tee -a "$MASTER_LOG"

# Step 3: Generate per-bundle dashboards
{
    echo "════════════════════════════════════════════════════════════"
    echo "STEP 3: Generating Per-Bundle Dashboards"
    echo "════════════════════════════════════════════════════════════"
    echo ""
} | tee -a "$MASTER_LOG"

if [[ -f "$REPO_ROOT/run-all-bundle-dashboards.sh" ]]; then
    bash "$REPO_ROOT/run-all-bundle-dashboards.sh" "$TICKET_ID" 2>&1 | tee -a "$MASTER_LOG"
    DASHBOARD_STATUS=${PIPESTATUS[0]}
else
    {
        echo "❌ Error: run-all-bundle-dashboards.sh not found"
        echo "   Looking in: $REPO_ROOT"
    } | tee -a "$MASTER_LOG"
    DASHBOARD_STATUS=1
fi

{
    echo ""
    echo "✅ Dashboard Generation Complete (Status: $DASHBOARD_STATUS)"
    echo ""
} | tee -a "$MASTER_LOG"

# Step 4: Generate comprehensive analysis report
{
    echo "════════════════════════════════════════════════════════════"
    echo "STEP 4: Generating Comprehensive Analysis Report"
    echo "════════════════════════════════════════════════════════════"
    echo ""
} | tee -a "$MASTER_LOG"

if [[ -f "$SCRIPT_DIR/generate-bundle-analysis-report.sh" ]]; then
    bash "$SCRIPT_DIR/generate-bundle-analysis-report.sh" "$TICKET_ID" 2>&1 | tee -a "$MASTER_LOG"
    REPORT_STATUS=${PIPESTATUS[0]}
else
    {
        echo "❌ Error: generate-bundle-analysis-report.sh not found"
        echo "   Looking in: $SCRIPT_DIR"
    } | tee -a "$MASTER_LOG"
    REPORT_STATUS=1
fi

{
    echo ""
    echo "✅ Report Generation Complete (Status: $REPORT_STATUS)"
    echo ""
} | tee -a "$MASTER_LOG"

# Step 4: Generate summary
{
    echo "════════════════════════════════════════════════════════════"
    echo "WORKFLOW COMPLETE - SUMMARY"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Ticket: $TICKET_ID"
    echo "Analysis Directory: $TICKET_DIR"
    echo "Completion Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "Step Results:"
    echo "  ✓ Step 1 (Extraction): Status $EXTRACT_STATUS"
    echo "  ✓ Step 2 (Run Scripts): Status $SCRIPT_STATUS"
    echo "  ✓ Step 3 (Dashboards): Status $DASHBOARD_STATUS"
    echo "  ✓ Step 4 (Generate Report): Status $REPORT_STATUS"
    echo ""
} | tee -a "$MASTER_LOG"

# Check for output files
GENERATED_DIR="${TICKET_DIR}/generated"

{
    echo "Generated Files:"
    echo ""
    
    echo "  📊 Bundle Analysis:"
    [[ -d "$GENERATED_DIR/bundle_script_analysis" ]] && {
        echo "     ✓ Directory: $GENERATED_DIR/bundle_script_analysis"
        echo "     ✓ Bundles: $(find "$GENERATED_DIR/bundle_script_analysis" -mindepth 1 -maxdepth 1 -type d | wc -l)"
        echo "     ✓ Reports: $(find "$GENERATED_DIR/bundle_script_analysis" -name 'analysis_report.txt' | wc -l)"
    } || echo "     ✗ Not found"

    echo ""
    echo "  📈 Dashboards:"
    [[ -d "$TICKET_DIR/metric_dashboards" ]] && {
        echo "     ✓ Directory: $TICKET_DIR/metric_dashboards"
        echo "     ✓ Bundle Dashboards: $(find "$TICKET_DIR/metric_dashboards" -mindepth 1 -maxdepth 1 -type d | wc -l)"
        [[ -f "$TICKET_DIR/metric_dashboards/index.html" ]] && echo "     ✓ Index: index.html"
    } || echo "     ✗ Not found"
    
    echo ""
    echo "  📄 Reports:"
    [[ -f "$GENERATED_DIR/bundle_scripts_summary.txt" ]] && {
        echo "     ✓ Summary: bundle_scripts_summary.txt"
    }
    [[ -f "$GENERATED_DIR/comprehensive_bundle_analysis.html" ]] && {
        echo "     ✓ HTML Report: comprehensive_bundle_analysis.html"
    }
    [[ -f "$MASTER_LOG" ]] && {
        echo "     ✓ Workflow Log: analysis_workflow.log"
    }
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "NEXT STEPS:"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "1. View the comprehensive HTML report:"
    echo "   open \"$GENERATED_DIR/comprehensive_bundle_analysis.html\""
    echo ""
    echo "2. View the dashboard index:"
    echo "   open \"$TICKET_DIR/metric_dashboards/index.html\""
    echo ""
    echo "3. Check the summary:"
    echo "   cat \"$GENERATED_DIR/bundle_scripts_summary.txt\""
    echo ""
    echo "4. View workflow log:"
    echo "   cat \"$MASTER_LOG\""
    echo ""
    echo "5. List all bundle analysis results:"
    echo "   ls -la \"$GENERATED_DIR/bundle_script_analysis/\""
    echo ""
} | tee -a "$MASTER_LOG"

echo ""
echo "✅ Analysis workflow complete! Check the generated files above."
echo ""

# Determine overall status
if [[ $EXTRACT_STATUS -eq 0 ]] && [[ $SCRIPT_STATUS -eq 0 ]] && [[ $DASHBOARD_STATUS -eq 0 ]] && [[ $REPORT_STATUS -eq 0 ]]; then
    EXIT_CODE=0
    echo "Status: SUCCESS ✅"
else
    EXIT_CODE=1
    echo "Status: PARTIAL/FAILED ⚠️"
fi

exit $EXIT_CODE

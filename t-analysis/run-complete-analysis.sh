#!/bin/bash

################################################################################
# NIOSSPT Complete Analysis Automation Script
# 
# Usage:
#   bash run-complete-analysis.sh "NIOSSPT-XXXXX"
#   bash run-complete-analysis.sh "https://infoblox.atlassian.net/browse/NIOSSPT-XXXXX"
#   bash run-complete-analysis.sh "NIOSSPT-XXXXX" --skip-download  # Skip step 3 if bundles exist
#   bash run-complete-analysis.sh "NIOSSPT-XXXXX" --verbose        # Show detailed output
#
# This script orchestrates all 7 analysis steps:
#   1. Read Jira Ticket
#   2. Summarize Problem Description
#   3. Download Support Bundles
#   4. Generate Comprehensive Dashboard
#   5. Generate Problem-Statement Analysis
#   6. Generate Per-Bundle Reports
#   7. Generate Final RCA Report
#
# Output: Complete RCA report at $TICKET_DIR/COMPREHENSIVE_RCA_REPORT.md
################################################################################

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TA_DIR="${SCRIPT_DIR}"
SKILLS_DIR="$(cd "${TA_DIR}/.." && pwd)"
TICKET_BASE_DIR="${HOME}/analysis_support_tickets"

VERBOSE=false
SKIP_DOWNLOAD=false
SKIP_STEPS=""
RESUME_FROM_STEP3=false

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║ $1"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_step() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 STEP $1: $2"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ ERROR: $1"
    exit 1
}

print_info() {
    if [ "$VERBOSE" = true ]; then
        echo "ℹ️  $1"
    fi
}

cleanup_dir() {
    local dir_path=$1
    if [ -d "$dir_path" ]; then
        chmod -R u+rwX "$dir_path" 2>/dev/null || true
        rm -rf "$dir_path"
    fi
}

validate_file() {
    local file=$1
    local desc=$2
    if [ ! -f "$file" ]; then
        print_error "$desc not found: $file"
    fi
    print_success "$desc present: $(du -h "$file" | cut -f1)"
}

prepare_ticket_directory() {
    local ticket_dir=$1
    local remote_dir="$ticket_dir/remote_files"

    mkdir -p "$remote_dir"
    mkdir -p "$ticket_dir/generated"

    # Always rebuild extracted views from the latest synced bundle content.
    cleanup_dir "$remote_dir/BUNDLE_EXTRACT"

    print_success "Ticket directory prepared (existing artifacts preserved, extraction cache reset)"
}

extract_bundle_archives() {
    local remote_dir=$1
    local extract_root="$remote_dir/BUNDLE_EXTRACT"
    local archives_file
    local archive
    local base_name
    local target_dir
    local extracted_count=0
    local extracted_with_warnings=0
    local failed_count=0
    local nested_extracted=0
    local nested_with_warnings=0
    local nested_failed=0
    local nested_target
    local extracted_files=0
    local tar_err

    extract_archive_to_dir() {
        local archive_path="$1"
        local output_dir="$2"

        case "$archive_path" in
            *.tar.gz|*.tgz)
                tar -xzf "$archive_path" -C "$output_dir"
                ;;
            *.tar)
                tar -xf "$archive_path" -C "$output_dir"
                ;;
            *)
                return 1
                ;;
        esac
    }

    # Always rebuild extraction root so only current bundle-specific directories exist.
    cleanup_dir "$extract_root"
    mkdir -p "$extract_root"

    archives_file=$(mktemp)
    find "$remote_dir" -maxdepth 1 -type f \
        \( -name "sb_*.tar.gz" -o -name "sb_*.tgz" -o -name "sb_*.tar" \) \
        ! -name ".*" | sort > "$archives_file"

    while IFS= read -r archive; do
        [[ -z "$archive" ]] && continue

        base_name=$(basename "$archive")
        base_name=${base_name%.tar.gz}
        base_name=${base_name%.tgz}
        base_name=${base_name%.tar}
        target_dir="$extract_root/$base_name"

        cleanup_dir "$target_dir"
        mkdir -p "$target_dir"
        tar_err=$(mktemp)

        if extract_archive_to_dir "$archive" "$target_dir" > /dev/null 2>"$tar_err"; then
            extracted_count=$((extracted_count + 1))
            print_info "Extracted: $(basename "$archive") -> $target_dir"
        else
            extracted_files=$(find "$target_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
            if [ "$extracted_files" -gt 0 ]; then
                extracted_with_warnings=$((extracted_with_warnings + 1))
                echo "⚠️  Extracted with warnings: $archive ($extracted_files files)"
                print_info "tar warnings (first lines): $(sed -n '1,2p' "$tar_err" | tr '\n' ' ')"
            else
                failed_count=$((failed_count + 1))
                echo "⚠️  Failed to extract: $archive"
                cleanup_dir "$target_dir"
            fi
        fi

        rm -f "$tar_err"
    done < "$archives_file"

    rm -f "$archives_file"

    # Treat warning-only extractions as successful when files were produced.
    if [ $((extracted_count + extracted_with_warnings)) -eq 0 ]; then
        print_error "No support bundle archives were extracted from $remote_dir"
    fi

    if [ "$failed_count" -gt 0 ]; then
        echo "⚠️  Extraction completed with $failed_count failures"
    fi

    if [ "$extracted_with_warnings" -gt 0 ]; then
        echo "⚠️  Top-level extraction had warnings for $extracted_with_warnings archives"
    fi

    # Extract only nested active/passive support-bundle archives.
    while IFS= read -r archive; do
        [[ -z "$archive" ]] && continue

        base_name=$(basename "$archive")
        base_name=${base_name%.tar.gz}
        base_name=${base_name%.tgz}
        base_name=${base_name%.tar}
        nested_target="$(dirname "$archive")/$base_name"

        cleanup_dir "$nested_target"
        mkdir -p "$nested_target"
        tar_err=$(mktemp)

        if extract_archive_to_dir "$archive" "$nested_target" > /dev/null 2>"$tar_err"; then
            nested_extracted=$((nested_extracted + 1))
            print_info "Nested extract: $(basename "$archive") -> $nested_target"
        else
            extracted_files=$(find "$nested_target" -type f 2>/dev/null | wc -l | tr -d ' ')
            if [ "$extracted_files" -gt 0 ]; then
                nested_with_warnings=$((nested_with_warnings + 1))
                echo "⚠️  Nested extracted with warnings: $archive ($extracted_files files)"
                print_info "nested tar warnings (first lines): $(sed -n '1,2p' "$tar_err" | tr '\n' ' ')"
            else
                nested_failed=$((nested_failed + 1))
                echo "⚠️  Failed nested extract: $archive"
                cleanup_dir "$nested_target"
            fi
        fi

        rm -f "$tar_err"
    done < <(find "$extract_root" -type f \
        \( -iname "active_node*.tar*" \
        -o -iname "passive_node*.tar*" \
        -o -iname "*active*supportbundle*.tar*" \
        -o -iname "*passive*supportbundle*.tar*" \) 2>/dev/null | sort)

    if [ "$nested_failed" -gt 0 ]; then
        echo "⚠️  Nested extraction completed with $nested_failed failures"
    fi

    if [ "$nested_with_warnings" -gt 0 ]; then
        echo "⚠️  Nested extraction had warnings for $nested_with_warnings archives"
    fi

    infoblox_logs=$(find "$extract_root" -type f -name "infoblox.log" 2>/dev/null | wc -l)
    active_dirs=$(find "$extract_root" -type d -name "active_node_supportBundle" 2>/dev/null | wc -l)
    passive_dirs=$(find "$extract_root" -type d -name "passive_node_supportBundle" 2>/dev/null | wc -l)
    print_success "Bundle extraction complete ($extracted_count top-level archives, $extracted_with_warnings with warnings, $nested_extracted nested archives, $nested_with_warnings nested with warnings, $infoblox_logs infoblox.log files, active dirs: $active_dirs, passive dirs: $passive_dirs)"
}

# ============================================================================
# Parse Arguments
# ============================================================================

parse_ticket_id() {
    local input=$1
    
    # If it's a URL, extract ticket ID
    if [[ $input =~ browse/([A-Z]+\-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    # If it looks like a ticket ID already
    elif [[ $input =~ ^[A-Z]+-[0-9]+$ ]]; then
        echo "$input"
    else
        print_error "Invalid ticket format: $input (expected NIOSSPT-XXXXX or Jira URL)"
    fi
}

# ============================================================================
# Main Script
# ============================================================================

# Parse command line arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 TICKET_ID [--skip-download] [--verbose]"
    echo ""
    echo "Examples:"
    echo "  $0 NIOSSPT-XXXXX"
    echo "  $0 'https://infoblox.atlassian.net/browse/NIOSSPT-XXXXX'"
    echo "  $0 NIOSSPT-XXXXX --verbose"
    echo ""
    exit 1
fi

INPUT_TICKET="$1"
shift || true

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-download)
            SKIP_DOWNLOAD=true
            ;;
        --verbose)
            VERBOSE=true
            ;;
        .)
            # Ignore trailing dot argument commonly passed as working-directory shorthand.
            ;;
        *)
            print_error "Unknown argument: $1"
            ;;
    esac
    shift || true
done

# Extract ticket ID from input
TICKET_ID=$(parse_ticket_id "$INPUT_TICKET")
TICKET_DIR="$TICKET_BASE_DIR/$TICKET_ID"

if [ -d "$TICKET_DIR" ] && [ -n "$(find "$TICKET_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
    RESUME_FROM_STEP3=true
fi

print_header "NIOSSPT COMPLETE ANALYSIS WORKFLOW - $TICKET_ID"

echo "Configuration:"
echo "  Ticket ID:     $TICKET_ID"
echo "  Ticket Dir:    $TICKET_DIR"
echo "  Skills Dir:    $SKILLS_DIR"
echo "  T-Analysis:    $TA_DIR"
echo "  Verbose:       $VERBOSE"
echo "  Skip Download: $SKIP_DOWNLOAD"
echo "  Resume 3-7:    $RESUME_FROM_STEP3"
echo ""

# Create ticket directory if needed
mkdir -p "$TICKET_DIR"
print_success "Ticket directory ready: $TICKET_DIR"

# Prepare directory without deleting prior outputs.
prepare_ticket_directory "$TICKET_DIR"

# ============================================================================
# STEP 1: Read Jira Ticket
# ============================================================================

print_step "1" "Read Jira Ticket Data"
if [ "$RESUME_FROM_STEP3" = true ] && [ -s "$TICKET_DIR/01_jira_ticket_raw.txt" ]; then
    print_info "Existing ticket directory detected; reusing Step 1 output"
    validate_file "$TICKET_DIR/01_jira_ticket_raw.txt" "Jira Ticket Raw"
else
    print_info "Fetching ticket $TICKET_ID from Jira..."
    if bash "$TA_DIR/jira_access.sh" "$TICKET_ID" | tee "$TICKET_DIR/01_jira_ticket_raw.txt" > /dev/null 2>&1; then
        validate_file "$TICKET_DIR/01_jira_ticket_raw.txt" "Jira Ticket Raw"
    else
        print_error "Failed to fetch Jira ticket. Check credentials: ~/.jira-credentials"
    fi
fi

# ============================================================================
# STEP 2: Summarize Problem Description
# ============================================================================

print_step "2" "Summarize Problem Description"
if [ "$RESUME_FROM_STEP3" = true ] && [ -s "$TICKET_DIR/02_jira_problem_summary.md" ]; then
    print_info "Existing ticket directory detected; reusing Step 2 output"
    validate_file "$TICKET_DIR/02_jira_problem_summary.md" "Problem Summary"
else
    print_info "Extracting problem summary from Jira ticket..."

    {
        echo "# $TICKET_ID - Problem Summary"
        echo ""
        echo "## Ticket Summary"
        sed -n 's/^Summary: //p' "$TICKET_DIR/01_jira_ticket_raw.txt"
        echo ""
        echo "## Ticket Description"
        sed -n 's/^Description: //p' "$TICKET_DIR/01_jira_ticket_raw.txt"
        echo ""
        echo "## Required Details Extracted"
        echo "- Ticket ID: $TICKET_ID"
        echo "- Generated At: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "- Jira URL: https://infoblox.atlassian.net/browse/$TICKET_ID"
    } > "$TICKET_DIR/02_jira_problem_summary.md"

    validate_file "$TICKET_DIR/02_jira_problem_summary.md" "Problem Summary"
fi

# ============================================================================
# STEP 3: Download Support Bundles
# ============================================================================

print_step "3" "Download Support Bundles"

if [ "$SKIP_DOWNLOAD" = true ] && [ -d "$TICKET_DIR/remote_files" ]; then
    bundle_count=$(find "$TICKET_DIR/remote_files" -maxdepth 1 -type f \
        \( -name "sb_*.tar" -o -name "sb_*.tar.gz" -o -name "sb_*.tgz" \) \
        ! -name ".*" 2>/dev/null | wc -l)
    if [ "$bundle_count" -gt 0 ]; then
        print_info "Skipping download (bundles already present)"
        echo "Found $bundle_count existing bundles"
    else
        print_error "--skip-download requested but no .tar* bundles found in $TICKET_DIR/remote_files"
    fi
else
    print_info "Extracting remote path from Jira..."
    REMOTE_SERVER="pmallick@sup-xfer-01.inca.infoblox.com"
    REMOTE_PATH=$(bash "$TA_DIR/jira_extract_case_path.sh" "$TICKET_ID" 2>/dev/null || echo "")
    
    if [ -z "$REMOTE_PATH" ]; then
        print_error "Failed to extract remote bundle path from ticket"
    fi
    
    print_info "Remote path: $REMOTE_PATH"
    LOCAL_DIR="$TICKET_DIR/remote_files"
    
    print_info "Starting incremental bundle sync (this may take several minutes)..."
    if bash "$TA_DIR/support_bundle_download.sh" "$REMOTE_SERVER" "$REMOTE_PATH" "$LOCAL_DIR" \
        | tee "$TICKET_DIR/03_download.log" > /dev/null 2>&1; then
        print_success "Bundle sync completed"
    else
        print_error "Bundle download failed. Check network and SSH access."
    fi
fi

# Create bundle inventory
find "$TICKET_DIR/remote_files" -maxdepth 1 -type f \( -name "sb_*.tar" -o -name "sb_*.tar.gz" -o -name "sb_*.tgz" \) \
    ! -name ".*" \
    | sort > "$TICKET_DIR/03_support_bundle_inventory.txt" 2>/dev/null || true

bundle_count=$(wc -l < "$TICKET_DIR/03_support_bundle_inventory.txt" 2>/dev/null || echo "0")
print_success "Bundle inventory created ($bundle_count bundles)"

print_info "Extracting support bundle archives for downstream analysis..."
extract_bundle_archives "$TICKET_DIR/remote_files"

# ============================================================================
# STEP 4: Generate Comprehensive Dashboard
# ============================================================================

print_step "4" "Generate Comprehensive Dashboard from All Bundles"
print_info "Generating metric dashboards (this takes 2-5 minutes)..."

if cd "$TA_DIR" && bash ./run-all-bundle-dashboards.sh "$TICKET_ID" . \
    | tee "$TICKET_DIR/04_comprehensive_dashboard_generation.log" > /dev/null 2>&1; then
    validate_file "$TICKET_DIR/COMPLETE_ANALYSIS_DASHBOARD.html" "Dashboard HTML"
    
    html_count=$(find "$TICKET_DIR/metric_dashboards" -name "*.html" 2>/dev/null | wc -l)
    print_success "Dashboard generation complete ($html_count metric files)"
else
    print_error "Dashboard generation failed"
fi

# ============================================================================
# STEP 5: Generate Problem-Statement-Based Analysis
# ============================================================================

print_step "5" "Generate Problem-Statement Analysis Per Bundle"
print_info "Extracting errors/warnings aligned with problem statement..."

if bash "$TA_DIR/extract-bundle-errors.sh" "$TICKET_ID" | tee "$TICKET_DIR/05_error_extraction.log" > /dev/null 2>&1; then
    error_count=$(find "$TICKET_DIR/generated" -name "*_errors_warnings.txt" 2>/dev/null | wc -l)
    print_success "Error extraction complete ($error_count extraction files)"
else
    print_error "Error extraction failed"
fi

print_info "Generating problem-statement correlation report..."
if python3 - "$TICKET_DIR" > "$TICKET_DIR/05_problem_statement_correlation_generation.log" 2>&1 << 'PY'
import os
import re
import glob
from collections import Counter
import sys

if len(sys.argv) < 2:
    raise SystemExit("ticket directory argument missing")

ticket_dir = os.path.expanduser(sys.argv[1])
summary_path = os.path.join(ticket_dir, "02_jira_problem_summary.md")
errors_glob = os.path.join(ticket_dir, "generated", "*_errors_warnings.txt")
out_path = os.path.join(ticket_dir, "05_problem_statement_bundle_analysis.md")

text = ""
if os.path.exists(summary_path):
    with open(summary_path, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read().lower()

stop = {
    "the", "and", "for", "with", "from", "that", "this", "have", "has", "had", "was", "were", "are", "is",
    "a", "an", "of", "to", "in", "on", "at", "by", "as", "or", "be", "it", "its", "into", "their", "they",
    "issue", "ticket", "summary", "description", "details", "required", "generated", "analysis", "report"
}

words = re.findall(r"[a-z0-9_]{4,}", text)
keywords = [w for w in words if w not in stop and not w.isdigit()]

freq = Counter(keywords)
selected = [k for k, _ in freq.most_common(20)]
if not selected:
    selected = ["error", "timeout", "dns", "memory", "fail"]

lines = []
lines.append("# Problem Statement Correlation by Bundle")
lines.append("")
lines.append("## Keywords Derived from Jira Summary/Description")
lines.append("")
lines.append(", ".join(selected))
lines.append("")
lines.append("## Bundle-wise Correlation")
lines.append("")

files = sorted(glob.glob(errors_glob))
if not files:
    lines.append("No generated/*_errors_warnings.txt files found.")
else:
    for fp in files:
        name = os.path.basename(fp).replace("_errors_warnings.txt", "")
        with open(fp, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read().lower()
        hit_counts = {k: content.count(k) for k in selected}
        total_hits = sum(hit_counts.values())
        top_hits = sorted(hit_counts.items(), key=lambda x: x[1], reverse=True)[:5]

        lines.append(f"### {name}")
        lines.append(f"- Total keyword hits: {total_hits}")
        lines.append("- Top matched keywords:")
        for k, v in top_hits:
            lines.append(f"  - {k}: {v}")
        lines.append("")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(out_path)
PY
then
    validate_file "$TICKET_DIR/05_problem_statement_bundle_analysis.md" "Problem Statement Analysis"
else
    print_error "Problem-statement correlation generation failed"
fi

# ============================================================================
# STEP 6: Generate Per-Support-Bundle Reports
# ============================================================================

print_step "6" "Generate Per-Support-Bundle Analysis Reports"
print_info "Running bundle-specific analysis scripts..."

if bash "$TA_DIR/run-bundle-scripts.sh" "$TICKET_ID" --skip-extraction \
    | tee "$TICKET_DIR/06_per_bundle_script_runs.log" > /dev/null 2>&1; then
    print_success "Per-bundle script execution complete"
else
    print_error "Per-bundle script execution failed"
fi

print_info "Generating bundle analysis report..."
if bash "$TA_DIR/generate-bundle-analysis-report.sh" "$TICKET_ID" \
    | tee "$TICKET_DIR/06_per_bundle_report_generation.log" > /dev/null 2>&1; then
    validate_file "$TICKET_DIR/generated/comprehensive_bundle_analysis.html" "Bundle Analysis HTML"
    print_success "Bundle analysis report generation complete"
else
    print_error "Bundle analysis report generation failed"
fi

# ============================================================================
# STEP 7: Generate Final RCA Report
# ============================================================================

print_step "7" "Generate Final RCA Report Set"
print_info "Generating comprehensive RCA analysis..."

if cd "$TICKET_DIR" && python3 "$TA_DIR/generate-final-rca.py" . \
    | tee "$TICKET_DIR/07_final_rca_generation.log" > /dev/null 2>&1; then
    print_success "RCA report generation complete"
else
    print_error "RCA report generation failed"
fi

# Validate all RCA outputs
for rca_file in EXECUTIVE_SUMMARY.md COMPREHENSIVE_RCA_REPORT.md ERROR_TO_CODE_RCA_SUMMARY.md FIX_IMPLEMENTATION_GUIDE.md; do
    validate_file "$TICKET_DIR/$rca_file" "RCA: $rca_file"
done

# ============================================================================
# Final Summary
# ============================================================================

print_header "✅ ANALYSIS COMPLETE - ALL 7 STEPS SUCCESSFUL"

echo "📊 DELIVERABLES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 Ticket Directory: $TICKET_DIR"
echo ""
echo "Primary Reports:"
ls -lh "$TICKET_DIR"/EXECUTIVE_SUMMARY.md "$TICKET_DIR"/COMPREHENSIVE_RCA_REPORT.md 2>/dev/null | awk '{print "   " $9 " (" $5 ")"}'
echo ""
echo "Supporting Analysis:"
echo "   • ERROR_TO_CODE_RCA_SUMMARY.md - Error categorization"
echo "   • FIX_IMPLEMENTATION_GUIDE.md - Remediation steps"
echo "   • COMPLETE_ANALYSIS_DASHBOARD.html - Metric dashboards"
echo "   • generated/comprehensive_bundle_analysis.html - Bundle reports"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 NEXT STEPS:"
echo "   1. Review: cat $TICKET_DIR/COMPREHENSIVE_RCA_REPORT.md"
echo "   2. Dashboard: open $TICKET_DIR/COMPLETE_ANALYSIS_DASHBOARD.html"
echo "   3. Implement: Follow $TICKET_DIR/FIX_IMPLEMENTATION_GUIDE.md"
echo ""
echo "✅ Workflow completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

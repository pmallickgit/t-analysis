#!/bin/bash

# Run all analysis scripts for each support bundle and generate comprehensive HTML report
# Usage: ./run-all-bundle-dashboards.sh TICKET-ID

if [[ -z "$1" ]]; then
    echo "Usage: $0 NIOSSPT-XXXXX"
    exit 1
fi

TICKET_ID="$1"
TICKET_DIR=~/analysis_support_tickets/${TICKET_ID}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
OUTPUT_BASE_DIR="${TICKET_DIR}/metric_dashboards"
ALT_OUTPUT_DIR="${TICKET_DIR}/metrics_dashboard"

PY_ENV_DIR="${PY_ENV_DIR:-$HOME/wenvs/dsenv}"
PY_ACTIVATE="${PY_ENV_DIR}/bin/activate"

if [[ ! -f "$PY_ACTIVATE" ]] && [[ -f "$HOME/Downloads/dsenv/bin/activate" ]]; then
    PY_ENV_DIR="$HOME/Downloads/dsenv"
    PY_ACTIVATE="${PY_ENV_DIR}/bin/activate"
fi

if [[ -f "$PY_ACTIVATE" ]]; then
    # shellcheck disable=SC1090
    source "$PY_ACTIVATE"
else
    echo "⚠️  Python environment not found: $PY_ACTIVATE"
    echo "    Continuing with system python/bash environment"
fi

apply_classic_theme_to_html() {
    local html_file="$1"
    [[ -f "$html_file" ]] || return 0

    python3 - "$html_file" <<'PYCLASSIC'
import sys

path = sys.argv[1]
marker = "/* classic-cern-theme-override */"
back_marker = "<!-- dashboard-back-button -->"
override = """
<style>
/* classic-cern-theme-override */
html, body {
    font-family: \"Times New Roman\", Times, serif !important;
    background: #ffffff !important;
    color: #000000 !important;
}
/* Force a uniform typeface across every element in generated pages */
*, *::before, *::after {
    font-family: \"Times New Roman\", Times, serif !important;
}
h1, h2, h3, h4, h5, h6 {
    color: #000000 !important;
}
a {
    color: #1f2937 !important;
    text-decoration: none !important;
}
a:visited {
    color: #1f2937 !important;
}
.dashboard,
.dashboard-card,
.cpu-table-card,
.summary-section,
.toc,
.stat-card {
    background: #ffffff !important;
    color: #000000 !important;
    border: 1px solid #000000 !important;
    box-shadow: none !important;
    border-radius: 0 !important;
}

.bundle-section {
    border: none !important;
    box-shadow: none !important;
}
</style>
""".strip()

back_button_css = """
<style>
/* dashboard-back-button */
.dashboard-back-btn {
    position: fixed;
    top: 12px;
    left: 12px;
    z-index: 9999;
    background: #ffffff;
    color: #1f2937;
    border: 1px solid #000000;
    padding: 6px 10px;
    text-decoration: none;
    font-family: "Times New Roman", Times, serif;
    font-size: 14px;
}
.dashboard-back-btn:hover {
    color: #111827;
    background: #f3f3f3;
}
</style>
""".strip()

back_button_html = '<a href="javascript:history.back()" class="dashboard-back-btn">< Back</a>'

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    content = f.read()

updated = content

if marker not in updated:
    if "</head>" in updated:
        updated = updated.replace("</head>", f"{override}\n</head>", 1)
    else:
        updated = f"{override}\n{updated}"

if back_marker not in updated:
    if "</head>" in updated and "/* dashboard-back-button */" not in updated:
        updated = updated.replace("</head>", f"{back_button_css}\n</head>", 1)

    back_block = f"{back_marker}\n{back_button_html}"
    if "<body>" in updated:
        updated = updated.replace("<body>", f"<body>\n    {back_block}", 1)
    elif "<body " in updated:
        idx = updated.find(">", updated.find("<body "))
        if idx != -1:
            updated = updated[:idx + 1] + "\n    " + back_block + updated[idx + 1:]

with open(path, "w", encoding="utf-8") as f:
    f.write(updated)
PYCLASSIC
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Dashboard Generation for ${TICKET_ID}                  "
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Scripts Directory: ${SCRIPTS_DIR}"
echo "Python Environment: ${PY_ENV_DIR}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_BASE_DIR}"

# Backward-compatible alias some workflows expect
if [[ ! -e "${ALT_OUTPUT_DIR}" ]]; then
    ln -s "${OUTPUT_BASE_DIR}" "${ALT_OUTPUT_DIR}" 2>/dev/null || true
fi

# Find all analyzable support bundle log directories.
# Prefer host/var/log when both host/var/log and var/log exist for the same bundle.
echo "🔍 Finding support bundles with analyzable logs..."
BUNDLE_LOGS=()
SEEN_BUNDLE_LOGS=""
while IFS= read -r logdir; do
    selected_logdir="$logdir"

    # Prefer host/var/log for a bundle when both host and non-host log dirs exist.
    if [[ "$selected_logdir" != */host/var/log ]]; then
        host_logdir="${selected_logdir%/var/log}/host/var/log"
        if [[ -d "$host_logdir" ]]; then
            selected_logdir="$host_logdir"
        fi
    fi

    if ! printf '%s\n' "$SEEN_BUNDLE_LOGS" | grep -Fxq "$selected_logdir"; then
        BUNDLE_LOGS+=("$selected_logdir")
        SEEN_BUNDLE_LOGS+="$selected_logdir"$'\n'
    fi
done < <(find "${TICKET_DIR}/remote_files" -type d -name "log" -path "*/var/log" 2>/dev/null)

echo "   Found ${#BUNDLE_LOGS[@]} support bundles to analyze"
echo ""

# Array to store bundle info for HTML report
declare -a BUNDLE_INFO

BUNDLE_NUM=1
for LOG_DIR in "${BUNDLE_LOGS[@]}"; do
    # Get bundle name from path
    BUNDLE_NAME=$(echo "$LOG_DIR" | sed 's|.*/remote_files/||' | sed 's|/var/log||' | sed 's|/host||')
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Bundle ${BUNDLE_NUM}: ${BUNDLE_NAME}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Log Directory: $LOG_DIR"
    
    # Create bundle-specific output directory
    BUNDLE_OUTPUT_DIR="${OUTPUT_BASE_DIR}/bundle_${BUNDLE_NUM}"
    mkdir -p "${BUNDLE_OUTPUT_DIR}"
    
    echo "   🔧 Running 15 analysis scripts..."
    
    # Run each script
    SCRIPTS=(
        "cpu_analysis.sh"
        "mem_analysis.sh"
        "disk_analysis.sh"
        "net_analysis.sh"
        "top_analysis.sh"
        "infoblox_analysis.sh"
        "bind_chr_analysis.sh"
        "vdca_chr_analysis.sh"
        "smaps_analysis.sh"
        "fpcpu_analsyis.sh"
        "fpmbuf_analysis.sh"
        "fpports_analysis.sh"
        "fprrstat_analysis.sh"
        "fptcpdcastat_analysis.sh"
        "fpdtob_analysis.sh"
    )
    TOTAL_SCRIPTS=${#SCRIPTS[@]}
    
    SCRIPT_COUNT=1
    for SCRIPT in "${SCRIPTS[@]}"; do
        SCRIPT_NAME="${SCRIPT%.sh}"
        SCRIPT_NAME="${SCRIPT_NAME//_analysis/}"
        SCRIPT_NAME="${SCRIPT_NAME//_analsyis/}"
        OUTPUT_FILE="${BUNDLE_OUTPUT_DIR}/${SCRIPT_NAME}.html"
        WORK_DIR="${BUNDLE_OUTPUT_DIR}/.work_${SCRIPT_NAME}"
        GENERATED_HTML=""
        
        if [ -f "${SCRIPTS_DIR}/$SCRIPT" ]; then
            echo "      [$SCRIPT_COUNT/$TOTAL_SCRIPTS] Running ${SCRIPT}..."

            rm -rf "$WORK_DIR"
            mkdir -p "$WORK_DIR"

            # Provide files from all relevant bundle locations so analyzers can
            # consume expected inputs (ptop, messages/syslog, infoblox.log, etc.).
            find "$LOG_DIR" -maxdepth 1 -type f -exec ln -sf {} "$WORK_DIR"/ \;

            # When host logs are selected, also include sibling var/log files
            # because some bundles keep syslog/messages only there.
            if [[ "$LOG_DIR" == */host/var/log ]]; then
                SIBLING_LOG_DIR="${LOG_DIR%/host/var/log}/var/log"
                if [[ -d "$SIBLING_LOG_DIR" ]]; then
                    find "$SIBLING_LOG_DIR" -maxdepth 1 -type f -exec ln -sf {} "$WORK_DIR"/ \;
                fi
            fi

            # Some scripts expect infoblox.log at bundle root.
            BUNDLE_ROOT="$LOG_DIR"
            BUNDLE_ROOT="${BUNDLE_ROOT%/host/var/log}"
            BUNDLE_ROOT="${BUNDLE_ROOT%/var/log}"
            if [[ -f "$BUNDLE_ROOT/infoblox.log" ]]; then
                ln -sf "$BUNDLE_ROOT/infoblox.log" "$WORK_DIR/"
            fi

            # Run analysis script where logs are available as local files
            (
                cd "$WORK_DIR" || exit 1
                bash "${SCRIPTS_DIR}/$SCRIPT" > /dev/null 2>&1
            )

            case "$SCRIPT" in
                cpu_analysis.sh) GENERATED_HTML="cpu_usage_dashboard.html" ;;
                mem_analysis.sh) GENERATED_HTML="mem_dashboard.html" ;;
                disk_analysis.sh) GENERATED_HTML="disk_usage_dashboard.html" ;;
                net_analysis.sh) GENERATED_HTML="net_usage_dashboard.html" ;;
                top_analysis.sh) GENERATED_HTML="top_processes_dashboard.html" ;;
                infoblox_analysis.sh) GENERATED_HTML="infoblox_dashboard.html" ;;
                bind_chr_analysis.sh) GENERATED_HTML="bind_chr_dashboard.html" ;;
                vdca_chr_analysis.sh) GENERATED_HTML="vdca_chr_dashboard.html" ;;
                smaps_analysis.sh) GENERATED_HTML="smaps_dashboard.html" ;;
                fpcpu_analsyis.sh) GENERATED_HTML="fpcpu_usage_dashboard.html" ;;
                fpmbuf_analysis.sh) GENERATED_HTML="fpmbuf_dashboard.html" ;;
                fpports_analysis.sh) GENERATED_HTML="port_usage_dashboard.html" ;;
                fprrstat_analysis.sh) GENERATED_HTML="fprrstat_dashboard.html" ;;
                fptcpdcastat_analysis.sh) GENERATED_HTML="fptcpdcastat_dashboard.html" ;;
                fpdtob_analysis.sh) GENERATED_HTML="fpdtob_dashboard.html" ;;
            esac

            if [[ -n "$GENERATED_HTML" ]] && [[ -f "$WORK_DIR/$GENERATED_HTML" ]]; then
                cp "$WORK_DIR/$GENERATED_HTML" "$OUTPUT_FILE"
            elif ls "$WORK_DIR"/*.html >/dev/null 2>&1; then
                # Fallback for scripts that change output names
                cp "$(ls -1 "$WORK_DIR"/*.html | head -n 1)" "$OUTPUT_FILE"
            fi

            if [ -f "$OUTPUT_FILE" ]; then
                # Some analyzers emit an HTML shell that explicitly says no data.
                # In that case treat it as missing so the summary dashboard greys it out.
                if grep -qiE "no data available|no data found|insufficient data|no matching data|no records found|empty dataset" "$OUTPUT_FILE"; then
                    rm -f "$OUTPUT_FILE"
                    echo "         ⚠️  Skipped (no data): ${SCRIPT_NAME}.html"
                else
                    apply_classic_theme_to_html "$OUTPUT_FILE"
                    echo "         ✅ Generated: ${SCRIPT_NAME}.html"
                fi
            else
                echo "         ⚠️  Skipped (no data): ${SCRIPT_NAME}.html"
            fi

            rm -rf "$WORK_DIR"
        else
            echo "         ⚠️  Script not found: $SCRIPT"
        fi
        SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
    done
    
    # Store bundle info for HTML report
    BUNDLE_INFO+=("${BUNDLE_NUM}|${BUNDLE_NAME}|bundle_${BUNDLE_NUM}")
    
    echo "   ✅ Bundle ${BUNDLE_NUM} complete!"
    echo ""
    
    BUNDLE_NUM=$((BUNDLE_NUM + 1))
done

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Generating Comprehensive HTML Report                   "
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Now generate the comprehensive HTML report
python3 - <<PYTHON_SCRIPT
import os
import glob
from datetime import datetime

ticket_id = "${TICKET_ID}"
ticket_dir = "${TICKET_DIR}"
output_dir = "${OUTPUT_BASE_DIR}"

# Read bundle info
bundle_data = """${BUNDLE_INFO[@]}""".split()

print("📝 Creating comprehensive HTML report...")

html_content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${TICKET_ID} - Comprehensive Analysis Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: "Times New Roman", Times, serif;
            background: #ffffff;
            padding: 20px;
            color: #000000;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
        }
        .header {
            background: #ffffff;
            border: 1px solid #000000;
            padding: 20px;
            margin-bottom: 30px;
            text-align: center;
        }
        .header h1 {
            color: #000000;
            font-size: 32px;
            margin-bottom: 10px;
        }
        .header .meta {
            color: #000000;
            font-size: 15px;
        }
        .toc {
            background: #ffffff;
            border: 1px solid #000000;
            padding: 20px;
            margin-bottom: 30px;
        }
        .toc h2 {
            color: #000000;
            margin-bottom: 20px;
            border-bottom: 1px solid #000000;
            padding-bottom: 10px;
        }
        .toc ul {
            list-style: none;
            display: flex;
            flex-wrap: wrap;
            gap: 18px;
            padding-left: 0;
            justify-content: flex-start;
        }
        .toc li {
            padding: 0;
        }
        .toc a {
            color: #1f2937;
            text-decoration: none;
            font-size: 18px;
            padding: 0;
            border: none;
            background: transparent;
            display: inline;
        }
        .toc a:hover {
            color: #111827;
            background: transparent;
            border: none;
            padding-left: 0;
        }
        .bundle-section {
            background: #ffffff;
            padding: 20px;
            margin-bottom: 30px;
        }
        .bundle-section h2 {
            color: #000000;
            font-size: 28px;
            margin-bottom: 10px;
            border-bottom: 1px solid #000000;
            padding-bottom: 10px;
        }
        .bundle-name {
            color: #000000;
            font-size: 14px;
            margin-bottom: 25px;
            font-family: 'Courier New', monospace;
        }
        .dashboards-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .dashboard-card {
            background: transparent;
            border: none;
            padding: 2px 0;
            text-align: left;
        }
        .dashboard-card:hover {
            background: transparent;
        }
        .dashboard-card a {
            color: #1f2937;
            text-decoration: none;
            display: inline;
        }
        .dashboard-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 5px;
        }
        .dashboard-desc {
            font-size: 13px;
            opacity: 1;
        }
        .dashboard-card.missing {
            background: transparent;
            color: #9ca3af;
            border: none;
            opacity: 1;
        }
        .dashboard-card.missing .dashboard-title,
        .dashboard-card.missing .dashboard-desc {
            color: #9ca3af;
        }
        .summary-section {
            background: #ffffff;
            border: 1px solid #000000;
            padding: 20px;
            margin-bottom: 30px;
        }
        .summary-section h2 {
            color: #000000;
            margin-bottom: 20px;
            border-bottom: 1px solid #000000;
            padding-bottom: 10px;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .stat-card {
            background: #ffffff;
            color: #000000;
            border: 1px solid #000000;
            padding: 20px;
            text-align: center;
        }
        .stat-value {
            font-size: 42px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .stat-label {
            font-size: 14px;
            opacity: 1;
        }
        .footer {
            text-align: center;
            color: #000000;
            margin-top: 30px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>${TICKET_ID}</h1>
            <h2 style="color: #000000; margin: 15px 0;">Comprehensive Analysis Dashboard</h2>
            <div class="meta">
                <strong>Generated:</strong> """ + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """ | 
                <strong>Bundles Analyzed:</strong> ${#BUNDLE_LOGS[@]} | 
                <strong>Total Dashboards:</strong> """ + str(${#BUNDLE_LOGS[@]} * 15) + """
            </div>
        </div>

        <div class="summary-section">
            <h2>Analysis Summary</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-value">${#BUNDLE_LOGS[@]}</div>
                    <div class="stat-label">Support Bundles</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">"""

# Count generated dashboards
total_dashboards = 0
for bundle_info in bundle_data:
    if '|' in bundle_info:
        parts = bundle_info.split('|')
        bundle_dir = os.path.join(output_dir, parts[2])
        if os.path.exists(bundle_dir):
            total_dashboards += len(glob.glob(os.path.join(bundle_dir, "*.html")))

bundle_count = len([b for b in bundle_data if '|' in b])
analysis_scripts_per_bundle = 15
analysis_scripts_run = bundle_count * analysis_scripts_per_bundle

rca_candidates = [
    "EXECUTIVE_SUMMARY.md",
    "COMPREHENSIVE_RCA_REPORT.md",
    "ERROR_TO_CODE_RCA_SUMMARY.md",
    "FIX_IMPLEMENTATION_GUIDE.md",
    "generated/comprehensive_bundle_analysis.html",
]
rca_reports_count = sum(1 for p in rca_candidates if os.path.exists(os.path.join(ticket_dir, p)))

html_content = html_content.replace(
    f"<strong>Total Dashboards:</strong> {bundle_count * 15}",
    f"<strong>Total Dashboards:</strong> {total_dashboards}"
)

html_content += str(total_dashboards) + """</div>
                    <div class="stat-label">Dashboards Generated</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">""" + str(analysis_scripts_run) + """</div>
                    <div class="stat-label">Analysis Scripts Run</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">""" + str(rca_reports_count) + """</div>
                    <div class="stat-label">RCA Reports</div>
                </div>
            </div>
        </div>

        <div class="toc">
            <h2>Table of Contents</h2>
            <ul>
"""

# Add TOC entries
for bundle_info in bundle_data:
    if '|' in bundle_info:
        parts = bundle_info.split('|')
        bundle_num = parts[0]
        html_content += f'                <li><a href="#bundle{bundle_num}">Bundle {bundle_num}</a></li>\n'

html_content += """            </ul>
        </div>
"""

# Dashboard metadata
dashboard_meta = {
    'cpu': ('CPU Analysis', 'CPU utilization and load average'),
    'mem': ('Memory Analysis', 'Memory usage and trends'),
    'disk': ('Disk Analysis', 'Disk I/O and capacity'),
    'net': ('Network Analysis', 'Network traffic and statistics'),
    'top': ('Top Processes', 'Resource-intensive processes'),
    'infoblox': ('Infoblox Logs', 'Comprehensive log analysis'),
    'bind_chr': ('BIND Cache', 'Cache hit ratio analysis'),
    'vdca_chr': ('vDCA Cache', 'vDCA cache performance'),
    'smaps': ('Memory Maps', 'Process memory mapping'),
    'fpcpu': ('Fastpath CPU', 'Fastpath CPU statistics'),
    'fpmbuf': ('Fastpath Mbufs', 'Fastpath buffer analysis'),
    'fpports': ('Fastpath Ports', 'Fastpath port statistics'),
    'fprrstat': ('Fastpath RR', 'Fastpath round-robin stats'),
    'fptcpdcastat': ('Fastpath TCP/DCA', 'TCP/DCA metrics'),
    'fpdtob': ('Fastpath DTOB', 'DTOB analysis')
}

# Add bundle sections
for bundle_info in bundle_data:
    if '|' in bundle_info:
        parts = bundle_info.split('|')
        bundle_num = parts[0]
        bundle_name = parts[1]
        bundle_dir_name = parts[2]
        bundle_dir = os.path.join(output_dir, bundle_dir_name)
        
        html_content += f"""
        <div class="bundle-section" id="bundle{bundle_num}">
            <h2>Bundle {bundle_num}</h2>
            <div class="bundle-name">{bundle_name}</div>
            
            <div class="dashboards-grid">
"""
        
        # Add dashboard cards
        for dashboard_id, (title, desc) in dashboard_meta.items():
            dashboard_file = os.path.join(bundle_dir, f"{dashboard_id}.html")
            rel_path = f"metric_dashboards/{bundle_dir_name}/{dashboard_id}.html"
            
            if os.path.exists(dashboard_file):
                html_content += f"""                <div class="dashboard-card">
                    <a href="{rel_path}" target="_blank">
                        <div class="dashboard-title">{title}</div>
                        <div class="dashboard-desc">{desc}</div>
                    </a>
                </div>
"""
            else:
                html_content += f"""                <div class="dashboard-card missing">
                    <div class="dashboard-title">{title}</div>
                    <div class="dashboard-desc">No data available</div>
                </div>
"""
        
        html_content += """            </div>
        </div>
"""

html_content += """
        <div class="footer">
            <p>Generated by Automated Analysis System - """ + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """</p>
            <p style="margin-top: 10px;">"""

# Add RCA links only if files exist to avoid broken footer links
rca_links = [
    ("EXECUTIVE_SUMMARY.md", "Executive Summary"),
    ("COMPREHENSIVE_RCA_REPORT.md", "Full RCA Report"),
    ("ERROR_TO_CODE_RCA_SUMMARY.md", "Error Analysis"),
    ("FIX_IMPLEMENTATION_GUIDE.md", "Fix Guide"),
]

existing_links = []
for filename, label in rca_links:
    if os.path.exists(os.path.join(ticket_dir, filename)):
        existing_links.append(
            f'<a href="{filename}" style="color: #1f2937; margin: 0 10px; text-decoration: none;">{label}</a>'
        )

if existing_links:
    html_content += " | ".join(existing_links)
else:
    html_content += "RCA markdown documents not available for this ticket"

html_content += """
            </p>
        </div>
    </div>
</body>
</html>
"""

# Write HTML file
output_file = os.path.join(ticket_dir, "COMPLETE_ANALYSIS_DASHBOARD.html")
with open(output_file, 'w') as f:
    f.write(html_content)

print(f"   ✅ Created: COMPLETE_ANALYSIS_DASHBOARD.html")
print(f"   📊 Total dashboards linked: {total_dashboards}")

PYTHON_SCRIPT

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   ✅ DASHBOARD GENERATION COMPLETE                       "
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Summary:"
echo "   • Support Bundles Analyzed: ${#BUNDLE_LOGS[@]}"
echo "   • Dashboards per Bundle: 15"
echo "   • Total Dashboards: $((${#BUNDLE_LOGS[@]} * 15))"
echo ""
echo "📄 Main Report:"
echo "   ${TICKET_DIR}/COMPLETE_ANALYSIS_DASHBOARD.html"
echo ""
echo "📂 Dashboard Location:"
echo "   ${OUTPUT_BASE_DIR}/"
echo ""
echo "🎯 Opening comprehensive dashboard..."
open "${TICKET_DIR}/COMPLETE_ANALYSIS_DASHBOARD.html"

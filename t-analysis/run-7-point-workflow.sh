#!/usr/bin/env bash

# 7-point NIOSSPT analysis workflow runner.
# Usage:
#   bash run-7-point-workflow.sh NIOSSPT-XXXXX

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TA_DIR="$SCRIPT_DIR"
SKILLS_DIR="$(cd "$TA_DIR/.." && pwd)"

parse_ticket_id() {
  local input="$1"

  if [[ "$input" =~ ^NIOSSPT-[0-9]+$ ]]; then
    echo "$input"
    return
  fi

  echo "Invalid ticket format: $input" >&2
  echo "Expected: NIOSSPT-XXXXX" >&2
  exit 1
}

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

print_link() {
  local p="$1"
  if [[ -f "$p" ]]; then
    echo "  - $p"
  fi
}

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 NIOSSPT-XXXXX"
  exit 1
fi

INPUT_TICKET="$1"
TICKET_ID="$(parse_ticket_id "$INPUT_TICKET")"
JIRA_TICKET_URL="https://infoblox.atlassian.net/browse/$TICKET_ID"
TICKET_DIR="$HOME/analysis_support_tickets/$TICKET_ID"
LOCAL_DIR="$TICKET_DIR/remote_files"

mkdir -p "$TICKET_DIR"
cd "$TICKET_DIR"

log "Starting 7-point workflow for $TICKET_ID"
log "Jira ticket URL (built internally): $JIRA_TICKET_URL"
log "Ticket directory: $TICKET_DIR"
log "t-analysis directory: $TA_DIR"

########################################
# Step 1: Read Jira ticket
########################################
log "Step 1/7: Reading Jira ticket"
bash "$TA_DIR/jira_access.sh" "$TICKET_ID" | tee "$TICKET_DIR/01_jira_ticket_raw.txt"

########################################
# Step 2: Summarize problem and ticket details
########################################
log "Step 2/7: Summarizing problem description and required details"
{
  echo "# $TICKET_ID - Problem Summary"
  echo
  echo "## Ticket Summary"
  sed -n 's/^Summary: //p' "$TICKET_DIR/01_jira_ticket_raw.txt"
  echo
  echo "## Ticket Description"
  sed -n 's/^Description: //p' "$TICKET_DIR/01_jira_ticket_raw.txt"
  echo
  echo "## Required Details Extracted"
  echo "- Ticket ID: $TICKET_ID"
  echo "- Generated At: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "- Jira URL: $JIRA_TICKET_URL"
} > "$TICKET_DIR/02_jira_problem_summary.md"

########################################
# Step 3: Download support bundles
########################################
log "Step 3/7: Downloading support bundles mentioned in ticket"
REMOTE_PATH="$(bash "$TA_DIR/jira_extract_case_path.sh" "$TICKET_ID")"

if [[ "$REMOTE_PATH" == /import/* ]]; then
  REMOTE_SERVER="pratapub@10.120.20.173"
else
  REMOTE_SERVER="pmallick@sup-xfer-01.inca.infoblox.com"
fi

bash "$TA_DIR/support_bundle_download.sh" "$REMOTE_SERVER" "$REMOTE_PATH" "$LOCAL_DIR" \
  | tee "$TICKET_DIR/03_download.log"

find "$LOCAL_DIR" -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" -o -name "*.gz" \) \
  | sort > "$TICKET_DIR/03_support_bundle_inventory.txt"

########################################
# Step 4: Generate comprehensive dashboard + terminal link
########################################
log "Step 4/7: Generating comprehensive dashboard from bundle data"
bash "$TA_DIR/run-all-bundle-dashboards.sh" "$TICKET_ID" . \
  | tee "$TICKET_DIR/04_comprehensive_dashboard_generation.log"

DASHBOARD_HTML="$TICKET_DIR/COMPLETE_ANALYSIS_DASHBOARD.html"
if [[ -f "$DASHBOARD_HTML" ]]; then
  log "Dashboard generated. Link:"
  echo "  - $DASHBOARD_HTML"
fi

########################################
# Step 5: Build per-bundle error+config HTML
########################################
log "Step 5/7: Extracting error logs and configuration details per bundle"
bash "$TA_DIR/extract-bundle-errors.sh" "$TICKET_ID" | tee "$TICKET_DIR/05_error_extraction.log"

STEP5_HTML="$TICKET_DIR/05_error_config_by_bundle.html"
python3 - "$TICKET_DIR" "$STEP5_HTML" << 'PY'
import glob
import html
import os
import re
import sys
from collections import defaultdict

if len(sys.argv) != 3:
    raise SystemExit("Usage: python build_step5_html.py <ticket_dir> <output_html>")

ticket_dir = os.path.expanduser(sys.argv[1])
out_html = os.path.expanduser(sys.argv[2])

errors_files = sorted(glob.glob(os.path.join(ticket_dir, "generated", "*_errors_warnings.txt")))
remote_files_dir = os.path.join(ticket_dir, "remote_files")

config_exts = {".conf", ".cfg", ".cnf", ".json", ".yaml", ".yml", ".xml", ".ini", ".env"}
config_names = {"named.conf", "dispatcher.env", "fast-path.env", "dns_cache_acceleration.json"}

all_config_files = []
if os.path.isdir(remote_files_dir):
    for root, _, files in os.walk(remote_files_dir):
        for fn in files:
            lower = fn.lower()
            ext = os.path.splitext(lower)[1]
            if ext in config_exts or lower in config_names or "config" in lower:
                all_config_files.append(os.path.join(root, fn))


def detect_bundle_name(path: str) -> str:
    base = os.path.basename(path)
    return re.sub(r"_errors_warnings\.txt$", "", base)


def pick_configs_for_bundle(bundle: str):
    bundle_l = bundle.lower()
    matched = [p for p in all_config_files if bundle_l in p.lower()]
    if matched:
        return matched[:80]
    return all_config_files[:80]


def tail_lines(text: str, limit: int = 120):
    lines = text.splitlines()
    if len(lines) <= limit:
        return lines
    return lines[:limit]

rows = []
for ef in errors_files:
    bundle = detect_bundle_name(ef)
    with open(ef, "r", encoding="utf-8", errors="ignore") as f:
        error_text = f.read()

    error_lines = [ln for ln in tail_lines(error_text, 180) if ln.strip()]
    configs = pick_configs_for_bundle(bundle)

    rows.append((bundle, error_lines, configs, ef))

html_parts = []
html_parts.append("<!doctype html>")
html_parts.append("<html><head><meta charset='utf-8'>")
html_parts.append("<meta name='viewport' content='width=device-width, initial-scale=1'>")
html_parts.append("<title>Error and Configuration Details by Bundle</title>")
html_parts.append("<style>")
html_parts.append("body{font-family:Arial,Helvetica,sans-serif;margin:24px;background:#f7f7f9;color:#111}")
html_parts.append("h1{margin-bottom:4px} h2{margin-top:28px}")
html_parts.append(".meta{color:#555;margin-bottom:20px}")
html_parts.append(".card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:16px;margin:16px 0}")
html_parts.append("pre{background:#111;color:#f5f5f5;padding:10px;border-radius:6px;overflow:auto;max-height:380px}")
html_parts.append("ul{margin:0 0 0 20px}")
html_parts.append("code{background:#eee;padding:2px 6px;border-radius:4px}")
html_parts.append("</style></head><body>")
html_parts.append("<h1>Error Logs and Configuration Details by Support Bundle</h1>")
html_parts.append(f"<div class='meta'>Generated: {html.escape(__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S'))}</div>")

if not rows:
    html_parts.append("<div class='card'><strong>No *_errors_warnings.txt files found under generated/</strong></div>")
else:
    for bundle, error_lines, configs, src in rows:
        html_parts.append("<div class='card'>")
        html_parts.append(f"<h2>{html.escape(bundle)}</h2>")
        html_parts.append(f"<div>Source error file: <code>{html.escape(src)}</code></div>")
        html_parts.append(f"<div>Matched config files: {len(configs)}</div>")
        html_parts.append("<h3>Errors and Warnings (excerpt)</h3>")
        html_parts.append("<pre>" + html.escape("\n".join(error_lines) if error_lines else "No non-empty lines captured") + "</pre>")
        html_parts.append("<h3>Configuration Files (sample)</h3>")
        if configs:
            html_parts.append("<ul>")
            for c in configs[:60]:
                html_parts.append(f"<li><code>{html.escape(c)}</code></li>")
            html_parts.append("</ul>")
        else:
            html_parts.append("<div>No matching configuration files found.</div>")
        html_parts.append("</div>")

html_parts.append("</body></html>")

with open(out_html, "w", encoding="utf-8") as f:
    f.write("\n".join(html_parts))

print(out_html)
PY

log "Step 5 HTML generated. Link:"
echo "  - $STEP5_HTML"

########################################
# Step 6: Per-support-bundle report + per-bundle html links
########################################
log "Step 6/7: Generating per-support-bundle reports"
bash "$TA_DIR/run-bundle-scripts.sh" "$TICKET_ID" --skip-extraction \
  | tee "$TICKET_DIR/06_per_bundle_script_runs.log"

bash "$TA_DIR/generate-bundle-analysis-report.sh" "$TICKET_ID" \
  | tee "$TICKET_DIR/06_per_bundle_report_generation.log"

log "Per-bundle HTML links (metric dashboards):"
find "$TICKET_DIR/metric_dashboards" -type f -name '*.html' 2>/dev/null | sort | while IFS= read -r f; do
  echo "  - $f"
done

if [[ -f "$TICKET_DIR/generated/comprehensive_bundle_analysis.html" ]]; then
  log "Comprehensive bundle HTML report link:"
  echo "  - $TICKET_DIR/generated/comprehensive_bundle_analysis.html"
fi

########################################
# Step 7: Final RCA report set
########################################
log "Step 7/7: Generating final RCA report"
python3 "$TA_DIR/generate-final-rca.py" "$TICKET_DIR" \
  | tee "$TICKET_DIR/07_final_rca_generation.log"

log "Final RCA outputs:"
for f in EXECUTIVE_SUMMARY.md COMPREHENSIVE_RCA_REPORT.md ERROR_TO_CODE_RCA_SUMMARY.md FIX_IMPLEMENTATION_GUIDE.md; do
  if [[ -f "$TICKET_DIR/$f" ]]; then
    echo "  - $TICKET_DIR/$f"
  else
    echo "  - MISSING: $TICKET_DIR/$f"
  fi
done

log "Workflow complete for $TICKET_ID"

# NIOSSPT 7-Point Analysis Skill (t-analysis)

## Goal
This skill executes the full ticket workflow and generates verifiable outputs for all 7 required points:

1. Read the Jira ticket
2. Summarize problem description and required ticket details
3. Download support bundles mentioned in ticket
4. Generate comprehensive dashboard from all support bundle data
5. Generate analysis with respect to the problem statement for each extracted bundle
6. Generate per-support-bundle report
7. Generate final RCA report

## Preconditions
- Jira credentials exist in ~/.jira-credentials (JIRA_USER/JIRA_TOKEN)
- Network access exists to Jira and support bundle host
- Ticket data lives under ~/analysis_support_tickets/<TICKET_ID>

## Rerun Semantics
- If the ticket directory already exists, reuse Step 1 and Step 2 outputs when present.
- Always rerun Step 3 through Step 7 to refresh analysis from latest bundle data.
- Step 3 must use incremental sync behavior: download only missing or changed files from remote.

## Standard Variables
Run these first:

```bash
TICKET_ID="NIOSSPT-XXXXX"
SKILLS_DIR="$HOME/Downloads/old_mac/analysis_data/skills_desk"
TA_DIR="$SKILLS_DIR/t-analysis"
TICKET_DIR="$HOME/analysis_support_tickets/$TICKET_ID"
mkdir -p "$TICKET_DIR"
cd "$TICKET_DIR"
```

## Output Contract (7 points -> 7 outputs)
- Point 1 output: 01_jira_ticket_raw.txt
- Point 2 output: 02_jira_problem_summary.md
- Point 3 output: 03_support_bundle_inventory.txt
- Point 4 output: COMPLETE_ANALYSIS_DASHBOARD.html
- Point 5 output: 05_problem_statement_bundle_analysis.md
- Point 6 output: generated/comprehensive_bundle_analysis.html and generated/bundle_script_analysis/<bundle>/analysis_report.txt
- Point 7 outputs: EXECUTIVE_SUMMARY.md, COMPREHENSIVE_RCA_REPORT.md, ERROR_TO_CODE_RCA_SUMMARY.md, FIX_IMPLEMENTATION_GUIDE.md

---

## Step 1: Read Jira Ticket

```bash
bash "$TA_DIR/jira_access.sh" "$TICKET_ID" | tee "$TICKET_DIR/01_jira_ticket_raw.txt"
```

Validation:

```bash
grep -E "^Summary:|^Description:" "$TICKET_DIR/01_jira_ticket_raw.txt"
```

## Step 2: Summarize Problem Description and Ticket Details

```bash
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
  echo "- Jira URL: https://infoblox.atlassian.net/browse/$TICKET_ID"
} > "$TICKET_DIR/02_jira_problem_summary.md"
```

Validation:

```bash
head -40 "$TICKET_DIR/02_jira_problem_summary.md"
```

## Step 3: Download Support Bundles Mentioned in Ticket

```bash
REMOTE_PATH="$(bash "$TA_DIR/jira_extract_case_path.sh" "$TICKET_ID")"
LOCAL_DIR="$TICKET_DIR/remote_files"

# Use import-host credentials for /import paths.
if [[ "$REMOTE_PATH" == /import/* ]]; then
  REMOTE_SERVER="pratapub@10.120.20.173"
else
  REMOTE_SERVER="pmallick@sup-xfer-01.inca.infoblox.com"
fi

bash "$TA_DIR/support_bundle_download.sh" "$REMOTE_SERVER" "$REMOTE_PATH" "$LOCAL_DIR" \
  | tee "$TICKET_DIR/03_download.log"

find "$LOCAL_DIR" -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" -o -name "*.gz" \) \
  | sort > "$TICKET_DIR/03_support_bundle_inventory.txt"
```

Validation:

```bash
wc -l "$TICKET_DIR/03_support_bundle_inventory.txt"
```

## Step 4: Generate Comprehensive Dashboard from All Support Bundle Data

```bash
bash "$TA_DIR/run-all-bundle-dashboards.sh" "$TICKET_ID" . \
  | tee "$TICKET_DIR/04_comprehensive_dashboard_generation.log"
```

Validation:

```bash
test -f "$TICKET_DIR/COMPLETE_ANALYSIS_DASHBOARD.html" && echo "OK: COMPLETE_ANALYSIS_DASHBOARD.html"
find "$TICKET_DIR/metric_dashboards" -name "*.html" | wc -l
```

## Step 5: Generate Problem-Statement-Based Analysis Per Extracted Bundle

First extract errors/warnings used for problem-alignment analysis:

```bash
bash "$TA_DIR/extract-bundle-errors.sh" "$TICKET_ID" | tee "$TICKET_DIR/05_error_extraction.log"
```

Then create bundle-wise problem statement correlation report:

```bash
python3 - "$TICKET_DIR" << 'PY'
import os, re, glob
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
    text = open(summary_path, "r", encoding="utf-8", errors="ignore").read().lower()

stop = {
    "the","and","for","with","from","that","this","have","has","had","was","were","are","is",
    "a","an","of","to","in","on","at","by","as","or","be","it","its","into","their","they",
    "issue","ticket","summary","description","details","required","generated","analysis","report"
}
words = re.findall(r"[a-z0-9_]{4,}", text)
keywords = [w for w in words if w not in stop and not w.isdigit()]

# keep top unique keywords by frequency
freq = Counter(keywords)
selected = [k for k, _ in freq.most_common(20)]
if not selected:
    selected = ["error", "timeout", "dns", "memory", "fail"]

lines = []
lines.append(f"# Problem Statement Correlation by Bundle")
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
        content = open(fp, "r", encoding="utf-8", errors="ignore").read().lower()
        hit_counts = {k: content.count(k) for k in selected}
        total_hits = sum(hit_counts.values())
        top_hits = sorted(hit_counts.items(), key=lambda x: x[1], reverse=True)[:5]

        lines.append(f"### {name}")
        lines.append(f"- Total keyword hits: {total_hits}")
        lines.append("- Top matched keywords:")
        for k, v in top_hits:
            lines.append(f"  - {k}: {v}")
        lines.append("")

open(out_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(out_path)
PY
```

Validation:

```bash
head -80 "$TICKET_DIR/05_problem_statement_bundle_analysis.md"
```

## Step 6: Generate Per-Support-Bundle Reports

```bash
bash "$TA_DIR/run-bundle-scripts.sh" "$TICKET_ID" --skip-extraction \
  | tee "$TICKET_DIR/06_per_bundle_script_runs.log"

bash "$TA_DIR/generate-bundle-analysis-report.sh" "$TICKET_ID" \
  | tee "$TICKET_DIR/06_per_bundle_report_generation.log"
```

Validation:

```bash
test -f "$TICKET_DIR/generated/comprehensive_bundle_analysis.html" && echo "OK: comprehensive_bundle_analysis.html"
find "$TICKET_DIR/generated/bundle_script_analysis" -name "analysis_report.txt" | wc -l
```

## Step 7: Generate Final RCA Report Set

```bash
python3 "$TA_DIR/generate-final-rca.py" "$TICKET_DIR" \
  | tee "$TICKET_DIR/07_final_rca_generation.log"
```

Validation:

```bash
for f in EXECUTIVE_SUMMARY.md COMPREHENSIVE_RCA_REPORT.md ERROR_TO_CODE_RCA_SUMMARY.md FIX_IMPLEMENTATION_GUIDE.md; do
  test -f "$TICKET_DIR/$f" && echo "OK: $f" || echo "MISSING: $f"
done
```

---

## One-Command Execution Order

```bash
# Run in order from Step 1 to Step 7 in this file.
# If any step fails, fix credentials/path/input and rerun that step before proceeding.
```

## Final Deliverables Checklist

```bash
ls -lh \
  "$TICKET_DIR/01_jira_ticket_raw.txt" \
  "$TICKET_DIR/02_jira_problem_summary.md" \
  "$TICKET_DIR/03_support_bundle_inventory.txt" \
  "$TICKET_DIR/COMPLETE_ANALYSIS_DASHBOARD.html" \
  "$TICKET_DIR/05_problem_statement_bundle_analysis.md" \
  "$TICKET_DIR/generated/comprehensive_bundle_analysis.html" \
  "$TICKET_DIR/EXECUTIVE_SUMMARY.md" \
  "$TICKET_DIR/COMPREHENSIVE_RCA_REPORT.md" \
  "$TICKET_DIR/ERROR_TO_CODE_RCA_SUMMARY.md" \
  "$TICKET_DIR/FIX_IMPLEMENTATION_GUIDE.md"
```

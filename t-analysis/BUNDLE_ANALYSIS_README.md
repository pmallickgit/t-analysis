# Bundle Script Analysis Workflow

## Overview

This collection of scripts automates the process of extracting support bundles, running analysis scripts from the bundle's `/var/log/scripts` directory, and generating comprehensive reports.

## Scripts Included

### 1. **run-bundle-scripts.sh**
Executes scripts found in extracted support bundles and collects analysis results.

**Usage:**
```bash
bash run-bundle-scripts.sh <TICKET_ID> [--skip-extraction]
```

**Features:**
- Discovers all extracted bundle directories
- Locates `var/log/scripts` in each bundle
- Executes scripts and captures output
- Runs base analysis scripts from the main `scripts/` directory
- Generates per-bundle analysis reports
- Creates summary report with statistics

**Output:**
- `generated/bundle_script_analysis/` - Directory containing analysis for each bundle
- `generated/bundle_scripts_summary.txt` - Overall execution summary

### 2. **generate-bundle-analysis-report.sh**
Creates an interactive HTML report from collected script outputs.

**Usage:**
```bash
bash generate-bundle-analysis-report.sh <TICKET_ID>
```

**Features:**
- Generates beautiful HTML report with CSS styling
- Includes executive summary with statistics
- Table of contents with bundle navigation
- Per-bundle analysis sections
- Script output preview in report
- Mobile-responsive design

**Output:**
- `generated/comprehensive_bundle_analysis.html` - Interactive web report

### 3. **analyze-complete-bundle.sh**
Master orchestration script that runs the complete workflow in sequence.

**Usage:**
```bash
bash analyze-complete-bundle.sh <TICKET_ID> [--skip-extraction]
```

**Workflow:**
1. Extracts support bundle files (if not skipped)
2. Runs scripts from each bundle
3. Generates comprehensive HTML report
4. Creates detailed summary and logs

**Output:**
- `analysis_workflow.log` - Complete workflow execution log
- All outputs from previous scripts

## Directory Structure

```
/Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/
├── t-analysis/
│   ├── run-bundle-scripts.sh
│   ├── generate-bundle-analysis-report.sh
│   ├── analyze-complete-bundle.sh
│   ├── extract-bundle-errors.sh
│   └── BUNDLE_ANALYSIS_README.md (this file)
├── scripts/
│   ├── cpu_analysis.sh
│   ├── mem_analysis.sh
│   ├── disk_analysis.sh
│   └── ... (other analysis scripts)
└── ~/analysis_support_tickets/
    └── <TICKET_ID>/
        ├── bundle1/
        │   └── var/log/scripts/
        ├── bundle2/
        │   └── var/log/scripts/
        └── generated/
            ├── bundle_script_analysis/
            ├── bundle_scripts_summary.txt
            ├── comprehensive_bundle_analysis.html
            └── analysis_workflow.log
```

## Workflow

### Quick Start

```bash
# Complete workflow from extraction to report
cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis
bash analyze-complete-bundle.sh NIOSSPT-XXXXX
```

### Step-by-Step

```bash
# Step 1: Run scripts on extracted bundles
bash run-bundle-scripts.sh NIOSSPT-XXXXX

# Step 2: Generate HTML report
bash generate-bundle-analysis-report.sh NIOSSPT-XXXXX

# Step 3: View results
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html
```

### Skip Extraction

If bundles are already extracted:

```bash
bash analyze-complete-bundle.sh NIOSSPT-XXXXX --skip-extraction
```

## Script Features

### run-bundle-scripts.sh

**What it does:**
1. Discovers all bundle directories in the ticket folder
2. For each bundle:
   - Locates the `var/log` directory
   - Runs any scripts in `var/log/scripts/`
   - Runs all base analysis scripts from `scripts/` directory
   - Captures output and generates reports

**Environment Variables (for base scripts):**
- `VAR_LOG` - Path to the bundle's var/log directory
- `BUNDLE_DIR` - Path to the bundle directory
- `BUNDLE_NAME` - Name of the bundle being analyzed

**Output Files:**
- `bundle_script_analysis/<bundle>/<script>_output.txt` - Script execution results
- `bundle_script_analysis/<bundle>/<script>_analysis.txt` - Analysis results from base scripts
- `bundle_script_analysis/<bundle>/analysis_report.txt` - Per-bundle summary

### generate-bundle-analysis-report.sh

**What it does:**
1. Reads all analysis outputs from `bundle_script_analysis/`
2. Creates professional HTML report
3. Includes statistics, tables of contents, and previews

**Report Features:**
- Responsive design that works on mobile and desktop
- Color-coded success/failure indicators
- Expandable sections for each bundle
- Output previews with line counts and file sizes
- Executive summary with key metrics

## Customization

### Adding Base Analysis Scripts

Place analysis scripts in `scripts/` directory. They will be automatically executed by `run-bundle-scripts.sh` with access to:

```bash
# In your analysis script, you can access:
$VAR_LOG      # var/log directory of the bundle
$BUNDLE_DIR   # root directory of the bundle
$BUNDLE_NAME  # name of the bundle
```

Example:

```bash
#!/bin/bash
# scripts/custom_analysis.sh

if [[ -z "$VAR_LOG" ]]; then
    echo "Error: VAR_LOG not set"
    exit 1
fi

# Your analysis code
grep -r "error" "$VAR_LOG" | wc -l
```

## Troubleshooting

### Scripts not found
- Ensure bundles are properly extracted with `var/log/scripts/` structure
- Check that base scripts exist in `scripts/` directory

### No output generated
- Verify ticket ID is correct
- Check `analysis_workflow.log` for error messages
- Run individual scripts manually to diagnose issues

### HTML report not displaying
- Ensure `bundle_script_analysis/` directory was created
- Check for JavaScript console errors in browser
- Try viewing with a different browser

## Examples

### Analyze a JIRA Ticket

```bash
cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis

# Run complete workflow
bash analyze-complete-bundle.sh NIOSSPT-XXXXX

# View results
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html
```

### View Summary Stats

```bash
cat ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_scripts_summary.txt
```

### Run Specific Scripts Only

```bash
# Extract and run scripts, but skip extraction
bash run-bundle-scripts.sh NIOSSPT-XXXXX --skip-extraction
```

## Performance Considerations

- **Bundle Size:** Larger bundles take longer to analyze
- **Script Count:** More scripts = longer execution time
- **Disk Space:** Ensure sufficient space in `~/analysis_support_tickets/`
- **Network:** If bundles are remote, ensure network connectivity

## Log Files

All activities are logged to:
- `analysis_workflow.log` - Complete workflow execution log
- `bundle_script_analysis/<bundle>/analysis_report.txt` - Per-bundle execution logs
- `bundle_scripts_summary.txt` - Statistics and summary

## Support

For issues or questions, check:
1. The workflow log for error messages
2. Individual script output files
3. Verify input bundle structure and extraction

## Notes

- Scripts preserve all output, including errors
- Analysis results are cumulative - rerunning adds new results
- HTML reports are self-contained and can be shared
- All paths support both canonical ticket directory (`~/analysis_support_tickets/`) and relative paths

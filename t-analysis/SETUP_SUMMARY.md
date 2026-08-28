# Bundle Script Analysis Workflow - Created Resources

## Summary

I've created a complete automated workflow for analyzing support bundles by running scripts from within each extracted bundle and generating detailed analysis reports.

## Files Created (in `/Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis/`)

### 1. **run-bundle-scripts.sh** ⚙️
- **Purpose:** Discover and execute scripts from each bundle's `var/log/scripts/` directory
- **Features:**
  - Processes all bundles in the ticket directory
  - Runs both embedded bundle scripts and base analysis scripts
  - Captures output for each script execution
  - Generates per-bundle analysis reports
  - Creates summary statistics
  
**Usage:**
```bash
bash run-bundle-scripts.sh NIOSSPT-XXXXX
bash run-bundle-scripts.sh NIOSSPT-XXXXX --skip-extraction  # If already extracted
```

---

### 2. **generate-bundle-analysis-report.sh** 📊
- **Purpose:** Create interactive HTML report from collected analysis results
- **Features:**
  - Beautifully styled responsive HTML5 report
  - Executive summary with key metrics
  - Table of contents for easy navigation
  - Per-bundle sections with script details
  - Output previews with line counts and file sizes
  - Color-coded success/failure indicators
  
**Usage:**
```bash
bash generate-bundle-analysis-report.sh NIOSSPT-XXXXX
```

**Output:** `~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html`

---

### 3. **analyze-complete-bundle.sh** 🚀
- **Purpose:** Master orchestration script for complete workflow
- **Workflow:**
  1. Extracts support bundles (optional, can skip)
  2. Runs all scripts on extracted bundles
  3. Generates comprehensive HTML report
  4. Creates detailed workflow log
  
**Usage:**
```bash
bash analyze-complete-bundle.sh NIOSSPT-XXXXX
bash analyze-complete-bundle.sh NIOSSPT-XXXXX --skip-extraction  # Skip extraction
```

---

### 4. **BUNDLE_ANALYSIS_README.md** 📖
- Comprehensive documentation
- Workflow explanation
- Directory structure reference
- Customization guide
- Troubleshooting section
- Examples

---

### 5. **QUICK_START.sh** 🎯
- Quick reference guide with examples
- Copy-paste ready commands
- All usage options
- Output locations
- Troubleshooting tips

---

## How It Works

### Data Flow

```
Support Bundle (*.tar.gz, *.zip)
    ↓
[Extract] extract-bundle-errors.sh
    ↓
Extracted Bundles
    ├── bundle1/var/log/scripts/*.sh
    ├── bundle2/var/log/scripts/*.sh
    └── bundleN/var/log/scripts/*.sh
    ↓
[Run Scripts] run-bundle-scripts.sh
    ├── Execute scripts from var/log/scripts/
    ├── Execute base scripts from scripts/
    └── Capture all output
    ↓
Collected Results
    └── generated/bundle_script_analysis/
        ├── bundle1/
        ├── bundle2/
        └── bundleN/
    ↓
[Generate Report] generate-bundle-analysis-report.sh
    ↓
Generated Reports
    ├── comprehensive_bundle_analysis.html
    ├── bundle_scripts_summary.txt
    └── analysis_workflow.log
```

---

## Quick Start

### One-Command Complete Analysis

```bash
cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis

# Run complete workflow
bash analyze-complete-bundle.sh NIOSSPT-XXXXX

# View HTML report
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html
```

### Step-by-Step Manual Workflow

```bash
cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis

# Step 1: Run scripts
bash run-bundle-scripts.sh NIOSSPT-XXXXX

# Step 2: Generate report
bash generate-bundle-analysis-report.sh NIOSSPT-XXXXX

# Step 3: View results
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html
cat ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_scripts_summary.txt
```

---

## Output Structure

```
~/analysis_support_tickets/<TICKET_ID>/
├── extracted_bundles/
│   └── bundle_contents...
├── generated/
│   ├── bundle_script_analysis/
│   │   ├── bundle1/
│   │   │   ├── analysis_report.txt
│   │   │   ├── script1_output.txt
│   │   │   ├── script2_output.txt
│   │   │   ├── cpu_analysis_analysis.txt
│   │   │   └── mem_analysis_analysis.txt
│   │   ├── bundle2/
│   │   │   └── ...
│   │   └── bundleN/
│   │       └── ...
│   ├── bundle_scripts_summary.txt
│   ├── comprehensive_bundle_analysis.html
│   └── analysis_workflow.log
```

---

## Key Features

✅ **Automated Script Discovery**
- Automatically finds scripts in each bundle's var/log/scripts/ directory

✅ **Dual-Mode Execution**
- Run scripts embedded in bundles
- Run base analysis scripts from scripts/ directory with bundle context

✅ **Context Passing**
- Scripts receive environment variables:
  - `$VAR_LOG` - Path to bundle's var/log
  - `$BUNDLE_DIR` - Path to bundle root
  - `$BUNDLE_NAME` - Name of current bundle

✅ **Comprehensive Reporting**
- Per-bundle analysis reports
- Summary statistics and metrics
- Beautiful interactive HTML report
- Complete workflow logs

✅ **Error Handling**
- Gracefully handles missing directories
- Captures and logs all errors
- Continues processing on script failures

✅ **Reusable**
- Can run multiple times (results accumulate)
- Works with already-extracted bundles
- No destructive operations

---

## Examples

### Example 1: Analyze a ticket
```bash
cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis
bash analyze-complete-bundle.sh NIOSSPT-XXXXX
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html
```

### Example 2: Skip Extraction (Already Extracted)
```bash
bash analyze-complete-bundle.sh NIOSSPT-YYYYY --skip-extraction
```

### Example 3: Manual Process for Custom Analysis
```bash
# Just run scripts, skip report generation
bash run-bundle-scripts.sh NIOSSPT-XXXXX

# Manually inspect results
ls -la ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_script_analysis/

# Then generate report later
bash generate-bundle-analysis-report.sh NIOSSPT-XXXXX
```

---

## Integration with Existing Scripts

The new scripts integrate seamlessly with existing tools:

- **extract-bundle-errors.sh** - Still available for error extraction
- **scripts/** directory - Analysis scripts executed automatically
- **Ticket directories** - Uses standard ~/analysis_support_tickets/ location

---

## Customization

### Adding Custom Analysis Scripts

Place any executable script in `scripts/` directory. It will be automatically run by `run-bundle-scripts.sh`:

```bash
#!/bin/bash
# scripts/my_custom_analysis.sh

# Access bundle context
echo "Analyzing bundle: $BUNDLE_NAME"
echo "VAR/LOG location: $VAR_LOG"

# Your analysis code
if [[ -f "$VAR_LOG/infoblox.log" ]]; then
    grep "ERROR" "$VAR_LOG/infoblox.log" | wc -l
fi
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Scripts not found | Ensure you're in t-analysis directory |
| No output generated | Check `analysis_workflow.log` for errors |
| Bundles not extracted | Remove `--skip-extraction` flag |
| HTML report blank | Run `run-bundle-scripts.sh` first |
| Permission denied | Run `chmod +x *.sh` in t-analysis directory |

---

## Performance Notes

- **Time:** Depends on bundle size and script count
- **Disk Space:** Results stored in generated/ directory
- **CPU:** Scripts run sequentially (can be parallelized if needed)
- **Network:** Only if bundles need to be downloaded first

---

## Next Steps

1. **Run the analysis:**
   ```bash
   cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis
   bash analyze-complete-bundle.sh NIOSSPT-XXXXX
   ```

2. **View the HTML report:**
   ```bash
   open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html
   ```

3. **Check the summary:**
   ```bash
   cat ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_scripts_summary.txt
   ```

4. **Review workflow log:**
   ```bash
   cat ~/analysis_support_tickets/NIOSSPT-XXXXX/analysis_workflow.log
   ```

---

## Support & Documentation

- **Quick Start:** `QUICK_START.sh` - Copy-paste commands
- **Full Documentation:** `BUNDLE_ANALYSIS_README.md` - Comprehensive guide
- **This File:** `SETUP_SUMMARY.md` - Overview and features

---

**Created:** May 18, 2026  
**Location:** `/Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis/`  
**All scripts are executable and ready to use!**

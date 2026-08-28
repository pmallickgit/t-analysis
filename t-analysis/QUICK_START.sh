#!/bin/bash
# QUICK START GUIDE FOR BUNDLE ANALYSIS SCRIPTS

# ╔════════════════════════════════════════════════════════════╗
# ║    BUNDLE ANALYSIS WORKFLOW - QUICK START GUIDE           ║
# ╚════════════════════════════════════════════════════════════╝

# LOCATION: /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis/

# ════════════════════════════════════════════════════════════════
# OPTION 1: Complete Workflow (Recommended)
# ════════════════════════════════════════════════════════════════

# This runs everything in sequence: extract → run scripts → generate report

cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis

# Replace NIOSSPT-XXXXX with your actual ticket ID
bash analyze-complete-bundle.sh NIOSSPT-XXXXX

# Then view the report:
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html


# ════════════════════════════════════════════════════════════════
# OPTION 2: Skip Extraction (If bundles already extracted)
# ════════════════════════════════════════════════════════════════

bash analyze-complete-bundle.sh NIOSSPT-XXXXX --skip-extraction


# ════════════════════════════════════════════════════════════════
# OPTION 3: Manual Step-by-Step
# ════════════════════════════════════════════════════════════════

# Step 1: Run scripts on all bundles
bash run-bundle-scripts.sh NIOSSPT-XXXXX

# Step 2: Generate HTML report from results
bash generate-bundle-analysis-report.sh NIOSSPT-XXXXX

# Step 3: View the report
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html

# Step 4: View summary statistics
cat ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_scripts_summary.txt


# ════════════════════════════════════════════════════════════════
# OUTPUT LOCATIONS
# ════════════════════════════════════════════════════════════════

# Ticket Directory:
# ~/analysis_support_tickets/NIOSSPT-XXXXX/

# Generated Results:
# ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/

# Bundle Script Analysis:
# ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_script_analysis/

# HTML Report:
# ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html

# Summary Report:
# ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_scripts_summary.txt

# Workflow Log:
# ~/analysis_support_tickets/NIOSSPT-XXXXX/analysis_workflow.log


# ════════════════════════════════════════════════════════════════
# VIEW RESULTS
# ════════════════════════════════════════════════════════════════

# View HTML report in browser:
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html

# View summary in terminal:
cat ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_scripts_summary.txt

# View workflow log:
cat ~/analysis_support_tickets/NIOSSPT-XXXXX/analysis_workflow.log

# List all bundle analyses:
ls -la ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_script_analysis/

# View specific bundle report:
cat ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_script_analysis/<bundle_name>/analysis_report.txt


# ════════════════════════════════════════════════════════════════
# WHAT THESE SCRIPTS DO
# ════════════════════════════════════════════════════════════════

# 1. run-bundle-scripts.sh
#    - Extracts all support bundles (if not already extracted)
#    - Runs scripts from each bundle's var/log/scripts/ directory
#    - Runs base analysis scripts from scripts/ directory
#    - Collects and organizes results
#    - Generates per-bundle analysis reports

# 2. generate-bundle-analysis-report.sh
#    - Creates a beautiful, interactive HTML report
#    - Includes statistics, summaries, and bundle navigation
#    - Previews script outputs
#    - Mobile-responsive design

# 3. analyze-complete-bundle.sh
#    - Master orchestration script
#    - Runs all steps in the correct sequence
#    - Generates complete workflow log
#    - Provides summary of all generated files


# ════════════════════════════════════════════════════════════════
# SCRIPTS IN THIS DIRECTORY
# ════════════════════════════════════════════════════════════════

# run-bundle-scripts.sh              - Main analysis runner
# generate-bundle-analysis-report.sh - HTML report generator
# analyze-complete-bundle.sh         - Master workflow orchestrator
# extract-bundle-errors.sh           - Error extraction utility
# BUNDLE_ANALYSIS_README.md          - Full documentation


# ════════════════════════════════════════════════════════════════
# TROUBLESHOOTING
# ════════════════════════════════════════════════════════════════

# Q: Scripts not found?
# A: Ensure you're running from t-analysis directory

# Q: No output generated?
# A: Check analysis_workflow.log for error messages

# Q: Bundles not extracted?
# A: Remove --skip-extraction flag or check bundle location

# Q: HTML report blank?
# A: Ensure run-bundle-scripts.sh completed successfully

# Q: Want to rerun analysis?
# A: Just run the scripts again - results accumulate in generated/


# ════════════════════════════════════════════════════════════════
# EXAMPLES
# ════════════════════════════════════════════════════════════════

# Example 1: Analyze a ticket
cd /Users/pmallick/Downloads/old_mac/analysis_data/skills_desk/t-analysis
bash analyze-complete-bundle.sh NIOSSPT-XXXXX
open ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/comprehensive_bundle_analysis.html

# Example 2: Analyze an already extracted ticket
bash analyze-complete-bundle.sh NIOSSPT-YYYYY --skip-extraction
open ~/analysis_support_tickets/NIOSSPT-YYYYY/generated/comprehensive_bundle_analysis.html

# Example 3: Manual workflow
bash run-bundle-scripts.sh NIOSSPT-XXXXX
bash generate-bundle-analysis-report.sh NIOSSPT-XXXXX
cat ~/analysis_support_tickets/NIOSSPT-XXXXX/generated/bundle_scripts_summary.txt

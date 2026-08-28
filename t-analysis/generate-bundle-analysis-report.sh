#!/bin/bash
# Generate Comprehensive Analysis Report from Bundle Scripts
# Usage: ./generate-bundle-analysis-report.sh <TICKET_ID>

TICKET_ID="${1}"

if [[ -z "$TICKET_ID" ]]; then
    echo "❌ Error: Ticket ID required"
    echo "Usage: bash generate-bundle-analysis-report.sh NIOSSPT-XXXXX"
    exit 1
fi

# Set up directories
if [[ -d "$HOME/analysis_support_tickets/$TICKET_ID" ]]; then
    TICKET_DIR="$HOME/analysis_support_tickets/$TICKET_ID"
else
    TICKET_DIR="$(pwd)"
fi

GENERATED_DIR="${TICKET_DIR}/generated"
BUNDLE_ANALYSIS_DIR="${GENERATED_DIR}/bundle_script_analysis"
REPORT_OUTPUT="${GENERATED_DIR}/comprehensive_bundle_analysis.html"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     GENERATING COMPREHENSIVE ANALYSIS REPORT              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Ticket ID: $TICKET_ID"
echo "Source Directory: $BUNDLE_ANALYSIS_DIR"
echo "Output File: $REPORT_OUTPUT"
echo ""

# Check if analysis directory exists
if [[ ! -d "$BUNDLE_ANALYSIS_DIR" ]]; then
    echo "❌ Error: Bundle analysis directory not found"
    echo "   Please run run-bundle-scripts.sh first"
    exit 1
fi

# Start HTML report
cat > "$REPORT_OUTPUT" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bundle Script Analysis Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        
        .meta-info {
            background: #f8f9fa;
            padding: 20px 40px;
            border-bottom: 2px solid #e9ecef;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
        }
        
        .meta-item {
            padding: 10px;
            border-radius: 5px;
            background: white;
        }
        
        .meta-item strong {
            display: block;
            color: #667eea;
            font-size: 0.9em;
            margin-bottom: 5px;
        }
        
        .content {
            padding: 40px;
        }
        
        .bundle-section {
            margin-bottom: 50px;
            border: 2px solid #e9ecef;
            border-radius: 8px;
            padding: 25px;
            background: #fafbfc;
        }
        
        .bundle-title {
            font-size: 1.8em;
            color: #667eea;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 3px solid #667eea;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .bundle-title::before {
            content: "📦";
            font-size: 1.3em;
        }
        
        .script-result {
            background: white;
            padding: 20px;
            margin: 15px 0;
            border-left: 5px solid #667eea;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.05);
        }
        
        .script-result.success {
            border-left-color: #28a745;
            background: #f0f9f4;
        }
        
        .script-result.failed {
            border-left-color: #dc3545;
            background: #fdf4f5;
        }
        
        .script-name {
            font-weight: bold;
            font-size: 1.1em;
            color: #333;
            margin-bottom: 8px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .script-result.success .script-name::before {
            content: "✅";
        }
        
        .script-result.failed .script-name::before {
            content: "❌";
        }
        
        .script-meta {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 10px;
            padding-top: 10px;
            border-top: 1px solid #ddd;
            font-size: 0.95em;
        }
        
        .script-meta span {
            color: #666;
        }
        
        .script-meta strong {
            color: #333;
            display: block;
        }
        
        .script-output {
            background: #f5f5f5;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 15px;
            margin-top: 10px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            max-height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        
        .summary-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            border-radius: 10px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .stat-card h3 {
            font-size: 1em;
            opacity: 0.9;
            margin-bottom: 10px;
        }
        
        .stat-card .number {
            font-size: 2.5em;
            font-weight: bold;
        }
        
        .section-title {
            font-size: 1.5em;
            color: #667eea;
            margin: 30px 0 20px 0;
            padding-bottom: 10px;
            border-bottom: 2px solid #667eea;
        }
        
        .footer {
            background: #f8f9fa;
            padding: 20px 40px;
            text-align: center;
            border-top: 2px solid #e9ecef;
            color: #666;
            font-size: 0.9em;
        }
        
        .toc {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 30px;
        }
        
        .toc h3 {
            color: #667eea;
            margin-bottom: 15px;
        }
        
        .toc ul {
            list-style: none;
            columns: 2;
        }
        
        .toc li {
            padding: 5px 0;
            color: #666;
        }
        
        .toc li::before {
            content: "▸ ";
            color: #667eea;
            margin-right: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Bundle Script Analysis Report</h1>
            <p>Comprehensive Analysis of Support Bundle Scripts and Logs</p>
        </div>
EOF

# Add metadata
{
    echo "        <div class=\"meta-info\">"
    echo "            <div class=\"meta-item\">"
    echo "                <strong>Ticket ID</strong>"
    echo "                <span>$TICKET_ID</span>"
    echo "            </div>"
    echo "            <div class=\"meta-item\">"
    echo "                <strong>Generated</strong>"
    echo "                <span>$(date '+%Y-%m-%d %H:%M:%S')</span>"
    echo "            </div>"
    echo "            <div class=\"meta-item\">"
    echo "                <strong>Source Directory</strong>"
    echo "                <span>$BUNDLE_ANALYSIS_DIR</span>"
    echo "            </div>"
    echo "        </div>"
} >> "$REPORT_OUTPUT"

# Count bundles and scripts
BUNDLE_COUNT=$(find "$BUNDLE_ANALYSIS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
TOTAL_SCRIPTS=$(find "$BUNDLE_ANALYSIS_DIR" -name "*_output.txt" -o -name "*_analysis.txt" | wc -l)
TOTAL_REPORTS=$(find "$BUNDLE_ANALYSIS_DIR" -name "analysis_report.txt" | wc -l)

# Add summary statistics
{
    echo "        <div class=\"content\">"
    echo "            <h2 class=\"section-title\">Executive Summary</h2>"
    echo "            <div class=\"summary-stats\">"
    echo "                <div class=\"stat-card\">"
    echo "                    <h3>Bundles Analyzed</h3>"
    echo "                    <div class=\"number\">$BUNDLE_COUNT</div>"
    echo "                </div>"
    echo "                <div class=\"stat-card\">"
    echo "                    <h3>Scripts Executed</h3>"
    echo "                    <div class=\"number\">$TOTAL_SCRIPTS</div>"
    echo "                </div>"
    echo "                <div class=\"stat-card\">"
    echo "                    <h3>Analysis Reports</h3>"
    echo "                    <div class=\"number\">$TOTAL_REPORTS</div>"
    echo "                </div>"
    echo "            </div>"
} >> "$REPORT_OUTPUT"

# Add table of contents
{
    echo "            <div class=\"toc\">"
    echo "                <h3>Bundle Analysis Overview</h3>"
    echo "                <ul>"
} >> "$REPORT_OUTPUT"

# Process each bundle and add to report
for BUNDLE_DIR in "$BUNDLE_ANALYSIS_DIR"/*/; do
    [[ ! -d "$BUNDLE_DIR" ]] && continue
    
    BUNDLE_NAME=$(basename "$BUNDLE_DIR")
    echo "Processing bundle: $BUNDLE_NAME"
    
    {
        echo "                    <li><a href=\"#bundle-$BUNDLE_NAME\" style=\"color: #667eea; text-decoration: none;\">$BUNDLE_NAME</a></li>"
    } >> "$REPORT_OUTPUT"
done

{
    echo "                </ul>"
    echo "            </div>"
} >> "$REPORT_OUTPUT"

# Add detailed results for each bundle
for BUNDLE_DIR in "$BUNDLE_ANALYSIS_DIR"/*/; do
    [[ ! -d "$BUNDLE_DIR" ]] && continue
    
    BUNDLE_NAME=$(basename "$BUNDLE_DIR")
    
    {
        echo "            <div class=\"bundle-section\" id=\"bundle-$BUNDLE_NAME\">"
        echo "                <div class=\"bundle-title\">$BUNDLE_NAME</div>"
    } >> "$REPORT_OUTPUT"
    
    # Count scripts in this bundle
    BUNDLE_SCRIPTS=$(find "$BUNDLE_DIR" -type f \( -name "*_output.txt" -o -name "*_analysis.txt" \) | wc -l)
    
    {
        echo "                <div class=\"script-meta\">"
        echo "                    <span><strong>Scripts Executed:</strong> $BUNDLE_SCRIPTS</span>"
        echo "                    <span><strong>Analysis Date:</strong> $(date '+%Y-%m-%d')</span>"
        echo "                </div>"
    } >> "$REPORT_OUTPUT"
    
    # Add script results
    for OUTPUT_FILE in "$BUNDLE_DIR"/*_output.txt "$BUNDLE_DIR"/*_analysis.txt; do
        [[ ! -f "$OUTPUT_FILE" ]] && continue
        
        SCRIPT_FILE=$(basename "$OUTPUT_FILE")
        SCRIPT_NAME="${SCRIPT_FILE%_*.txt}"
        FILE_SIZE=$(du -h "$OUTPUT_FILE" | awk '{print $1}')
        LINE_COUNT=$(wc -l < "$OUTPUT_FILE")
        IS_SUCCESS=$([[ -s "$OUTPUT_FILE" ]] && echo "true" || echo "false")
        
        if [[ "$IS_SUCCESS" == "true" ]]; then
            STATUS_CLASS="success"
            STATUS_TEXT="Success"
        else
            STATUS_CLASS="failed"
            STATUS_TEXT="No Output"
        fi
        
        {
            echo "                <div class=\"script-result $STATUS_CLASS\">"
            echo "                    <div class=\"script-name\">$SCRIPT_NAME</div>"
            echo "                    <div class=\"script-meta\">"
            echo "                        <span><strong>Status:</strong> $STATUS_TEXT</span>"
            echo "                        <span><strong>Lines:</strong> $LINE_COUNT</span>"
            echo "                        <span><strong>Size:</strong> $FILE_SIZE</span>"
            echo "                    </div>"
        } >> "$REPORT_OUTPUT"
        
        # Add truncated output preview
        if [[ "$IS_SUCCESS" == "true" ]] && [[ $LINE_COUNT -gt 0 ]]; then
            {
                echo "                    <div class=\"script-output\">"
                head -50 "$OUTPUT_FILE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
                if [[ $LINE_COUNT -gt 50 ]]; then
                    echo ""
                    echo "... ($(($LINE_COUNT - 50)) more lines) ..."
                fi
                echo "                    </div>"
            } >> "$REPORT_OUTPUT"
        fi
        
        {
            echo "                </div>"
        } >> "$REPORT_OUTPUT"
    done
    
    {
        echo "            </div>"
    } >> "$REPORT_OUTPUT"
done

# Close HTML
{
    echo "        </div>"
    echo "        <div class=\"footer\">"
    echo "            <p>Report generated on $(date '+%Y-%m-%d %H:%M:%S')</p>"
    echo "            <p>Source: $BUNDLE_ANALYSIS_DIR</p>"
    echo "        </div>"
    echo "    </div>"
    echo "</body>"
    echo "</html>"
} >> "$REPORT_OUTPUT"

echo ""
echo "✅ Comprehensive report generated!"
echo ""
echo "📊 Report Details:"
echo "   📁 Bundles Analyzed: $BUNDLE_COUNT"
echo "   ⚙️  Scripts Executed: $TOTAL_SCRIPTS"
echo "   📄 Analysis Reports: $TOTAL_REPORTS"
echo ""
echo "📄 Output File: $REPORT_OUTPUT"
echo ""
echo "To view the report:"
echo "   open \"$REPORT_OUTPUT\""
echo "   # or"
echo "   cat \"$REPORT_OUTPUT\" | less"
echo ""

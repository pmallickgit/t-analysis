#!/bin/bash

# Master Dashboard Generator
# Executes all analysis scripts and combines outputs into a single dashboard

echo "🚀 Starting Master Dashboard Generation..."
echo "=========================================="
echo ""

# Clean up old HTML dashboard files
echo "🧹 Cleaning up old dashboard files..."
rm -f *_dashboard.html 2>/dev/null
rm -f top15_processes_table.html 2>/dev/null
rm -f *_table.html 2>/dev/null
rm -f bind_analysis.html 2>/dev/null
rm -f metrics_*.html 2>/dev/null
echo "   ✅ Old dashboard files removed"
echo ""

# List of analysis scripts to execute (excluding infoblox_analysis.sh)
SCRIPTS=(
    "cpu_analysis.sh"
    "mem_analysis.sh"
    "disk_analysis.sh"
    "net_analysis.sh"
    "top_analysis.sh"
    "smaps_analysis.sh"
    "bind_chr_analysis.sh"
    "vdca_chr_analysis.sh"
    "fpcpu_analsyis.sh"
    "fpdtob_analysis.sh"
    "fpmbuf_analysis.sh"
    "fpports_analysis.sh"
    "fprrstat_analysis.sh"
    "fptcpdcastat_analysis.sh"
)

# Execute each script
echo "📊 Executing analysis scripts..."
echo ""

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo "▶️  Running $script..."
        bash "$script" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "   ✅ Completed successfully"
        else
            echo "   ⚠️  Completed with warnings"
        fi
    else
        echo "   ⏭️  Skipping $script (not found)"
    fi
done

echo ""
echo "🎨 Generating unified dashboard..."
echo ""

# Create unified dashboard with Python
python3 << 'PYTHON_SCRIPT'
import os
import re
from datetime import datetime

# Dashboard sections mapping
sections = {
    'cpu_analysis.sh': {'title': 'CPU Analysis', 'html_files': ['cpu_usage_dashboard.html'], 'icon': '🔥'},
    'mem_analysis.sh': {'title': 'Memory Analysis', 'html_files': ['mem_dashboard.html'], 'icon': '💾'},
    'disk_analysis.sh': {'title': 'Disk Analysis', 'html_files': ['disk_usage_dashboard.html'], 'icon': '💿'},
    'net_analysis.sh': {'title': 'Network Analysis', 'html_files': ['net_usage_dashboard.html'], 'icon': '🌐'},
    'top_analysis.sh': {'title': 'Top Processes', 'html_files': ['top_processes_dashboard.html', 'top15_processes_table.html'], 'icon': '📊'},
    'smaps_analysis.sh': {'title': 'SMAPS Memory Analysis (Top 5)', 'html_files': ['smaps_dashboard.html'], 'icon': '🧠'},
    'bind_chr_analysis.sh': {'title': 'BIND CHR Analysis', 'html_files': ['bind_chr_dashboard.html', 'bind_analysis.html'], 'icon': '🔗'},
    'vdca_chr_analysis.sh': {'title': 'VDCA CHR Analysis', 'html_files': ['vdca_chr_dashboard.html', 'vdca_chr_table.html'], 'icon': '📡'},
    'fpcpu_analsyis.sh': {'title': 'FP CPU Analysis', 'html_files': ['fpcpu_usage_dashboard.html', 'fpcpu_dashboard.html'], 'icon': '⚡'},
    'fpdtob_analysis.sh': {'title': 'FP DTOB Analysis', 'html_files': ['fpdtob_dashboard.html'], 'icon': '📈'},
    'fpmbuf_analysis.sh': {'title': 'FP MBUF Analysis', 'html_files': ['fpmbuf_dashboard.html'], 'icon': '📦'},
    'fpports_analysis.sh': {'title': 'FP Ports Analysis', 'html_files': ['port_usage_dashboard.html', 'fpports_dashboard.html'], 'icon': '🔌'},
    'fprrstat_analysis.sh': {'title': 'FP RR Stat Analysis', 'html_files': ['fprrstat_dashboard.html'], 'icon': '📉'},
    'fptcpdcastat_analysis.sh': {'title': 'FP TCP DCA Stat', 'html_files': ['fptcpdcastat_dashboard.html'], 'icon': '🔄'},
}

# Also check for metrics_named.html
if os.path.exists('metrics_named.html'):
    sections['metrics'] = {'title': 'Named Metrics', 'html_files': ['metrics_named.html'], 'icon': '📊'}

def extract_body_content(html_file):
    """Extract content from HTML file with styles preserved"""
    try:
        with open(html_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            # Check if file is essentially empty or has minimal content
            if len(content.strip()) < 100:
                return create_empty_state_message()
            
            # Extract styles from head section
            styles = ''
            style_matches = re.findall(r'<style[^>]*>(.*?)</style>', content, re.DOTALL | re.IGNORECASE)
            if style_matches:
                # Wrap styles in a scoped style tag
                styles = '<style>' + '\n'.join(style_matches) + '</style>\n'
            
            # Extract scripts if any
            scripts = ''
            script_matches = re.findall(r'<script[^>]*>(.*?)</script>', content, re.DOTALL | re.IGNORECASE)
            if script_matches:
                scripts = '\n' + ''.join(['<script>' + s + '</script>' for s in script_matches])
            
            # Try to extract body content
            body_match = re.search(r'<body[^>]*>(.*)</body>', content, re.DOTALL | re.IGNORECASE)
            if body_match:
                return styles + body_match.group(1) + scripts
            
            # If no body tag, look for main content
            container_match = re.search(r'<div[^>]*class=["\']container["\'][^>]*>(.*?)</div>(?=\s*</body>|$)', content, re.DOTALL | re.IGNORECASE)
            if container_match:
                return styles + container_match.group(1) + scripts
            
            # Return whole content if can't find specific sections
            return content
    except Exception as e:
        return f'<p style="color: red;">Error loading {html_file}: {str(e)}</p>'

def create_empty_state_message():
    """Create an aesthetic empty state message"""
    return '''
    <div style="
        text-align: center;
        padding: 80px 40px;
        background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
        border-radius: 16px;
        margin: 20px 0;
        box-shadow: inset 0 2px 10px rgba(0,0,0,0.05);
    ">
        <div style="
            font-size: 72px;
            margin-bottom: 20px;
            opacity: 0.3;
        ">📊</div>
        <h3 style="
            font-size: 24px;
            color: #64748b;
            margin-bottom: 12px;
            font-weight: 600;
        ">No Data Available</h3>
        <p style="
            font-size: 16px;
            color: #94a3b8;
            max-width: 500px;
            margin: 0 auto;
            line-height: 1.6;
        ">This section is currently empty or data collection is in progress. Please check back later or verify the data source.</p>
    </div>
    '''

def generate_summary_report():
    """Generate a comprehensive summary report from all analysis data"""
    import pandas as pd
    import numpy as np
    
    summary_html = '''
    <style>
        .summary-container {
            padding: 20px;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            border-radius: 12px;
            margin: 20px 0;
        }
        .summary-header {
            text-align: center;
            margin-bottom: 30px;
        }
        .summary-header h2 {
            color: #2C3E50;
            font-size: 32px;
            margin-bottom: 10px;
        }
        .summary-header p {
            color: #7F8C8D;
            font-size: 16px;
        }
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }
        .summary-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 4px 20px rgba(0,0,0,0.15);
        }
        .summary-card-title {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 15px;
            font-size: 18px;
            font-weight: 600;
            color: #2C3E50;
        }
        .summary-card-icon {
            font-size: 24px;
        }
        .summary-metric {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #ECF0F1;
        }
        .summary-metric:last-child {
            border-bottom: none;
        }
        .summary-metric-label {
            color: #7F8C8D;
            font-size: 14px;
        }
        .summary-metric-value {
            color: #2C3E50;
            font-weight: 600;
            font-size: 14px;
        }
        .alert-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
            margin-left: 8px;
        }
        .alert-high {
            background: #e74c3c;
            color: white;
        }
        .alert-medium {
            background: #f39c12;
            color: white;
        }
        .alert-low {
            background: #27ae60;
            color: white;
        }
    </style>
    <div class="summary-container">
        <div class="summary-header">
            <h2>📊 System Analysis Summary Report</h2>
            <p>Generated on ''' + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + '''</p>
        </div>
        <div class="summary-grid">
    '''
    
    # CPU Summary
    try:
        if os.path.exists('all_cpu_data.csv'):
            df = pd.read_csv('all_cpu_data.csv')
            # Filter out summary cpu rows
            df_filtered = df[df['cpu'] != 'cpu'] if 'cpu' in df.columns else df
            cpu_count = df_filtered['cpu'].nunique()
            # Check which column exists for usage
            usage_col = 'u' if 'u' in df_filtered.columns else 'use_pct'
            if usage_col in df_filtered.columns:
                df_filtered[usage_col] = pd.to_numeric(df_filtered[usage_col], errors='coerce')
                avg_usage = df_filtered[usage_col].mean()
                max_usage = df_filtered[usage_col].max()
                alert_level = 'HIGH' if max_usage > 80 else 'MEDIUM' if max_usage > 60 else 'LOW'
                alert_class = 'alert-high' if max_usage > 80 else 'alert-medium' if max_usage > 60 else 'alert-low'
                
                summary_html += f'''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">🔥</span>
                    <span>CPU Analysis</span>
                    <span class="alert-badge {alert_class}">{alert_level}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Total CPUs</span>
                    <span class="summary-metric-value">{cpu_count}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Avg Usage</span>
                    <span class="summary-metric-value">{avg_usage:.2f}%</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Peak Usage</span>
                    <span class="summary-metric-value">{max_usage:.2f}%</span>
                </div>
            </div>
                '''
    except Exception as e:
        pass
    
    # Memory Summary
    try:
        if os.path.exists('mem_dashboard.html'):
            summary_html += '''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">💾</span>
                    <span>Memory Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Status</span>
                    <span class="summary-metric-value">✓ Data Available</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # Disk Summary
    try:
        if os.path.exists('all_disk_data.csv'):
            df = pd.read_csv('all_disk_data.csv')
            # Check different possible column names
            disk_col = 'disk_name' if 'disk_name' in df.columns else 'disk'
            disk_count = df[disk_col].nunique()
            
            # Calculate IOPS from available columns
            read_col = 'read_iops' if 'read_iops' in df.columns else 'rps'
            write_col = 'write_iops' if 'write_iops' in df.columns else 'wps'
            
            if read_col in df.columns and write_col in df.columns:
                df[read_col] = pd.to_numeric(df[read_col], errors='coerce')
                df[write_col] = pd.to_numeric(df[write_col], errors='coerce')
                avg_iops = df[read_col].mean() + df[write_col].mean()
            else:
                avg_iops = 0
            
            summary_html += f'''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">💿</span>
                    <span>Disk Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Total Disks</span>
                    <span class="summary-metric-value">{disk_count}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Avg IOPS</span>
                    <span class="summary-metric-value">{avg_iops:.0f}</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # Top Processes Summary
    try:
        if os.path.exists('all_top_data.csv'):
            df = pd.read_csv('all_top_data.csv')
            # Check for different column names
            process_col = 'process_name' if 'process_name' in df.columns else 'process'
            process_count = df[process_col].nunique()
            
            # Get top CPU consuming process
            if 'cpu_use_pct' in df.columns and not df.empty:
                df['cpu_use_pct'] = pd.to_numeric(df['cpu_use_pct'], errors='coerce')
                top_process = df.groupby(process_col)['cpu_use_pct'].mean().idxmax()
                top_cpu = df.groupby(process_col)['cpu_use_pct'].mean().max()
            else:
                top_process = 'N/A'
                top_cpu = 0
            
            # Truncate long process names
            display_name = top_process if len(top_process) <= 25 else top_process[:25] + '...'
            
            summary_html += f'''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">📊</span>
                    <span>Top Processes</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Tracked Processes</span>
                    <span class="summary-metric-value">{process_count}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Top Consumer</span>
                    <span class="summary-metric-value" title="{top_process}">{display_name}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Avg CPU</span>
                    <span class="summary-metric-value">{top_cpu:.2f}%</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # FP CPU Summary
    try:
        if os.path.exists('all_fpcpu_data.csv'):
            df = pd.read_csv('all_fpcpu_data.csv')
            fpcpu_count = df['cpu'].nunique()
            avg_usage = df['u'].mean()
            
            summary_html += f'''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">⚡</span>
                    <span>Fastpath CPU</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">FP CPUs</span>
                    <span class="summary-metric-value">{fpcpu_count}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Avg Usage</span>
                    <span class="summary-metric-value">{avg_usage:.2f}%</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # Network Analysis Summary
    try:
        if os.path.exists('net_usage_dashboard.html'):
            summary_html += '''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">🌐</span>
                    <span>Network Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Status</span>
                    <span class="summary-metric-value">✓ Visualization Available</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # SMAPS Memory Analysis Summary
    try:
        if os.path.exists('all_process_data.csv'):
            df = pd.read_csv('all_process_data.csv')
            process_count = df['command'].nunique() if 'command' in df.columns else 0
            if 'rss' in df.columns:
                df['rss'] = pd.to_numeric(df['rss'], errors='coerce')
                total_rss_mb = df['rss'].sum() / (1024 * 1024) if not df.empty else 0
                top_process = df.groupby('command')['rss'].mean().idxmax() if not df.empty else 'N/A'
                top_process_display = top_process[:25] + '...' if len(top_process) > 25 else top_process
            else:
                total_rss_mb = 0
                top_process_display = 'N/A'
            
            summary_html += f'''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">🧠</span>
                    <span>SMAPS Memory</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Tracked Processes</span>
                    <span class="summary-metric-value">{process_count}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Total RSS</span>
                    <span class="summary-metric-value">{total_rss_mb:.0f} MB</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Top Consumer</span>
                    <span class="summary-metric-value" title="{top_process}">{top_process_display}</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # BIND CHR Analysis Summary
    try:
        if os.path.exists('bind_chr_dashboard.html'):
            summary_html += '''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">🔗</span>
                    <span>BIND CHR Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Status</span>
                    <span class="summary-metric-value">✓ Cache Metrics Available</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # VDCA CHR Analysis Summary
    try:
        if os.path.exists('vdca_chr_dashboard.html'):
            summary_html += '''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">📡</span>
                    <span>VDCA CHR Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Status</span>
                    <span class="summary-metric-value">✓ Cache Metrics Available</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # FP DTOB Analysis Summary
    try:
        if os.path.exists('fpdtob_dashboard.html'):
            summary_html += '''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">📈</span>
                    <span>FP DTOB Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Status</span>
                    <span class="summary-metric-value">✓ Traffic Metrics Available</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # FP MBUF Analysis Summary
    try:
        if os.path.exists('fpmbuf_dashboard.html'):
            summary_html += '''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">📦</span>
                    <span>FP MBUF Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Status</span>
                    <span class="summary-metric-value">✓ Buffer Metrics Available</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # FP Ports Analysis Summary
    try:
        if os.path.exists('all_foports_data.csv'):
            df = pd.read_csv('all_foports_data.csv')
            port_count = df['port'].nunique() if 'port' in df.columns else 0
            
            # Calculate total packets if available
            if 'ip_qps' in df.columns and 'op_qps' in df.columns:
                df['ip_qps'] = pd.to_numeric(df['ip_qps'], errors='coerce')
                df['op_qps'] = pd.to_numeric(df['op_qps'], errors='coerce')
                avg_in_pps = df['ip_qps'].mean()
                avg_out_pps = df['op_qps'].mean()
            else:
                avg_in_pps = 0
                avg_out_pps = 0
            
            summary_html += f'''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">🔌</span>
                    <span>FP Ports Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Total Ports</span>
                    <span class="summary-metric-value">{port_count}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Avg In PPS</span>
                    <span class="summary-metric-value">{avg_in_pps:.0f}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Avg Out PPS</span>
                    <span class="summary-metric-value">{avg_out_pps:.0f}</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # FP RR Stat Analysis Summary
    try:
        if os.path.exists('fprrstat_dashboard.html'):
            summary_html += '''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">📉</span>
                    <span>FP RR Stat Analysis</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Status</span>
                    <span class="summary-metric-value">✓ DNS RRSet Metrics Available</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    # FP TCP DCA Stat Summary
    try:
        if os.path.exists('all_fptcpdcastat_data.csv'):
            df = pd.read_csv('all_fptcpdcastat_data.csv')
            ip_count = df['ip'].nunique() if 'ip' in df.columns else 0
            
            # Get connection stats if available
            if 'cs' in df.columns:
                df['cs'] = pd.to_numeric(df['cs'], errors='coerce')
                total_connections = df['cs'].sum()
            else:
                total_connections = 0
            
            summary_html += f'''
            <div class="summary-card">
                <div class="summary-card-title">
                    <span class="summary-card-icon">🔄</span>
                    <span>FP TCP DCA Stat</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Tracked IPs</span>
                    <span class="summary-metric-value">{ip_count}</span>
                </div>
                <div class="summary-metric">
                    <span class="summary-metric-label">Total Connections</span>
                    <span class="summary-metric-value">{total_connections:.0f}</span>
                </div>
            </div>
            '''
    except Exception as e:
        pass
    
    summary_html += '''
        </div>
        <div style="text-align: center; color: #7F8C8D; font-size: 14px; margin-top: 20px;">
            <p>💡 Click on any section header below to view detailed analysis</p>
        </div>
    </div>
    '''
    
    return summary_html

# Collect all available sections
available_sections = []

# Add summary report as first section
summary_content = generate_summary_report()
available_sections.append({
    'id': 'summary_report',
    'title': 'Executive Summary',
    'icon': '📋',
    'content': summary_content,
    'file': 'summary_report',
    'expanded': True  # Keep this section expanded by default
})
for script, config in sections.items():
    for html_file in config['html_files']:
        if os.path.exists(html_file):
            available_sections.append({
                'id': script.replace('.sh', '').replace('.', '_'),
                'title': config['title'],
                'icon': config['icon'],
                'content': extract_body_content(html_file),
                'file': html_file
            })
            break  # Use first available file

# Generate unified HTML dashboard
html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Unified System Analysis Dashboard</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(20px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}
        html {{
            scroll-behavior: smooth;
        }}
        body {{
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            background-attachment: fixed;
            color: #2c3e50;
            min-height: 100vh;
            padding: 20px;
        }}
        body::before {{
            content: '';
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: 
                radial-gradient(circle at 20% 50%, rgba(120, 119, 198, 0.3) 0%, transparent 50%),
                radial-gradient(circle at 80% 80%, rgba(252, 136, 102, 0.3) 0%, transparent 50%);
            pointer-events: none;
            z-index: 0;
        }}
        .main-container {{
            max-width: 100%;
            margin: 0 auto;
            position: relative;
            z-index: 1;
        }}
        .header {{
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            padding: 30px 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            margin-bottom: 30px;
            animation: fadeIn 0.6s ease-out;
            max-width: 1600px;
            margin-left: auto;
            margin-right: auto;
        }}
        h1 {{
            font-size: 42px;
            font-weight: 800;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            text-align: center;
            margin-bottom: 10px;
        }}
        .subtitle {{
            text-align: center;
            color: #7f8c8d;
            font-size: 16px;
            font-weight: 500;
        }}
        .info-banner {{
            background: linear-gradient(135deg, #e8f4f8 0%, #f0f8ff 100%);
            border-left: 5px solid #667eea;
            padding: 20px 25px;
            margin-bottom: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.1);
            max-width: 1600px;
            margin-left: auto;
            margin-right: auto;
        }}
        .info-banner p {{
            margin: 8px 0;
            color: #2c3e50;
            font-size: 14px;
            line-height: 1.6;
        }}
        .section-container {{
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            margin-bottom: 30px;
            animation: fadeIn 0.6s ease-out;
            max-width: 100%;
            overflow: visible;
        }}
        .section-header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
            overflow: hidden;
        }}
        .section-header::before {{
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255,255,255,0.2), transparent);
            transition: left 0.5s ease;
        }}
        .section-header:hover::before {{
            left: 100%;
        }}
        .section-header:hover {{
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.4);
        }}
        .section-header:active {{
            transform: translateY(0);
        }}
        .section-title {{
            font-size: 28px;
            font-weight: 700;
            margin: 0;
        }}
        .section-toggle {{
            font-size: 24px;
            font-weight: bold;
            transition: transform 0.3s ease;
        }}
        .section-toggle.collapsed {{
            transform: rotate(-90deg);
        }}
        .section-content {{
            display: block;
            animation: fadeIn 0.4s ease-out;
            overflow-x: auto;
            width: 100%;
        }}
        .section-content.collapsed {{
            display: none;
        }}
        .footer {{
            text-align: center;
            color: white;
            margin-top: 30px;
            padding: 20px;
            font-size: 14px;
            opacity: 0.9;
        }}
        /* Quick Navigation Menu */
        .nav-toggle {{
            position: fixed;
            bottom: 100px;
            right: 30px;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            font-size: 20px;
            cursor: pointer;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            z-index: 1001;
            display: flex;
            align-items: center;
            justify-content: center;
        }}
        .nav-toggle:hover {{
            transform: translateY(-5px) scale(1.05);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.5);
        }}
        .nav-menu {{
            position: fixed;
            bottom: 160px;
            right: 30px;
            background: rgba(255, 255, 255, 0.98);
            backdrop-filter: blur(10px);
            border-radius: 16px;
            padding: 20px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
            max-width: 300px;
            max-height: 500px;
            overflow-y: auto;
            z-index: 1001;
            opacity: 0;
            transform: translateY(20px) scale(0.9);
            pointer-events: none;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }}
        .nav-menu.active {{
            opacity: 1;
            transform: translateY(0) scale(1);
            pointer-events: auto;
        }}
        .nav-menu h3 {{
            margin: 0 0 15px 0;
            font-size: 18px;
            color: #2c3e50;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }}
        .nav-menu a {{
            display: flex;
            align-items: center;
            padding: 10px 12px;
            margin: 5px 0;
            border-radius: 8px;
            text-decoration: none;
            color: #2c3e50;
            font-size: 14px;
            transition: all 0.2s ease;
            background: rgba(102, 126, 234, 0.05);
        }}
        .nav-menu a:hover {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            transform: translateX(5px);
        }}
        .nav-menu a span {{
            margin-right: 8px;
        }}
        /* Global font override for consistency across all sections */
        .section-content,
        .section-content *,
        .section-content body,
        .section-content table,
        .section-content th,
        .section-content td,
        .section-content p,
        .section-content div,
        .section-content span,
        .section-content h1,
        .section-content h2,
        .section-content h3,
        .section-content h4,
        .section-content h5,
        .section-content h6 {{
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif !important;
        }}
        /* Ensure Plotly graphs use consistent font */
        .section-content .plotly .gtitle,
        .section-content .plotly text,
        .section-content svg text {{
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif !important;
        }}
        /* Ensure images and canvases are responsive */
        .section-container img {{
            max-width: 100%;
            height: auto;
        }}
        .section-container canvas {{
            max-width: 100% !important;
        }}
        /* Override nested container styles */
        .section-container .container {{
            max-width: 100%;
            background: transparent;
            padding: 0;
            box-shadow: none;
        }}
        /* Ensure embedded content maintains proper sizing */
        .section-content > div {{
            max-width: 100%;
            overflow-x: auto;
        }}
        /* Export button styling */
        .export-btn {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            margin: 10px 0;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            box-shadow: 0 2px 8px rgba(102, 126, 234, 0.3);
            transition: all 0.3s ease;
        }}
        .export-btn:hover {{
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
        }}
        .export-btn:active {{
            transform: translateY(0);
        }}
        .table-wrapper {{
            position: relative;
            margin: 20px 0;
        }}
        .table-controls {{
            display: flex;
            justify-content: flex-end;
            margin-bottom: 10px;
            gap: 10px;
        }}
    </style>
</head>
<body>
    <div class="main-container">
        <div class="header">
            <h1>📊 Unified System Analysis Dashboard</h1>
            <p class="subtitle">Comprehensive System Diagnostics & Performance Analysis</p>
            <p class="subtitle" style="margin-top: 5px; font-size: 14px;">Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>

        <div class="info-banner">
            <p><strong>📋 Dashboard Overview:</strong> This unified dashboard combines data from {len(available_sections)} analysis modules.</p>
            <p><strong>🔍 Navigation:</strong> Scroll through sections below or use the quick navigation menu (📑 button). Click section headers to collapse/expand.</p>
            <p><strong>💾 Export:</strong> Click "Export CSV" buttons above tables to download data.</p>
        </div>

        <!-- Quick Navigation Menu -->
        <button class="nav-toggle" onclick="toggleNavMenu()" title="Quick Navigation">
            📑
        </button>
        <div class="nav-menu" id="navMenu">
            <h3>📑 Quick Navigation</h3>
"""

# Add navigation links
html_content += "\n"
for i, section in enumerate(available_sections):
    html_content += f"            <a href=\"#section-container-{i}\" onclick=\"closeNavMenu(); return true;\"><span>{section['icon']}</span>{section['title']}</a>\n"

html_content += """        </div>
"""

# Add content sections (all stacked vertically)
for i, section in enumerate(available_sections):
    # Check if section should be expanded by default
    is_expanded = section.get('expanded', False)
    toggle_class = '' if is_expanded else 'collapsed'
    content_class = '' if is_expanded else 'collapsed'
    
    html_content += f"""
        <div class="section-container" id="section-container-{i}">
            <div class="section-header" onclick="toggleSection('section-{i}')">
                <h2 class="section-title">{section['icon']} {section['title']}</h2>
                <span class="section-toggle {toggle_class}" id="toggle-{i}">▼</span>
            </div>
            <div class="section-content {content_class}" id="section-{i}">
                {section['content']}
            </div>
        </div>
"""

html_content += """
        <div class="footer">
            <p>🔧 System Analysis Dashboard | Generated from {num_sections} analysis modules</p>
        </div>
    </div>

    <script>
        // Toggle section visibility
        function toggleSection(sectionId) {
            const content = document.getElementById(sectionId);
            const toggleIcon = document.getElementById('toggle-' + sectionId.split('-')[1]);
            
            if (content.classList.contains('collapsed')) {
                content.classList.remove('collapsed');
                toggleIcon.classList.remove('collapsed');
                
                // Resize Plotly graphs when section is expanded
                setTimeout(function() {
                    const plotlyDivs = content.querySelectorAll('.plotly-graph-div');
                    plotlyDivs.forEach(function(div) {
                        if (window.Plotly) {
                            window.Plotly.Plots.resize(div);
                        }
                    });
                }, 100);
            } else {
                content.classList.add('collapsed');
                toggleIcon.classList.add('collapsed');
            }
        }

        // Toggle navigation menu
        function toggleNavMenu() {
            const navMenu = document.getElementById('navMenu');
            navMenu.classList.toggle('active');
        }

        // Close navigation menu
        function closeNavMenu() {
            const navMenu = document.getElementById('navMenu');
            navMenu.classList.remove('active');
        }

        // Close nav menu when clicking outside
        document.addEventListener('click', function(e) {
            const navMenu = document.getElementById('navMenu');
            const navToggle = document.querySelector('.nav-toggle');
            if (!navMenu.contains(e.target) && !navToggle.contains(e.target)) {
                closeNavMenu();
            }
        });

        // Export table to CSV
        function exportTableToCSV(tableId, filename) {
            const table = document.getElementById(tableId);
            if (!table) return;
            
            const rows = table.querySelectorAll('tr');
            let csv = [];
            
            for (let row of rows) {
                let cols = row.querySelectorAll('td, th');
                let csvRow = [];
                for (let col of cols) {
                    // Get text content and clean it
                    let text = col.textContent.trim();
                    // Escape quotes and wrap in quotes if contains comma
                    text = text.replace(/"/g, '""');
                    if (text.includes(',') || text.includes('\\n') || text.includes('"')) {
                        text = '"' + text + '"';
                    }
                    csvRow.push(text);
                }
                csv.push(csvRow.join(','));
            }
            
            // Create blob and download
            const csvContent = csv.join('\\n');
            const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            const url = URL.createObjectURL(blob);
            
            link.setAttribute('href', url);
            link.setAttribute('download', filename);
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }

        // Add export buttons to all tables
        function addExportButtons() {
            const tables = document.querySelectorAll('.section-content table');
            let tableCounter = 0;
            
            tables.forEach((table, index) => {
                // Skip if already has an ID
                if (!table.id) {
                    table.id = 'data-table-' + tableCounter;
                }
                const tableId = table.id;
                tableCounter++;
                
                // Skip very small tables (likely not data tables)
                const rows = table.querySelectorAll('tr');
                if (rows.length < 2) return;
                
                // Create wrapper if not exists
                if (!table.parentElement.classList.contains('table-wrapper')) {
                    const wrapper = document.createElement('div');
                    wrapper.className = 'table-wrapper';
                    table.parentNode.insertBefore(wrapper, table);
                    wrapper.appendChild(table);
                }
                
                // Check if export button already exists
                const existingControls = table.parentElement.querySelector('.table-controls');
                if (existingControls) return;
                
                // Create controls container
                const controls = document.createElement('div');
                controls.className = 'table-controls';
                
                // Create export button
                const exportBtn = document.createElement('button');
                exportBtn.className = 'export-btn';
                exportBtn.innerHTML = '📥 Export CSV';
                
                // Get section title for filename
                const section = table.closest('.section-content');
                const sectionTitle = section ? section.previousElementSibling.querySelector('.section-title').textContent.trim() : 'table';
                const filename = sectionTitle.replace(/[^a-z0-9]/gi, '_').toLowerCase() + '_table_' + tableCounter + '.csv';
                
                exportBtn.onclick = () => exportTableToCSV(tableId, filename);
                
                controls.appendChild(exportBtn);
                table.parentElement.insertBefore(controls, table);
            });
        }

        // Initialize export buttons when page loads
        document.addEventListener('DOMContentLoaded', function() {
            addExportButtons();
        });

        // Re-add export buttons when sections are toggled (in case content is dynamic)
        document.addEventListener('click', function(e) {
            if (e.target.closest('.section-header')) {
                setTimeout(addExportButtons, 100);
            }
        });

        // Scroll to top button
        const scrollBtn = document.createElement('button');
        scrollBtn.innerHTML = '↑';
        scrollBtn.style.cssText = `
            position: fixed;
            bottom: 30px;
            right: 30px;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            font-size: 24px;
            cursor: pointer;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
            opacity: 0;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            z-index: 1000;
            pointer-events: none;
        `;
        document.body.appendChild(scrollBtn);

        window.addEventListener('scroll', function() {
            if (window.pageYOffset > 300) {
                scrollBtn.style.opacity = '1';
                scrollBtn.style.pointerEvents = 'auto';
            } else {
                scrollBtn.style.opacity = '0';
                scrollBtn.style.pointerEvents = 'none';
            }
        });

        scrollBtn.addEventListener('click', function() {
            window.scrollTo({ top: 0, behavior: 'smooth' });
        });

        scrollBtn.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-5px)';
            this.style.boxShadow = '0 6px 20px rgba(102, 126, 234, 0.5)';
        });

        scrollBtn.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0)';
            this.style.boxShadow = '0 4px 15px rgba(102, 126, 234, 0.4)';
        });

        // Smooth scroll for section headers
        document.querySelectorAll('.section-header').forEach(header => {
            header.addEventListener('click', function() {
                setTimeout(() => {
                    this.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }, 100);
            });
        });

        // Add loading animation for sections
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.style.opacity = '1';
                    entry.target.style.transform = 'translateY(0)';
                }
            });
        }, { threshold: 0.1 });

        document.querySelectorAll('.section-container').forEach((section, index) => {
            section.style.opacity = '0';
            section.style.transform = 'translateY(30px)';
            section.style.transition = `all 0.6s ease-out ${index * 0.1}s`;
            observer.observe(section);
        });
    </script>
</body>
</html>
""".replace('{num_sections}', str(len(available_sections)))

# Write dashboard
with open('master_dashboard.html', 'w', encoding='utf-8') as f:
    f.write(html_content)

print(f"✅ Generated master dashboard with {len(available_sections)} sections")
print(f"   Sections included:")
for section in available_sections:
    print(f"   • {section['icon']} {section['title']} (from {section['file']})")

PYTHON_SCRIPT

echo ""
echo "=========================================="
echo "✅ Master Dashboard Generation Complete!"
echo "=========================================="
echo ""
echo "📄 Output: master_dashboard.html"
echo ""
echo "🌐 Open in browser to view unified analysis"
echo ""

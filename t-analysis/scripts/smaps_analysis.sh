#!/bin/bash

SMAPS_PY='smaps_data.py'
OUTPUT_HTML='smaps_dashboard.html'

echo "🔍 Analyzing SMAPS data for top 5 processes by Swap + Private memory..."

# Start the python script
cat <<'PYTHON_EOF' > ${SMAPS_PY}
import glob
import re
import sys
import pandas as pd
from datetime import datetime
import plotly.graph_objects as go
from plotly.subplots import make_subplots

pd.set_option('display.max_rows', None)
pd.set_option('display.max_columns', None)
pd.set_option('display.max_colwidth', None)

# Step 1: Read all ptop*.log files
log_files = sorted(glob.glob("ptop*.log"))

if not log_files:
    print("❌ No ptop*.log files found!")
    sys.exit(1)

print(f"📂 Found {len(log_files)} log files to process")

# Step 2: Parse TIME and SMAPS entries
records = []
current_time = None

for file in log_files:
    with open(file, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        for line in lines:
            if line.startswith("TIME"):
                parts = line.strip().split()
                if len(parts) >= 5:
                    current_time = f"{parts[3]} {parts[4]}"
            elif line.startswith("SMAPS") and current_time:
                match = re.match(
                    r"SMAPS (\d+) s/r/r-/sw (\d+) (\d+) (\d+) (\d+) s (\d+) (\d+) p (\d+) (\d+) sh (\d+) (\d+) h (\d+)  c (.+)",
                    line.strip()
                )
                if match:
                    pid = int(match.group(1))
                    size = int(match.group(2))
                    rss = int(match.group(3))
                    nrss = int(match.group(4))
                    swap = int(match.group(5))
                    shared_total = int(match.group(6))
                    shared_dirty = int(match.group(7))
                    private_total = int(match.group(8))
                    private_dirty = int(match.group(9))
                    shm_total = int(match.group(10))
                    shm_dirty = int(match.group(11))
                    hugepages = int(match.group(12))
                    command = match.group(13).strip()
                    
                    # Calculate swap + private memory
                    swap_plus_private = swap + private_total
                    
                    records.append({
                        "datetime": current_time,
                        "pid": pid,
                        "size": size,
                        "rss": rss,
                        "nrss": nrss,
                        "swap": swap,
                        "shared_total": shared_total,
                        "shared_dirty": shared_dirty,
                        "private_total": private_total,
                        "private_dirty": private_dirty,
                        "shm_total": shm_total,
                        "shm_dirty": shm_dirty,
                        "hugepages": hugepages,
                        "swap_plus_private": swap_plus_private,
                        "command": command
                    })

# Step 3: Create DataFrame
df = pd.DataFrame(records)
df['datetime'] = pd.to_datetime(df['datetime'])

print(f"📊 Processed {len(df)} SMAPS records")

# Save all data
df.to_csv('all_process_data.csv', index=False)

# Step 4: Find top 5 processes by average swap+private memory
df['process_name'] = df['command'].str.split().str[0]
avg_swap_private = df.groupby('process_name')['swap_plus_private'].mean().sort_values(ascending=False)
top5_processes = avg_swap_private.head(5).index.tolist()

print(f"\n🔝 Top 5 processes by Swap + Private memory:")
for i, proc in enumerate(top5_processes, 1):
    avg_mem = avg_swap_private[proc] / 1024  # Convert to MB
    print(f"   {i}. {proc}: {avg_mem:.2f} MB average")

# Step 5: Generate detailed graphs for each top 5 process
html_sections = []

# Define modern color palette
metric_colors = {
    'swap_plus_private': '#FF6B6B',
    'size': '#3366CC',
    'rss': '#DC3912',
    'nrss': '#FF9900',
    'swap': '#990099',
    'shared_total': '#109618',
    'shared_dirty': '#0099C6',
    'private_total': '#DD4477',
    'private_dirty': '#66AA00',
    'shm_total': '#B82E2E',
    'shm_dirty': '#316395',
    'hugepages': '#994499'
}

metric_names = {
    'swap_plus_private': 'Swap + Private Memory',
    'size': 'Virtual Size',
    'rss': 'RSS (Resident Set)',
    'nrss': 'Non-Resident Size',
    'swap': 'Swap Memory',
    'shared_total': 'Shared Total',
    'shared_dirty': 'Shared Dirty',
    'private_total': 'Private Total',
    'private_dirty': 'Private Dirty',
    'shm_total': 'Shared Memory Total',
    'shm_dirty': 'Shared Memory Dirty',
    'hugepages': 'Huge Pages'
}

# All metrics to plot
all_metrics = ['swap_plus_private', 'size', 'rss', 'nrss', 'swap', 'shared_total', 
               'shared_dirty', 'private_total', 'private_dirty', 'shm_total', 
               'shm_dirty', 'hugepages']

for idx, proc_name in enumerate(top5_processes):
    proc_df = df[df['process_name'] == proc_name].copy().sort_values('datetime')
    
    if proc_df.empty:
        continue
    
    # Sanitize process name for filename
    safe_proc_name = proc_name.replace('/', '_').replace(' ', '_')
    
    # Create a single comprehensive figure with all traces
    fig = go.Figure()
    
    for metric in all_metrics:
        fig.add_trace(go.Scatter(
            x=proc_df['datetime'],
            y=proc_df[metric] / 1024,  # Convert to MB
            mode='lines',
            name=metric_names.get(metric, metric),
            line=dict(
                color=metric_colors.get(metric, '#000000'),
                width=2.5,
                shape='spline'
            ),
            hovertemplate=f"<b>{metric_names.get(metric, metric)}</b><br>" +
                          "Time: %{x|%Y-%m-%d %H:%M:%S}<br>" +
                          "Value: %{y:.2f} MB<br>" +
                          "<extra></extra>"
        ))
    
    # Update layout with modern aesthetic
    fig.update_layout(
        title={
            'text': f"<b>Memory Metrics Over Time: {proc_name}</b><br><sub>PID variations: {', '.join(map(str, sorted(proc_df['pid'].unique())))}</sub>",
            'font': {'size': 22, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
            'x': 0.5,
            'xanchor': 'center',
            'y': 0.96,
            'yanchor': 'top'
        },
        xaxis_title="<b>Date & Time</b>",
        yaxis_title="<b>Memory (MB)</b>",
        height=500,
        width=900,  # Fixed width to allow table on the right
        plot_bgcolor='#FAFAFA',
        paper_bgcolor='#FFFFFF',
        font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
        xaxis=dict(
            type='date',
            showgrid=True,
            gridcolor='#E5E5E5',
            gridwidth=1,
            zeroline=False,
            title_font=dict(size=14, color='#34495E'),
            tickfont=dict(size=11, color='#34495E'),
            linecolor='#34495E',
            linewidth=1.5,
            mirror=True,
            ticks='outside',
            ticklen=5,
            tickcolor='#34495E'
        ),
        yaxis=dict(
            showgrid=True,
            gridcolor='#E5E5E5',
            gridwidth=1,
            zeroline=True,
            zerolinecolor='#CCCCCC',
            zerolinewidth=1.5,
            title_font=dict(size=14, color='#34495E'),
            tickfont=dict(size=11, color='#34495E'),
            linecolor='#34495E',
            linewidth=1.5,
            mirror=True,
            ticks='outside',
            ticklen=5,
            tickcolor='#34495E',
            tickformat=',.0f'
        ),
        legend=dict(
            title={'text': '<b>Memory Metrics</b>', 'font': {'size': 13}},
            orientation="h",
            yanchor="top",
            y=-0.15,
            xanchor="center",
            x=0.5,
            bgcolor='rgba(255, 255, 255, 0.95)',
            bordercolor='#CCCCCC',
            borderwidth=1,
            font=dict(size=11)
        ),
        hovermode="x unified",
        margin=dict(t=80, b=140, l=80, r=80)
    )
    
    # Generate statistics table for all metrics
    stats_data = []
    for metric in all_metrics:
        metric_values = proc_df[metric] / 1024  # Convert to MB
        stats_data.append({
            'Metric': metric_names.get(metric, metric),
            'Min (MB)': f"{metric_values.min():.2f}",
            'Max (MB)': f"{metric_values.max():.2f}",
            'Avg (MB)': f"{metric_values.mean():.2f}",
            'Current (MB)': f"{metric_values.iloc[-1]:.2f}"
        })
    
    # Build HTML table
    table_html = """
    <table id="metrics-stats-table">
        <thead>
            <tr>
                <th>Metric</th>
                <th>Min (MB)</th>
                <th>Max (MB)</th>
                <th>Avg (MB)</th>
                <th>Current (MB)</th>
            </tr>
        </thead>
        <tbody>
    """
    for stat in stats_data:
        table_html += f"""
            <tr>
                <td>{stat['Metric']}</td>
                <td>{stat['Min (MB)']}</td>
                <td>{stat['Max (MB)']}</td>
                <td>{stat['Avg (MB)']}</td>
                <td>{stat['Current (MB)']}</td>
            </tr>
        """
    table_html += """
        </tbody>
    </table>
    """
    
    # Get plotly graph HTML
    graph_html = fig.to_html(full_html=False, include_plotlyjs='cdn')
    
    # Create complete HTML with graph and table side by side
    complete_html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Memory Metrics: {proc_name}</title>
    <style>
        body {{
            font-family: 'Inter', Arial, sans-serif;
            margin: 20px;
            background: #f5f7fa;
        }}
        .container {{
            display: flex;
            gap: 20px;
            align-items: flex-start;
            flex-wrap: wrap;
        }}
        .graph-section {{
            flex: 1;
            min-width: 900px;
            background: white;
            padding: 20px;
            border-radius: 12px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }}
        .table-section {{
            flex: 0 0 450px;
            background: white;
            padding: 20px;
            border-radius: 12px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }}
        .table-section h3 {{
            margin-top: 0;
            color: #2C3E50;
            font-size: 18px;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }}
        th {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 12px 8px;
            text-align: left;
            font-weight: 600;
            font-size: 12px;
        }}
        td {{
            padding: 10px 8px;
            border-bottom: 1px solid #e0e0e0;
        }}
        tr:hover {{
            background-color: #f8f9ff;
        }}
        tr:last-child td {{
            border-bottom: none;
        }}
        @media (max-width: 1400px) {{
            .container {{
                flex-direction: column;
            }}
            .table-section {{
                flex: 1;
                min-width: 100%;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="graph-section">
            {graph_html}
        </div>
        <div class="table-section">
            <h3>📊 Memory Metrics Statistics</h3>
            {table_html}
        </div>
    </div>
</body>
</html>
    """
    
    html_file = f"metrics_{safe_proc_name}.html"
    with open(html_file, 'w') as f:
        f.write(complete_html)
    
    html_sections.append({
        'process': proc_name,
        'avg_memory': avg_swap_private[proc_name] / 1024,
        'max_memory': proc_df['swap_plus_private'].max() / 1024,
        'min_memory': proc_df['swap_plus_private'].min() / 1024,
        'samples': len(proc_df),
        'html_file': html_file
    })

# Step 6: Create combined dashboard HTML
html_content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SMAPS Memory Analysis Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Arial', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
        }
        .header {
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 30px;
            text-align: center;
        }
        h1 {
            color: #2C3E50;
            font-size: 36px;
            margin-bottom: 10px;
        }
        .subtitle {
            color: #7f8c8d;
            font-size: 16px;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 12px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .stat-card h3 {
            color: #FF6B6B;
            font-size: 18px;
            margin-bottom: 10px;
        }
        .stat-card .process-name {
            font-size: 24px;
            font-weight: bold;
            color: #2C3E50;
            margin-bottom: 15px;
        }
        .stat-row {
            display: flex;
            justify-content: space-between;
            padding: 5px 0;
            border-bottom: 1px solid #ecf0f1;
        }
        .stat-label {
            color: #7f8c8d;
            font-size: 14px;
        }
        .stat-value {
            color: #2C3E50;
            font-weight: 600;
            font-size: 14px;
        }
        .graph-section {
            background: white;
            padding: 20px;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 30px;
        }
        .graph-header {
            font-size: 20px;
            color: #2C3E50;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 3px solid #FF6B6B;
        }
        iframe {
            width: 100%;
            border: none;
            border-radius: 8px;
        }
        .footer {
            text-align: center;
            color: white;
            padding: 20px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 SMAPS Memory Analysis Dashboard</h1>
            <p class="subtitle">Top 5 Processes by Swap + Private Memory Usage</p>
            <p class="subtitle">Generated on """ + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """</p>
        </div>
        
        <div class="stats-grid">
"""

for i, section in enumerate(html_sections, 1):
    html_content += f"""
            <div class="stat-card">
                <h3>#{i} Process</h3>
                <div class="process-name">{section['process']}</div>
                <div class="stat-row">
                    <span class="stat-label">Average Memory:</span>
                    <span class="stat-value">{section['avg_memory']:.2f} MB</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Peak Memory:</span>
                    <span class="stat-value">{section['max_memory']:.2f} MB</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Minimum Memory:</span>
                    <span class="stat-value">{section['min_memory']:.2f} MB</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Data Points:</span>
                    <span class="stat-value">{section['samples']:,}</span>
                </div>
            </div>
"""

html_content += """
        </div>
"""

for i, section in enumerate(html_sections, 1):
    html_content += f"""
        <div class="graph-section">
            <div class="graph-header">
                #{i}. {section['process']} - Memory Usage Analysis
            </div>
            <iframe src="{section['html_file']}" height="600px"></iframe>
        </div>
"""

html_content += f"""
        <div class="footer">
            <p>🔧 SMAPS Analysis Dashboard | Analyzed {len(df)} total records</p>
            <p>Top 5 processes identified by highest average Swap + Private memory consumption</p>
        </div>
    </div>
</body>
</html>
"""

with open('smaps_dashboard.html', 'w', encoding='utf-8') as f:
    f.write(html_content)

print(f"\n✅ Generated smaps_dashboard.html with top 5 processes")
print(f"📁 Individual metrics files created for each process")
print(f"🎨 Dashboard ready for integration into master dashboard")

PYTHON_EOF

# Execute the Python script
python3 ${SMAPS_PY}

# Cleanup
rm -f ${SMAPS_PY}

echo ""
echo "=========================================="
echo "✅ SMAPS Analysis Complete!"
echo "=========================================="
echo ""
echo "📄 Output: smaps_dashboard.html"
echo ""

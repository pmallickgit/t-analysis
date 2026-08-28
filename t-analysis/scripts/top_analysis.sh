#!/bin/bash

TOP_PY='top_data.py'
TOP_LOG='top_data.csv'

# Start the python script
cat <<EOF > ${TOP_PY}
import glob
import os
import re
import sys
import pandas as pd
from datetime import datetime
import plotly.io as pio
import plotly.express as px
import plotly.subplots as sp
import plotly.graph_objects as go
import plotly.colors as pc
from plotly.subplots import make_subplots

pd.set_option('display.max_rows', None)
pd.set_option('display.max_columns', None)
pd.set_option('display.max_colwidth', None)

def read_log_files(directory_path, pattern):
    """Read and concatenate all log files matching the pattern in the directory."""
    log_files = sorted(glob.glob(os.path.join(directory_path, pattern)))
    raw_data = ""
    for file in log_files:
        with open(file, "r", encoding="utf-8", errors="ignore") as f:
            raw_data += f.read() + "\n"
    return raw_data

def extract_time(line, time_pattern):
    """Extract datetime from a line using the provided regex pattern."""
    time_match = time_pattern.search(line)
    if time_match:
        try:
            if len(time_match.groups()) == 2:
                date_str, time_str = time_match.groups()
                return datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M:%S")
            elif len(time_match.groups()) == 1:
                return datetime.strptime(time_match.group(1), "%Y-%m-%d %H:%M:%S")
        except Exception:
            return None
    return None

def create_dataframe(records, sort_by=None):
    """Create a pandas DataFrame from records and optionally sort."""
    df = pd.DataFrame(records)
    if sort_by and not df.empty:
        df.sort_values(by=sort_by, inplace=True)
    return df

directory_path = "./"
raw_data = read_log_files(directory_path, "ptop-*.log")
time_pattern = re.compile(r"TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})")

# TOP pattern: TOP parent-pid pid use% total-time (user-time system-time) cpu (process-name)
# Example: TOP     1 1150286 100.0% 4998200.7 (4997877.7 323.0) 14 (fp-rte:14)
top_pattern = re.compile(r'TOP\s+(\d+)\s+(\d+)\s+([\d.]+)%\s+([\d.]+)\s+\(([\d.]+)\s+([\d.]+)\)\s+(\d+)\s+\(([^)]+)\)')
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t 
    else:
        top_match = top_pattern.search(line)
        if top_match and current_time:
            parent_pid = int(top_match.group(1))
            pid = int(top_match.group(2))
            cpu_use_pct = float(top_match.group(3))
            total_time = float(top_match.group(4))
            user_time = float(top_match.group(5))
            system_time = float(top_match.group(6))
            cpu_id = int(top_match.group(7))
            process_name = top_match.group(8).strip()
            
            records.append({
                'datetime': current_time,
                'parent_pid': parent_pid,
                'pid': pid,
                'cpu_use_pct': cpu_use_pct,
                'total_time': total_time,
                'user_time': user_time,
                'system_time': system_time,
                'cpu_id': cpu_id,
                'process_name': process_name
            })

df = create_dataframe(records, sort_by=['process_name', 'datetime'])

if df.empty:
    print("⚠️  No TOP data found in logs!")
    print("Please check if the log files contain TOP entries.")
    sys.exit(0)

df['datetime'] = pd.to_datetime(df['datetime'])
df.to_csv('all_top_data.csv', index=False)

print("📊 TOP Data Sample:")
print(df.head(10))
print(f"\n✅ Total records: {len(df)}")
print(f"🔧 Unique Processes: {df['process_name'].nunique()}")

# Calculate diffs for time-based metrics to get actual CPU usage
time_metrics = ['total_time', 'user_time', 'system_time']
for metric in time_metrics:
    # Group by process_name and pid to track each process instance
    df[f'{metric}_diff'] = df.groupby(['process_name', 'pid'])[metric].diff().clip(lower=0)

# Get top N processes by average CPU usage
top_n = 15  # Show top 15 processes
process_avg_cpu = df.groupby('process_name')['cpu_use_pct'].mean().sort_values(ascending=False)
top_processes = process_avg_cpu.head(top_n).index.tolist()

print(f"\n🔝 Top {top_n} processes by average CPU usage:")
for i, (proc, avg_cpu) in enumerate(process_avg_cpu.head(top_n).items(), 1):
    print(f"  {i:2d}. {proc:30s} - {avg_cpu:6.2f}%")

# Filter dataframe to only include top processes
df_top = df[df['process_name'].isin(top_processes)].copy()

# Modern color palette
color_palette = ['#3366CC', '#DC3912', '#109618', '#FF9900', '#990099', '#22AA99', 
                 '#DD4477', '#66AA00', '#0099C6', '#316395', '#994499', '#AAAA11',
                 '#B82E2E', '#6633CC', '#E67300']

# Create subplots in 2-column layout for top processes
rows = (len(top_processes) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    subplot_titles=[f'<b>{proc}</b>' for proc in top_processes],
    vertical_spacing=0.04,
    horizontal_spacing=0.05
)

# Metrics to plot
metrics_to_plot = {
    'cpu_use_pct': {'name': 'CPU Usage %', 'color': '#3366CC'},
    'user_time_diff': {'name': 'User Time (diff)', 'color': '#109618'},
    'system_time_diff': {'name': 'System Time (diff)', 'color': '#DC3912'}
}

# Add traces for each process
for idx, process in enumerate(top_processes):
    proc_data = df_top[df_top['process_name'] == process].sort_values('datetime')
    row = idx // 2 + 1
    col = idx % 2 + 1
    
    # Collect all values for dynamic y-axis scaling
    all_values = []
    
    # Plot metrics
    for metric_idx, (metric, metric_info) in enumerate(metrics_to_plot.items()):
        if metric in proc_data.columns:
            metric_values = proc_data[metric].clip(lower=0)
            all_values.extend(metric_values.tolist())
            
            fig.add_trace(
                go.Scatter(
                    x=proc_data['datetime'],
                    y=metric_values,
                    mode='lines',
                    name=metric_info['name'],
                    legendgroup=metric,
                    line=dict(
                        color=metric_info['color'],
                        width=2,
                        shape='linear'
                    ),
                    hovertemplate='<b>%{fullData.name}</b><br>' +
                                  'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                                  'Value: %{y:.2f}<br>' +
                                  '<extra></extra>',
                    showlegend=(idx == 0)  # Show legend only for first process
                ),
                row=row,
                col=col
            )
    
    # Calculate dynamic y-axis range for this process
    positive_values = [v for v in all_values if v > 0]
    if positive_values:
        y_max = max(positive_values)
        y_range = [0, y_max * 1.1]  # 10% padding
    else:
        y_range = [0, 10]
    
    # Apply dynamic range to this subplot
    fig.update_yaxes(range=y_range, row=row, col=col)

# Update layout with modern aesthetic
fig.update_layout(
    height=300 * rows,
    title={
        'text': f'<b>Top {top_n} Process CPU Usage Metrics</b><br><sub>CPU Percentage & Time Distribution Over Time</sub>',
        'font': {'size': 26, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'x': 0.5,
        'xanchor': 'center',
        'y': 0.99
    },
    legend=dict(
        title={'text': '<b>Metrics</b>', 'font': {'size': 15, 'color': '#2C3E50'}},
        orientation="h",
        x=0.5,
        y=-0.02,
        xanchor="center",
        yanchor="top",
        bgcolor='rgba(255, 255, 255, 0.98)',
        bordercolor='#34495E',
        borderwidth=2,
        font={'size': 12, 'color': '#2C3E50'},
        itemsizing='constant'
    ),
    margin=dict(t=100, b=80, l=60, r=60),
    plot_bgcolor='#F8F9FA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified',
    showlegend=True
)

# Apply consistent axis styling to all subplots
for i in range(1, len(top_processes) + 1):
    row = (i - 1) // 2 + 1
    col = (i - 1) % 2 + 1
    
    # X-axis styling
    fig.update_xaxes(
        type='date',
        showgrid=True,
        gridcolor='#E8E8E8',
        gridwidth=1,
        zeroline=False,
        title_font=dict(size=11, color='#34495E'),
        tickfont=dict(size=10, color='#2C3E50'),
        linecolor='#7F8C8D',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=6,
        tickcolor='#7F8C8D',
        row=row,
        col=col
    )
    
    # Y-axis styling (dynamic range already set above)
    fig.update_yaxes(
        showgrid=True,
        gridcolor='#E8E8E8',
        gridwidth=1,
        zeroline=True,
        zerolinecolor='#BDC3C7',
        zerolinewidth=2,
        title_text='Value',
        title_font=dict(size=11, color='#34495E', weight='bold'),
        tickfont=dict(size=10, color='#2C3E50'),
        linecolor='#7F8C8D',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=6,
        tickcolor='#7F8C8D',
        tickformat='.2f',
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=13, color='#2C3E50', family='Arial, sans-serif')
    annotation['bgcolor'] = 'rgba(52, 152, 219, 0.1)'
    annotation['bordercolor'] = '#3498DB'
    annotation['borderwidth'] = 1
    annotation['borderpad'] = 4

# Save to HTML
pio.write_html(fig, file="top_processes_dashboard.html", full_html=True)
print("\n✅ TOP Processes Dashboard saved as top_processes_dashboard.html")
print("📊 Enhanced with dynamic y-axis scaling per process for better visibility")
print("🎨 Features: Top 15 processes, CPU% + time metrics, spline smoothing, modern design")

# ==================== Generate Top 15 Processes Table ====================

# Calculate total time spent per process (sum of all time diffs)
process_stats = df.groupby('process_name').agg({
    'total_time_diff': 'sum',
    'user_time_diff': 'sum',
    'system_time_diff': 'sum',
    'cpu_use_pct': 'mean',
    'pid': 'nunique',
    'datetime': 'count'  # Count number of observations/samples
}).round(2)

# Rename columns for better readability
process_stats.columns = ['Total CPU Time', 'User Time', 'System Time', 'Avg CPU %', 'Unique PIDs', 'Observations']
process_stats = process_stats.sort_values('Total CPU Time', ascending=False)

# Get top 15 processes
top15_processes = process_stats.head(15).reset_index()
top15_processes.index = top15_processes.index + 1  # Start ranking from 1

# Create HTML table
html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Top 15 Processes by CPU Time</title>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            font-family: 'Arial', 'Segoe UI', sans-serif;
            background: #ffffff;
            padding: 30px 20px;
            min-height: 100vh;
        }}
        .container {{
            max-width: 95%;
            margin: 0 auto;
            background: #ffffff;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }}
        h2 {{
            text-align: center;
            padding: 25px;
            background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%);
            color: white;
            font-size: 28px;
            font-weight: 600;
            margin: 0;
            letter-spacing: 0.5px;
        }}
        .subtitle {{
            text-align: center;
            padding: 15px;
            background: #ECF0F1;
            color: #2C3E50;
            font-size: 14px;
            border-bottom: 2px solid #BDC3C7;
            font-weight: 500;
        }}
        .table-container {{
            width: 100%;
            overflow-x: auto;
            padding: 20px;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            background: white;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            border-radius: 8px;
            overflow: hidden;
        }}
        thead {{
            background: linear-gradient(135deg, #3498DB 0%, #2980B9 100%);
            color: white;
        }}
        th {{
            padding: 18px 15px;
            text-align: left;
            font-weight: 600;
            font-size: 14px;
            letter-spacing: 0.5px;
            text-transform: uppercase;
            border-bottom: 3px solid #2C3E50;
        }}
        th:first-child {{
            text-align: center;
            width: 80px;
        }}
        td {{
            padding: 15px;
            border-bottom: 1px solid #ECF0F1;
            font-size: 14px;
            color: #34495E;
        }}
        td:first-child {{
            text-align: center;
            font-weight: bold;
            font-size: 18px;
            color: #2C3E50;
            background: linear-gradient(135deg, #F8F9FA 0%, #E9ECEF 100%);
        }}
        tbody tr:hover {{
            background-color: #F8F9FA;
            transform: scale(1.01);
            box-shadow: 0 4px 12px rgba(0,0,0,0.08);
            transition: all 0.2s ease;
        }}
        tbody tr:nth-child(odd) {{
            background-color: #FAFAFA;
        }}
        tbody tr:nth-child(1) td:first-child {{
            background: linear-gradient(135deg, #FFD700 0%, #FFC107 100%);
            color: #1A1A1A;
        }}
        tbody tr:nth-child(2) td:first-child {{
            background: linear-gradient(135deg, #C0C0C0 0%, #A8A8A8 100%);
            color: #1A1A1A;
        }}
        tbody tr:nth-child(3) td:first-child {{
            background: linear-gradient(135deg, #CD7F32 0%, #B87333 100%);
            color: white;
        }}
        .process-name {{
            font-weight: 600;
            color: #2C3E50;
            font-family: 'Courier New', monospace;
        }}
        .metric-value {{
            font-weight: 500;
            color: #34495E;
        }}
        .metric-label {{
            font-size: 11px;
            color: #7F8C8D;
            display: block;
            margin-top: 2px;
        }}
        .footer {{
            text-align: center;
            padding: 20px;
            background: #F8F9FA;
            color: #7F8C8D;
            font-size: 12px;
            border-top: 1px solid #E9ECEF;
        }}
        .badge {{
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 600;
            margin-left: 8px;
        }}
        .badge-high {{
            background: #E74C3C;
            color: white;
        }}
        .badge-medium {{
            background: #F39C12;
            color: white;
        }}
        .badge-low {{
            background: #27AE60;
            color: white;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h2>🏆 Top 15 Processes by CPU Time</h2>
        <div class="subtitle">
            Ranked by Total Time Spent on CPU (seconds)
        </div>
        <div class="table-container">
            <table>
                <thead>
                    <tr>
                        <th>Rank</th>
                        <th>Process Name</th>
                        <th>Total CPU Time (s)</th>
                        <th>User Time (s)</th>
                        <th>System Time (s)</th>
                        <th>Avg CPU %</th>
                        <th>Samples</th>
                        <th>PIDs</th>
                    </tr>
                </thead>
                <tbody>
"""

# Add rows for top 15 processes
for idx, row in top15_processes.iterrows():
    process_name = row['process_name']
    total_time = f"{row['Total CPU Time']:,.2f}"
    user_time = f"{row['User Time']:,.2f}"
    system_time = f"{row['System Time']:,.2f}"
    avg_cpu = row['Avg CPU %']
    observations = int(row['Observations'])
    unique_pids = int(row['Unique PIDs'])
    
    # Badge for CPU usage
    if avg_cpu >= 50:
        badge = f'<span class="badge badge-high">HIGH</span>'
    elif avg_cpu >= 10:
        badge = f'<span class="badge badge-medium">MED</span>'
    else:
        badge = f'<span class="badge badge-low">LOW</span>'
    
    html_content += f"""
                    <tr>
                        <td>{idx}</td>
                        <td><span class="process-name">{process_name}</span></td>
                        <td><span class="metric-value">{total_time}</span></td>
                        <td><span class="metric-value">{user_time}</span></td>
                        <td><span class="metric-value">{system_time}</span></td>
                        <td><span class="metric-value">{avg_cpu:.2f}%</span>{badge}</td>
                        <td><span class="metric-value">{observations:,}</span></td>
                        <td><span class="metric-value">{unique_pids}</span></td>
                    </tr>
"""

html_content += """
                </tbody>
            </table>
        </div>
        <div class="footer">
            <strong>Note:</strong> Total CPU Time represents cumulative time spent on CPU across all observations. 
            <strong>Samples</strong> = number of times the process was observed (typically once per minute). 
            <strong>PIDs</strong> = number of unique process IDs (indicating restarts or multiple instances).
        </div>
    </div>
</body>
</html>
"""

# Save the HTML table
with open('top15_processes_table.html', 'w') as f:
    f.write(html_content)

print("\n✅ Top 15 Processes Table saved as top15_processes_table.html")
print("\n🏆 Top 15 Processes by Total CPU Time:")
print("="*80)
for idx, row in top15_processes.iterrows():
    print(f"  {idx:2d}. {row['process_name']:30s} - {row['Total CPU Time']:12,.2f}s (Avg: {row['Avg CPU %']:6.2f}%)")
print("="*80)
print(f"🔧 Analyzed {len(top_processes)} top processes out of {df['process_name'].nunique()} total")
EOF

python3 ${TOP_PY}

rm ${TOP_PY}

#!/bin/bash

CPU_PY='cpu_data.py'
CPU_LOG='cpu_data.csv'
GNUPLOT_FILE='plot_from_cpu.gp'

# Start the python script
cat <<EOF > ${CPU_PY}
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


# Step 1: Read all data*.log files
log_files = sorted(glob.glob("ptop*.log"))

#CPU  cpu u  8.5 id/io 90.5  1.0 u/s/n  0.4  2.1  5.8 irq h/s  0.0  0.2
#CPU cpu0 u  6.0 id/io 93.5  0.5 u/s/n  0.1  1.8  3.7 irq h/s  0.0  0.4
#CPU cpu1 u  9.5 id/io 87.1  3.4 u/s/n  0.1  2.9  6.1 irq h/s  0.0  0.5
#CPU cpu2 u  9.4 id/io 90.2  0.4 u/s/n  0.6  2.2  6.1 irq h/s  0.0  0.5
#CPU cpu3 u 10.8 id/io 85.2  3.9 u/s/n  0.2  2.3  7.9 irq h/s  0.0  0.4
#CPU cpu4 u  9.8 id/io 90.1  0.0 u/s/n  1.1  1.9  6.3 irq h/s  0.0  0.5
#CPU cpu5 u  8.4 id/io 90.9  0.7 u/s/n  0.1  2.4  5.5 irq h/s  0.0  0.4

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

directory_path="./"
raw_data = read_log_files(directory_path, "ptop-*.log")
time_pattern = re.compile(r"TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})")
cpu_pattern = re.compile(r'CPU\s+(cpu\d*|cpu)\s+u\s+([\d.]+).*?u/s/n\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)')
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t 
    else:
        cpu_match = cpu_pattern.search(line)
        if cpu_match and current_time:
            cpu_id = cpu_match.group(1)
            u = float(cpu_match.group(2))
            us = float(cpu_match.group(3))
            sy = float(cpu_match.group(4))
            ni = float(cpu_match.group(5))
            records.append({
                'datetime': current_time,
                'cpu': cpu_id,
                'u': u,
                'us': us, 
                'sy': sy, 
                'ni': ni
                })  

df = create_dataframe(records)
df['datetime'] = pd.to_datetime(df['datetime'])

df.to_csv('all_cpu_data.csv', index=False)

print(df.head())


# Define modern, aesthetic colors for each metric
colors = {
    'u': '#3366CC',      # Royal Blue - User CPU
    'us': '#109618',     # Green - User+System
    'sy': '#DC3912',     # Red - System CPU
    'ni': '#FF9900'      # Orange - Nice CPU
}

# Metric display names for better readability
metric_names = {
    'u': 'User CPU (%)',
    'us': 'User+System (%)',
    'sy': 'System CPU (%)',
    'ni': 'Nice CPU (%)'
}

# Get unique CPUs
unique_cpus = df['cpu'].unique()

# Calculate max and min for each CPU
cpu_stats = {}
for cpu in unique_cpus:
    cpu_data = df[df['cpu'] == cpu]
    # Get max across all metrics
    max_val = cpu_data[['u', 'us', 'sy', 'ni']].max().max()
    min_val = cpu_data[['u', 'us', 'sy', 'ni']].min().min()
    cpu_stats[cpu] = {'max': max_val, 'min': min_val}

# Create subplots manually in 2-column layout with enhanced styling
from plotly.subplots import make_subplots
rows = (len(unique_cpus) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    subplot_titles=[f'<b>{cpu.upper()}</b><br><sub>Max: {cpu_stats[cpu]["max"]:.1f}% | Min: {cpu_stats[cpu]["min"]:.1f}%</sub>' for cpu in unique_cpus],
    vertical_spacing=0.05,
    horizontal_spacing=0.08
)

# Add traces for each CPU with enhanced styling
for idx, cpu in enumerate(unique_cpus):
    cpu_data = df[df['cpu'] == cpu]
    row = idx // 2 + 1
    col = idx % 2 + 1
    for metric in ['u', 'us', 'sy', 'ni']:
        fig.add_trace(
            go.Scatter(
                x=cpu_data['datetime'],
                y=cpu_data[metric],
                mode='lines',
                name=metric_names[metric],
                legendgroup=metric,
                line=dict(
                    color=colors[metric],
                    width=2.5,
                    shape='spline'  # Smooth lines
                ),
                hovertemplate='<b>%{fullData.name}</b><br>' +
                              'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                              'Usage: %{y:.1f}%<br>' +
                              '<extra></extra>',
                showlegend=(idx == 0)  # Show legend only once
            ),
            row=row,
            col=col
        )

# Update layout with modern aesthetic
fig.update_layout(
    height=300 * rows,
    title={
        'text': '<b>CPU Usage Metrics Over Time</b>',
        'font': {'size': 24, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'x': 0.5,
        'xanchor': 'center',
        'y': 0.99,
        'yanchor': 'top',
        'pad': {'t': 10, 'b': 10}
    },
    legend=dict(
        title={'text': '<b>Metrics</b>', 'font': {'size': 14}},
        orientation="h",
        x=0.5,
        y=-0.06,
        xanchor="center",
        yanchor="top",
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#CCCCCC',
        borderwidth=1,
        font={'size': 12}
    ),
    margin=dict(t=150, b=140, l=60, r=60),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified'
)

# Apply consistent axis styling to all subplots
for i in range(1, len(unique_cpus) + 1):
    row = (i - 1) // 3 + 1
    col = (i - 1) % 3 + 1
    
    # X-axis styling
    fig.update_xaxes(
        type='date',
        showgrid=True,
        gridcolor='#E5E5E5',
        gridwidth=1,
        zeroline=False,
        title_font=dict(size=12, color='#34495E'),
        tickfont=dict(size=10, color='#34495E'),
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        row=row,
        col=col
    )
    
    # Y-axis styling
    fig.update_yaxes(
        showgrid=True,
        gridcolor='#E5E5E5',
        gridwidth=1,
        zeroline=True,
        zerolinecolor='#CCCCCC',
        zerolinewidth=1.5,
        title_text='Usage (%)',
        title_font=dict(size=12, color='#34495E'),
        tickfont=dict(size=10, color='#34495E'),
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickformat='.1f',
        range=[0, 100],
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=14, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.01  # Slightly adjust title position

# Build per-CPU scrollable tables
cpu_tables_html = []
for cpu in unique_cpus:
    cpu_data = df[df['cpu'] == cpu].sort_values('datetime').copy()
    table_df = pd.DataFrame({
        'Datetime': cpu_data['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S'),
        'User CPU (%)': cpu_data['u'].round(1),
        'User+System (%)': cpu_data['us'].round(1),
        'System CPU (%)': cpu_data['sy'].round(1),
        'Nice CPU (%)': cpu_data['ni'].round(1)
    })
    table_html = table_df.to_html(index=False, classes='cpu-table cpu-table--metric', border=0)
    cpu_tables_html.append(f"""
    <div class=\"cpu-table-card\">
        <h3>{cpu.upper()}</h3>
        <div class=\"cpu-table-scroll\">{table_html}</div>
    </div>
    """)

plot_html = fig.to_html(full_html=False, include_plotlyjs='cdn')
final_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset=\"utf-8\" />
    <title>CPU Usage Dashboard</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 0;
            background: #f5f7fa;
            color: #2C3E50;
        }}
        .dashboard {{
            padding: 24px;
        }}
        .tables-title {{
            margin: 16px 0 14px;
            font-size: 21px;
            font-weight: 700;
            color: #1F2D3D;
        }}
        .cpu-tables-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(520px, 1fr));
            gap: 16px;
        }}
        .cpu-table-card {{
            border: 1px solid #D9E2EC;
            border-radius: 12px;
            background: linear-gradient(180deg, #FBFCFE 0%, #F7FAFD 100%);
            padding: 12px;
            box-shadow: 0 2px 10px rgba(31, 45, 61, 0.06);
        }}
        .cpu-table-card h3 {{
            margin: 2px 6px 10px;
            font-size: 16px;
            font-weight: 700;
            color: #243447;
        }}
        .cpu-table-scroll {{
            max-height: 320px;
            overflow-y: auto;
            overflow-x: auto;
            background: #FFFFFF;
            border: 1px solid #B8C7D9;
            border-radius: 8px;
        }}
        .cpu-table-scroll::-webkit-scrollbar {{
            width: 10px;
            height: 10px;
        }}
        .cpu-table-scroll::-webkit-scrollbar-thumb {{
            background: #C7D3E0;
            border-radius: 8px;
        }}
        .cpu-table-scroll::-webkit-scrollbar-track {{
            background: #F1F5F9;
            border-radius: 8px;
        }}
        table.cpu-table {{
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12px;
            border: 1px solid #C6D3E1;
        }}
        .cpu-table th, .cpu-table td {{
            border-bottom: 1px solid #D7E1EC;
            border-right: 1px solid #D7E1EC;
            padding: 8px 10px;
            text-align: left;
            white-space: nowrap;
        }}
        .cpu-table th:last-child,
        .cpu-table td:last-child {{
            border-right: 0;
        }}
        .cpu-table th {{
            position: sticky;
            top: 0;
            background-color: #DCE9F7;
            z-index: 2;
            text-transform: uppercase;
            letter-spacing: 0.03em;
            font-size: 11px;
            color: #334E68;
            border-bottom: 2px solid #AFC3D8;
        }}
        .cpu-table tbody tr:nth-child(even) {{
            background: #FAFCFE;
        }}
        .cpu-table tbody tr:hover {{
            background: #EEF5FD;
        }}
        .cpu-table td:nth-child(n+2) {{
            text-align: right;
            font-variant-numeric: tabular-nums;
            color: #1F3A5A;
        }}
    </style>
</head>
<body>
    <div class=\"dashboard\">
        {plot_html}
        <h2 class=\"tables-title\">Per-CPU Scrollable Tables</h2>
        <div class=\"cpu-tables-grid\">
            {''.join(cpu_tables_html)}
        </div>
    </div>
</body>
</html>
"""

with open("cpu_usage_dashboard.html", "w", encoding="utf-8") as f:
    f.write(final_html)

print("✅ CPU dashboard saved as cpu_usage_dashboard.html")
print("📊 Enhanced with taller subplots and per-CPU aesthetic scrollable tables")
EOF



python3 ${CPU_PY}

rm ${CPU_PY}

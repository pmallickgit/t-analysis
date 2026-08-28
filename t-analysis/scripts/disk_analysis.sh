#!/bin/bash

DISK_PY='disk_data.py'
DISK_LOG='disk_data.csv'

# Start the python script
cat <<EOF > ${DISK_PY}
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

# DISK pattern: DISK <id> <name> rkxt <r1> <r2> <r3> <r4> wkxt <w1> <w2> <w3> <w4> sqb <s1> <s2> <s3>
disk_pattern = re.compile(r'DISK\s+(\d+)\s+(\S+)\s+rkxt\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+wkxt\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+sqb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)')
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t 
    else:
        disk_match = disk_pattern.search(line)
        if disk_match and current_time:
            disk_id = disk_match.group(1)
            disk_name = disk_match.group(2)
            
            # Read metrics
            rkxt_1 = float(disk_match.group(3))
            rkxt_2 = float(disk_match.group(4))
            rkxt_3 = float(disk_match.group(5))
            rkxt_4 = float(disk_match.group(6))
            
            wkxt_1 = float(disk_match.group(7))
            wkxt_2 = float(disk_match.group(8))
            wkxt_3 = float(disk_match.group(9))
            wkxt_4 = float(disk_match.group(10))
            
            sqb_1 = float(disk_match.group(11))
            sqb_2 = float(disk_match.group(12))
            sqb_3 = float(disk_match.group(13))
            
            records.append({
                'datetime': current_time,
                'disk_id': disk_id,
                'disk_name': disk_name,
                'read_iops': rkxt_1,
                'read_kb_total': rkxt_2,
                'read_kb_avg': rkxt_3,
                'read_ms_avg': rkxt_4,
                'write_iops': wkxt_1,
                'write_kb_total': wkxt_2,
                'write_kb_avg': wkxt_3,
                'write_ms_avg': wkxt_4,
                'queue_size': sqb_1,
                'queue_min': sqb_2,
                'queue_max': sqb_3
            })

df = create_dataframe(records, sort_by=['disk_name', 'datetime'])

if df.empty:
    print("⚠️  No DISK data found in logs!")
    print("Please check if the log files contain DISK entries.")
    sys.exit(0)

df['datetime'] = pd.to_datetime(df['datetime'])
df.to_csv('all_disk_data.csv', index=False)

print("📊 DISK Data Sample:")
print(df.head(10))
print(f"\n✅ Total records: {len(df)}")
print(f"💾 Unique Disks: {df['disk_name'].nunique()}")
print(f"📋 Available metrics: {[col for col in df.columns if col not in ['datetime', 'disk_id', 'disk_name']]}")

# Get numeric columns (exclude datetime, disk_id, disk_name)
numeric_cols = ['read_iops', 'read_kb_total', 'read_kb_avg', 'read_ms_avg', 
                'write_iops', 'write_kb_total', 'write_kb_avg', 'write_ms_avg',
                'queue_size', 'queue_min', 'queue_max']

# Calculate diffs for counter-based metrics
counter_metrics = ['read_kb_total', 'write_kb_total']
for col in counter_metrics:
    df[f'{col}_diff'] = df.groupby('disk_name')[col].diff().clip(lower=0)

# Modern color palette for metrics
metric_colors = {
    'read_iops': '#3366CC',           # Royal Blue
    'read_kb_total_diff': '#109618',  # Green
    'read_kb_avg': '#66AA00',         # Lime Green
    'read_ms_avg': '#0099C6',         # Cyan
    'write_iops': '#DC3912',          # Red
    'write_kb_total_diff': '#FF9900', # Orange
    'write_kb_avg': '#990099',        # Purple
    'write_ms_avg': '#DD4477',        # Pink
    'queue_size': '#22AA99',          # Teal
    'queue_max': '#994499',           # Violet
}

# Metric display names
metric_names = {
    'read_iops': 'Read IOPS',
    'read_kb_total_diff': 'Read KB/min',
    'read_kb_avg': 'Read KB (Avg)',
    'read_ms_avg': 'Read Latency (ms)',
    'write_iops': 'Write IOPS',
    'write_kb_total_diff': 'Write KB/min',
    'write_kb_avg': 'Write KB (Avg)',
    'write_ms_avg': 'Write Latency (ms)',
    'queue_size': 'Queue Size',
    'queue_max': 'Queue Max',
}

# Get unique disks
unique_disks = sorted(df['disk_name'].unique())

# Calculate statistics for each disk
disk_stats = {}
for disk in unique_disks:
    disk_data = df[df['disk_name'] == disk]
    
    # Calculate max/min for key metrics
    read_iops_max = disk_data['read_iops'].max()
    read_iops_min = disk_data['read_iops'].min()
    write_iops_max = disk_data['write_iops'].max()
    write_iops_min = disk_data['write_iops'].min()
    
    disk_stats[disk] = {
        'read_iops_max': read_iops_max,
        'read_iops_min': read_iops_min,
        'write_iops_max': write_iops_max,
        'write_iops_min': write_iops_min
    }

# Create subplot titles with stats
subplot_titles = [
    f'<b>{disk}</b><br><sub>R-IOPS Max: {disk_stats[disk]["read_iops_max"]:.1f} | Min: {disk_stats[disk]["read_iops_min"]:.1f}<br>W-IOPS Max: {disk_stats[disk]["write_iops_max"]:.1f} | Min: {disk_stats[disk]["write_iops_min"]:.1f}</sub>'
    for disk in unique_disks
]

# Create subplots in 2-column layout
rows = (len(unique_disks) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    subplot_titles=subplot_titles,
    vertical_spacing=0.14,
    horizontal_spacing=0.12
)

# Metrics to plot
plot_metrics = ['read_iops', 'write_iops', 'read_kb_total_diff', 'write_kb_total_diff', 
                'read_ms_avg', 'write_ms_avg', 'queue_size']

# Add traces for each disk
for idx, disk in enumerate(unique_disks):
    disk_data = df[df['disk_name'] == disk].sort_values('datetime')
    row = idx // 2 + 1
    col = idx % 2 + 1
    
    # Collect all values for dynamic y-axis scaling
    all_values = []
    
    # Plot selected metrics
    for metric_idx, metric in enumerate(plot_metrics):
        if metric in disk_data.columns:
            metric_values = disk_data[metric].clip(lower=0)
            all_values.extend(metric_values.tolist())
            
            display_name = metric_names.get(metric, metric.replace('_', ' ').title())
            color = metric_colors.get(metric, '#316395')
            
            fig.add_trace(
                go.Scatter(
                    x=disk_data['datetime'],
                    y=metric_values,
                    mode='lines',
                    name=display_name,
                    legendgroup=metric,
                    line=dict(
                        color=color,
                        width=2.5,
                        shape='spline'
                    ),
                    hovertemplate='<b>%{fullData.name}</b><br>' +
                                  'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                                  'Value: %{y:.2f}<br>' +
                                  '<extra></extra>',
                    showlegend=(idx == 0)  # Show legend only for first disk
                ),
                row=row,
                col=col
            )
    
    # Calculate dynamic y-axis range for this disk
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
        'text': '<b>Disk I/O Performance Metrics</b><br><sub>IOPS, Throughput, Latency & Queue Statistics Over Time</sub>',
        'font': {'size': 24, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'x': 0.5,
        'xanchor': 'center'
    },
    legend=dict(
        title={'text': '<b>Metrics</b>', 'font': {'size': 14}},
        orientation="h",
        x=0.5,
        y=-0.08,
        xanchor="center",
        yanchor="top",
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#34495E',
        borderwidth=2,
        font={'size': 11, 'color': '#2C3E50'}
    ),
    margin=dict(t=180, b=110, l=70, r=70),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified'
)

# Apply consistent axis styling to all subplots
for i in range(1, len(unique_disks) + 1):
    row = (i - 1) // 2 + 1
    col = (i - 1) % 2 + 1
    
    # X-axis styling
    fig.update_xaxes(
        type='date',
        showgrid=True,
        gridcolor='#E0E0E0',
        gridwidth=1,
        zeroline=False,
        title_font=dict(size=11, color='#34495E'),
        tickfont=dict(size=10, color='#2C3E50'),
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
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
        title_font=dict(size=11, color='#34495E'),
        tickfont=dict(size=10, color='#2C3E50'),
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickformat='.2f',
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=11, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.01

# Generate per-disk data tables
disk_tables_html = []
for disk in unique_disks:
    disk_data = df[df['disk_name'] == disk].sort_values('datetime').copy()
    
    # Create table with key metrics
    table_df = pd.DataFrame({
        'Datetime': disk_data['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S'),
        'Read IOPS': disk_data['read_iops'].clip(lower=0).round(2),
        'Write IOPS': disk_data['write_iops'].clip(lower=0).round(2),
        'Read KB/min': disk_data['read_kb_total_diff'].clip(lower=0).round(2),
        'Write KB/min': disk_data['write_kb_total_diff'].clip(lower=0).round(2),
        'Read Latency (ms)': disk_data['read_ms_avg'].clip(lower=0).round(2),
        'Write Latency (ms)': disk_data['write_ms_avg'].clip(lower=0).round(2),
        'Queue Size': disk_data['queue_size'].clip(lower=0).round(2)
    })
    
    table_html = table_df.to_html(index=False, classes='disk-table disk-table--metric', border=0)
    disk_tables_html.append(f'''
    <div class="disk-table-card">
        <h3 class="disk-table-title">📊 Disk: {disk}</h3>
        <div class="disk-table-container">
            {table_html}
        </div>
    </div>
    ''')

# Generate the Plotly HTML
plotly_html = pio.to_html(fig, full_html=False, include_plotlyjs='cdn')

# CSS styling for tables
table_css = '''
<style>
    body {
        font-family: Arial, sans-serif;
        background-color: #f5f7fa;
        margin: 0;
        padding: 20px;
    }
    
    .disk-tables-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 25px;
        margin-top: 30px;
        margin-bottom: 50px;
    }
    
    .disk-table-card {
        background: white;
        border-radius: 8px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        padding: 20px;
        min-width: 0;
        overflow: hidden;
    }
    
    .disk-table-title {
        color: #2C3E50;
        font-size: 16px;
        margin-top: 0;
        margin-bottom: 15px;
        padding-bottom: 10px;
        border-bottom: 2px solid #3498DB;
    }
    
    .disk-table-container {
        max-height: 320px;
        overflow-y: auto;
        overflow-x: auto;
        border: 1px solid #D7E1EC;
        border-radius: 4px;
    }
    
    .disk-table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        font-size: 11px;
        min-width: 100%;
    }
    
    .disk-table thead {
        position: sticky;
        top: 0;
        z-index: 10;
        background-color: #DCE9F7;
    }
    
    .disk-table th {
        padding: 10px 6px;
        text-align: left;
        font-weight: 600;
        color: #2C3E50;
        border-bottom: 2px solid #C6D3E1;
        border-right: 1px solid #D7E1EC;
        white-space: nowrap;
        font-size: 11px;
    }
    
    .disk-table th:last-child {
        border-right: none;
    }
    
    .disk-table td {
        padding: 8px 6px;
        border-bottom: 1px solid #E8EEF4;
        border-right: 1px solid #E8EEF4;
        color: #34495E;
        white-space: nowrap;
    }
    
    .disk-table td:last-child {
        border-right: none;
    }
    
    .disk-table tbody tr:nth-child(even) {
        background-color: #F7FBFF;
    }
    
    .disk-table tbody tr:hover {
        background-color: #EEF5FD;
    }
    
    .disk-table td:not(:first-child) {
        text-align: right;
        font-variant-numeric: tabular-nums;
    }
    
    .disk-table-container::-webkit-scrollbar {
        width: 10px;
        height: 10px;
    }
    
    .disk-table-container::-webkit-scrollbar-track {
        background: #F1F1F1;
        border-radius: 5px;
    }
    
    .disk-table-container::-webkit-scrollbar-thumb {
        background: #BDC3C7;
        border-radius: 5px;
    }
    
    .disk-table-container::-webkit-scrollbar-thumb:hover {
        background: #95A5A6;
    }
</style>
'''

# Combine everything into final HTML
final_html = f'''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Disk Usage Dashboard</title>
    {table_css}
</head>
<body>
    {plotly_html}
    <div class="disk-tables-grid">
        {''.join(disk_tables_html)}
    </div>
</body>
</html>
'''

# Write to file
with open('disk_usage_dashboard.html', 'w', encoding='utf-8') as f:
    f.write(final_html)

print("\n✅ Disk Dashboard saved as disk_usage_dashboard.html")
print("📊 Enhanced with per-disk statistics and scrollable data tables")
print("🎨 Features: Per-disk graphs with min/max stats, spline smoothing, aesthetic tables")
print(f"💾 Analyzed {len(unique_disks)} disk(s): {', '.join(unique_disks)}")
EOF

python3 ${DISK_PY}

rm ${DISK_PY}

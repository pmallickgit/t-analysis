#!/bin/bash

FPMBUF_PY='fpmbuf_data.py'
FPMBUF_LOG='fpmbuf_data.csv'
GNUPLOT_FILE='plot_from_fpmbuf.gp'

# Start the python script
cat <<EOF > ${FPMBUF_PY}
import glob
import os
import pandas as pd
import plotly.graph_objs as go
from plotly.subplots import make_subplots
import plotly.io as pio
import re
from datetime import datetime

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
        except Exception as e:
            return None
    return None

def create_dataframe(records, sort_by=None):
    """Create a pandas DataFrame from records and optionally sort."""
    df = pd.DataFrame(records)
    if sort_by and not df.empty:
        df.sort_values(by=sort_by, inplace=True)
    return df

directory_path="./"

# Use shared log_utils for reading files and extracting time
raw_data = read_log_files(directory_path, "ptop-*.log")
time_pattern = re.compile(r"TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})")
fpmbuf_pattern = re.compile(r"FPMBUF.*?muc (\d+)\s+mac (\d+)\s+pmu ([\d.]+)%")
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t
    else:
        match = fpmbuf_pattern.search(line)
        if match and current_time:
            muc = int(match.group(1))
            mac = int(match.group(2))
            pmu = float(match.group(3))
            records.append({
                "datetime": current_time,
                "muc": muc,
                "mac": mac,
                "pmu": pmu
            })
df = create_dataframe(records, sort_by="datetime")

print("dataframe : ", df.head())
df.to_csv('fpmbuf_data.csv', index=False)

# Define modern color palette for fpmbuf metrics
metric_colors = {
    'muc': '#109618',      # Green - mbuf used
    'mac': '#3366CC',      # Royal Blue - mbuf available
    'pmu': '#DC3912'       # Red - percentage of mbuf used
}

# Metric display names and descriptions
metric_info = {
    'muc': {'name': 'mbuf used count', 'desc': 'Total mbuf used count'},
    'mac': {'name': 'mbuf available count', 'desc': 'Total mbuf available count'},
    'pmu': {'name': 'Percentage mbuf used', 'desc': 'Percentage mbuf used'}
}

# Calculate statistics for each metric
metric_stats = {}
for metric in ['muc', 'mac', 'pmu']:
    metric_stats[metric] = {
        'max': df[metric].max(),
        'min': df[metric].min()
    }

# Create subplot titles with stats
subplot_titles = [
    f"<b>{metric_info['muc']['name']}</b><br><sub>Max: {metric_stats['muc']['max']:.1f} | Min: {metric_stats['muc']['min']:.1f}</sub>",
    f"<b>{metric_info['mac']['name']}</b><br><sub>Max: {metric_stats['mac']['max']:.1f} | Min: {metric_stats['mac']['min']:.1f}</sub>",
    f"<b>{metric_info['pmu']['name']}</b><br><sub>Max: {metric_stats['pmu']['max']:.1f}% | Min: {metric_stats['pmu']['min']:.1f}%</sub>"
]

# Create enhanced subplots in 2-column layout
rows = 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    shared_xaxes=False,
    subplot_titles=subplot_titles,
    horizontal_spacing=0.10,
    vertical_spacing=0.15
)

# Add traces with enhanced styling
metrics = ['muc', 'mac', 'pmu']
for idx, metric in enumerate(metrics, start=1):
    row = (idx - 1) // 2 + 1
    col = (idx - 1) % 2 + 1
    fig.add_trace(
        go.Scatter(
            x=df["datetime"], 
            y=df[metric], 
            mode='lines',
            name=metric_info[metric]['name'],
            line=dict(
                color=metric_colors[metric],
                width=2.5,
                shape='spline'
            ),
            fill='tozeroy',
            fillcolor=f"rgba{tuple(list(int(metric_colors[metric].lstrip('#')[i:i+2], 16) for i in (0, 2, 4)) + [0.1])}",
            hovertemplate='<b>' + metric_info[metric]['name'] + '</b><br>' +
                         'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                         'Value: %{y:.2f}<br>' +
                         '<extra></extra>',
            showlegend=True
        ), 
        row=row, 
        col=col
    )

# Update main layout with modern aesthetic
fig.update_layout(
    height=300 * rows,
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    margin=dict(l=70, r=70, t=180, b=130),
    title={
        'text': '<b>Fastpath mbuf Metrics Dashboard</b><br>' +
                '<sub>mbuf used, available and percentage used Over Time</sub>',
        'x': 0.5,
        'xanchor': 'center',
        'font': {'size': 24, 'color': '#2C3E50', 'family': 'Arial, sans-serif'}
    },
    legend=dict(
        title={'text': '<b>Metrics</b>', 'font': {'size': 14}},
        orientation="h",
        x=0.5,
        y=-0.12,
        xanchor="center",
        yanchor="top",
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#CCCCCC',
        borderwidth=1,
        font={'size': 12}
    ),
    font={'family': 'Arial, sans-serif', 'size': 12, 'color': '#2C3E50'},
    hovermode="x unified",
    showlegend=True
)

# Apply consistent styling to all subplots
for i in range(1, 4):
    # X-axis styling with date formatting
    fig.update_xaxes(
        type='date',
        showgrid=True,
        gridcolor='#E5E5E5',
        gridwidth=1,
        zeroline=False,
        showline=True,
        mirror=True,
        linecolor='#34495E',
        linewidth=1.5,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickfont=dict(color='#34495E', size=10),
        row=1,
        col=i
    )
    
    # Y-axis styling
    fig.update_yaxes(
        showgrid=True,
        gridcolor='#E5E5E5',
        gridwidth=1,
        showline=True,
        mirror=True,
        linecolor='#34495E',
        linewidth=1.5,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickfont=dict(color='#34495E', size=10),
        zeroline=True,
        zerolinecolor='#CCCCCC',
        zerolinewidth=1.5,
        tickformat='.2f',
        row=1,
        col=i
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=11, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.01

# Generate per-metric data tables
metric_tables_html = []
for metric in metrics:
    metric_data = df.sort_values('datetime').copy()
    
    # Create table with the metric
    table_df = pd.DataFrame({
        'Datetime': metric_data['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S'),
        metric_info[metric]['name']: metric_data[metric].round(2)
    })
    
    table_html = table_df.to_html(index=False, classes='fpmbuf-table fpmbuf-table--metric', border=0)
    metric_tables_html.append(f'''
    <div class="fpmbuf-table-card">
        <h3 class="fpmbuf-table-title">📊 {metric_info[metric]['name']}</h3>
        <div class="fpmbuf-table-container">
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
        background-color: #F8F9FA;
        margin: 0;
        padding: 20px;
    }
    
    .fpmbuf-tables-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 25px;
        margin-top: 30px;
        margin-bottom: 50px;
    }
    
    .fpmbuf-table-card {
        background: white;
        border-radius: 8px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        padding: 20px;
        min-width: 0;
        overflow: hidden;
    }
    
    .fpmbuf-table-title {
        color: #2C3E50;
        font-size: 16px;
        margin-top: 0;
        margin-bottom: 15px;
        padding-bottom: 10px;
        border-bottom: 2px solid #3498DB;
    }
    
    .fpmbuf-table-container {
        max-height: 320px;
        overflow-y: auto;
        overflow-x: auto;
        border: 1px solid #D7E1EC;
        border-radius: 4px;
    }
    
    .fpmbuf-table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        font-size: 11px;
        min-width: 100%;
    }
    
    .fpmbuf-table thead {
        position: sticky;
        top: 0;
        z-index: 10;
        background-color: #DCE9F7;
    }
    
    .fpmbuf-table th {
        padding: 10px 6px;
        text-align: left;
        font-weight: 600;
        color: #2C3E50;
        border-bottom: 2px solid #C6D3E1;
        border-right: 1px solid #D7E1EC;
        white-space: nowrap;
        font-size: 11px;
    }
    
    .fpmbuf-table th:last-child {
        border-right: none;
    }
    
    .fpmbuf-table td {
        padding: 8px 6px;
        border-bottom: 1px solid #E8EEF4;
        border-right: 1px solid #E8EEF4;
        color: #34495E;
        white-space: nowrap;
    }
    
    .fpmbuf-table td:last-child {
        border-right: none;
    }
    
    .fpmbuf-table tbody tr:nth-child(even) {
        background-color: #F7FBFF;
    }
    
    .fpmbuf-table tbody tr:hover {
        background-color: #EEF5FD;
    }
    
    .fpmbuf-table td:not(:first-child) {
        text-align: right;
        font-variant-numeric: tabular-nums;
    }
    
    .fpmbuf-table-container::-webkit-scrollbar {
        width: 10px;
        height: 10px;
    }
    
    .fpmbuf-table-container::-webkit-scrollbar-track {
        background: #F1F1F1;
        border-radius: 5px;
    }
    
    .fpmbuf-table-container::-webkit-scrollbar-thumb {
        background: #BDC3C7;
        border-radius: 5px;
    }
    
    .fpmbuf-table-container::-webkit-scrollbar-thumb:hover {
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
    <title>Fastpath mbuf Dashboard</title>
    {table_css}
</head>
<body>
    {plotly_html}
    <div class="fpmbuf-tables-grid">
        {''.join(metric_tables_html)}
    </div>
</body>
</html>
'''

# Write to file
with open('fpmbuf_dashboard.html', 'w', encoding='utf-8') as f:
    f.write(final_html)

print("✅ mbuf Dashboard saved as fpmbuf_dashboard.html")
print("📊 Enhanced with 3-column layout, statistics and scrollable data tables")
print("🎨 Features: Per-metric graphs with min/max stats, spline smoothing, aesthetic tables")
EOF

python3 ${FPMBUF_PY}

rm ${FPMBUF_PY}
rm ${FPMBUF_LOG}

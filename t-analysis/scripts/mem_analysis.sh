#!/bin/bash

MEM_PY='mem_data.py'
MEM_LOG='mem_data.csv'
GNUPLOT_FILE='plot_from_mem.gp'

# Start the python script
cat <<EOF > ${MEM_PY}
import glob
import os
import pandas as pd
import plotly.graph_objects as go
import plotly.io as pio
from plotly.subplots import make_subplots
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
mem_pattern = re.compile(r"MEM\s+t\s+\d+\s+f\s+([\d.]+).*?a\s+([\d.]+).*?sw\s+([\d.]+).*?pio\s+([\d.]+).*?sio\s+([\d.]+)\s+\d+")
records = []
current_time = None
for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t
    else:
        mem_match = mem_pattern.search(line)
        if mem_match and current_time:
            mem_free = float(mem_match.group(1))
            mem_anon = float(mem_match.group(2))
            mem_swap = float(mem_match.group(3))
            mem_pio = float(mem_match.group(4))
            mem_sio = float(mem_match.group(5))
            records.append({
                'datetime': current_time,
                'free': mem_free,
                'anon': mem_anon,
                'swap': mem_swap,
                'pio': mem_pio,
                'sio': mem_sio
            })

df = create_dataframe(records)
print("dataframe : ", df.head())
df.to_csv('mem_data.csv', index=False)

# Define modern color palette for memory metrics
metric_colors = {
    'free': '#109618',      # Green - free memory is good
    'anon': '#3366CC',      # Royal Blue - anonymous memory
    'swap': '#DC3912',      # Red - swap usage (warning)
    'pio': '#FF9900',       # Orange - page I/O
    'sio': '#990099'        # Purple - swap I/O
}

# Metric display names and descriptions
metric_info = {
    'free': {'name': 'Free Memory (%)', 'desc': 'Available Memory'},
    'anon': {'name': 'Anonymous Memory', 'desc': 'Process Private Memory'},
    'swap': {'name': 'Swap Usage', 'desc': 'Swap Space Used'},
    'pio': {'name': 'Page I/O', 'desc': 'Page In/Out Activity'},
    'sio': {'name': 'Swap I/O', 'desc': 'Swap In/Out Activity'}
}

# Create enhanced subplots with 2 columns
metrics = ['free', 'anon', 'swap', 'pio', 'sio']

# Calculate min and max for each metric
metric_stats = {}
for metric in metrics:
    metric_stats[metric] = {
        'max': df[metric].max(),
        'min': df[metric].min()
    }

rows = (len(metrics) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    shared_xaxes=False,
    subplot_titles=[
        f"<b>{metric_info['free']['name']}</b><br><sub>Max: {metric_stats['free']['max']:.2f} | Min: {metric_stats['free']['min']:.2f}</sub>",
        f"<b>{metric_info['anon']['name']}</b><br><sub>Max: {metric_stats['anon']['max']:.2f} | Min: {metric_stats['anon']['min']:.2f}</sub>",
        f"<b>{metric_info['swap']['name']}</b><br><sub>Max: {metric_stats['swap']['max']:.2f} | Min: {metric_stats['swap']['min']:.2f}</sub>",
        f"<b>{metric_info['pio']['name']}</b><br><sub>Max: {metric_stats['pio']['max']:.2f} | Min: {metric_stats['pio']['min']:.2f}</sub>",
        f"<b>{metric_info['sio']['name']}</b><br><sub>Max: {metric_stats['sio']['max']:.2f} | Min: {metric_stats['sio']['min']:.2f}</sub>"
    ],
    vertical_spacing=0.08,
    horizontal_spacing=0.10
)

# Add traces with enhanced styling
for idx, metric in enumerate(metrics):
    row = idx // 2 + 1
    col = idx % 2 + 1
    
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
    margin=dict(l=80, r=80, t=180, b=140),
    title={
        'text': '<b>System Memory Metrics Dashboard</b><br>' +
                '<sub>Memory Usage, Swap, and I/O Performance Over Time</sub>',
        'x': 0.5,
        'xanchor': 'center',
        'font': {'size': 26, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'y': 0.99,
        'yanchor': 'top',
        'pad': {'t': 10, 'b': 10}
    },
    legend=dict(
        title={'text': '<b>Memory Metrics</b>', 'font': {'size': 13}},
        orientation="h",
        yanchor="top",
        y=-0.08,
        xanchor="center",
        x=0.5,
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#CCCCCC',
        borderwidth=1,
        font={'size': 11}
    ),
    font={'family': 'Arial, sans-serif', 'size': 12, 'color': '#2C3E50'},
    hovermode="x unified",
    showlegend=True
)

# Apply consistent styling to all subplots
for idx in range(len(metrics)):
    row = idx // 2 + 1
    col = idx % 2 + 1
    
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
        row=row,
        col=col
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
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=15, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.005

# Build per-segment scrollable tables (for below section)
segment_tables_html = []
for metric in metrics:
    table_df = pd.DataFrame({
        'Datetime': df['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S'),
        metric_info[metric]['name']: df[metric].round(2)
    })
    
    table_html = table_df.to_html(index=False, classes='mem-table mem-table--metric', border=0)
    segment_tables_html.append(f"""
    <div class=\"mem-table-card\">
        <h3>{metric_info[metric]['name']}</h3>
        <div class=\"mem-table-scroll\">{table_html}</div>
    </div>
    """)

plot_html = fig.to_html(full_html=False, include_plotlyjs='cdn')
final_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset=\"utf-8\" />
    <title>Memory Dashboard</title>
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
        .mem-tables-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(480px, 1fr));
            gap: 16px;
        }}
        .mem-table-card {{
            border: 1px solid #D9E2EC;
            border-radius: 12px;
            background: linear-gradient(180deg, #FBFCFE 0%, #F7FAFD 100%);
            padding: 12px;
            box-shadow: 0 2px 10px rgba(31, 45, 61, 0.06);
        }}
        .mem-table-card h3 {{
            margin: 2px 6px 10px;
            font-size: 16px;
            font-weight: 700;
            color: #243447;
        }}
        .mem-table-scroll {{
            max-height: 320px;
            overflow-y: auto;
            overflow-x: auto;
            background: #FFFFFF;
            border: 1px solid #B8C7D9;
            border-radius: 8px;
        }}
        .mem-table-scroll::-webkit-scrollbar {{
            width: 10px;
            height: 10px;
        }}
        .mem-table-scroll::-webkit-scrollbar-thumb {{
            background: #C7D3E0;
            border-radius: 8px;
        }}
        .mem-table-scroll::-webkit-scrollbar-track {{
            background: #F1F5F9;
            border-radius: 8px;
        }}
        table.mem-table {{
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12px;
            border: 1px solid #C6D3E1;
        }}
        .mem-table th, .mem-table td {{
            border-bottom: 1px solid #D7E1EC;
            border-right: 1px solid #D7E1EC;
            padding: 8px 10px;
            text-align: left;
            white-space: nowrap;
        }}
        .mem-table th:last-child,
        .mem-table td:last-child {{
            border-right: 0;
        }}
        .mem-table th {{
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
        .mem-table tbody tr:nth-child(even) {{
            background: #FAFCFE;
        }}
        .mem-table tbody tr:hover {{
            background: #EEF5FD;
        }}
        .mem-table td:nth-child(2) {{
            text-align: right;
            font-variant-numeric: tabular-nums;
            color: #1F3A5A;
        }}
    </style>
</head>
<body>
    <div class=\"dashboard\">
        {plot_html}
        <h2 class=\"tables-title\">Per-Segment Scrollable Tables</h2>
        <div class=\"mem-tables-grid\">
            {''.join(segment_tables_html)}
        </div>
    </div>
</body>
</html>
"""

with open("mem_dashboard.html", "w", encoding="utf-8") as f:
    f.write(final_html)

print("✅ Memory Dashboard saved as mem_dashboard.html")
print("📊 Enhanced with 2-column layout, 300px graphs, and per-segment aesthetic scrollable tables")
EOF

python3 ${MEM_PY}

rm ${MEM_PY}
rm ${MEM_LOG}

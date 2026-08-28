#!/bin/bash

FPCPU_PY='fpcpu_data.py'
FPCPU_LOG='fpcpu_data.csv'
GNUPLOT_FILE='plot_from_fpcpu.gp'

# Start the python script
cat <<EOF > ${FPCPU_PY}
import glob
import os
import pandas as pd
import plotly.graph_objects as go
import plotly.io as pio
from plotly.subplots import make_subplots
import re
from datetime import datetime

# Step 1: Read all data*.log files
log_files = sorted(glob.glob("ptop*.log"))

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

# Use shared log_utils for reading files and extracting time
raw_data = read_log_files(directory_path, "ptop-*.log")
time_pattern = re.compile(r"TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})")
fpcpu_pattern = re.compile(r'FPC\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)')
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t
    else:
        fpcpu_match = fpcpu_pattern.search(line)
        if fpcpu_match and current_time:
            fpcpu_id = fpcpu_match.group(1)
            u = float(fpcpu_match.group(2))
            c = float(fpcpu_match.group(3))
            cs = float(fpcpu_match.group(4))
            records.append({
                'datetime': current_time,
                'cpu': fpcpu_id,
                'u': u,
                'c': c,
                'cs': cs,
            })
df = create_dataframe(records)
df['datetime'] = pd.to_datetime(df['datetime'])

df.to_csv('all_fpcpu_data.csv', index=False)

print(df.head())

# Define modern, aesthetic colors for each metric
colors = {
    'u': '#3366CC',      # Royal Blue - FPCPU usage
    'c': '#109618',     # Green - cycles
    'cs': '#DC3912'     # Red - cycles/second
}

# Metric display names for better readability
metric_names = {
    'u': 'FPCPU Usage',
    'c': 'FPCPU cycles',
    'cs': 'FPCPU cycles/second'
}

# Get unique FPCPUs
unique_fpcpus = df['cpu'].unique()

# Calculate statistics for each FPCPU
fpcpu_stats = {}
for fpcpu in unique_fpcpus:
    fpcpu_data = df[df['cpu'] == fpcpu]
    
    # Calculate max/min for key metrics
    u_max = fpcpu_data['u'].max()
    u_min = fpcpu_data['u'].min()
    c_max = fpcpu_data['c'].max()
    c_min = fpcpu_data['c'].min()
    
    fpcpu_stats[fpcpu] = {
        'u_max': u_max,
        'u_min': u_min,
        'c_max': c_max,
        'c_min': c_min
    }

# Create subplot titles with stats
subplot_titles = [
    f'<b>FPCPU {fpcpu}</b><br><sub>Usage Max: {fpcpu_stats[fpcpu]["u_max"]:.1f} | Min: {fpcpu_stats[fpcpu]["u_min"]:.1f}</sub>'
    for fpcpu in unique_fpcpus
]

# Create subplots: one subplot per FPCPU in a 2-column layout
from plotly.subplots import make_subplots

rows = (len(unique_fpcpus) + 1) // 2
cols = 2

fig = make_subplots(
    rows=rows, 
    cols=cols, 
    subplot_titles=subplot_titles,
    vertical_spacing=0.14,
    horizontal_spacing=0.20,
    specs=[[{"secondary_y": False} for _ in range(cols)] for _ in range(rows)]
)

# Add traces for each FPCPU with all metrics
for idx, fpcpu in enumerate(unique_fpcpus):
    fpcpu_data = df[df['cpu'] == fpcpu]
    row = idx // 2 + 1
    col = idx % 2 + 1
    
    for metric in ['u', 'c', 'cs']:
        fig.add_trace(
            go.Scatter(
                x=fpcpu_data['datetime'],
                y=fpcpu_data[metric],
                mode='lines',
                name=metric_names[metric],
                legendgroup=metric,
                line=dict(
                    color=colors[metric],
                    width=2.5,
                    shape='spline'
                ),
                hovertemplate='<b>%{fullData.name}</b><br>' +
                              'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                              'Value: %{y:.1f}<br>' +
                              '<extra></extra>',
                showlegend=(idx == 0)  # Show legend only once
            ),
            row=row,
            col=col
        )

# Update layout with modern aesthetic
fig.update_layout(
    height=max(600, 300 * rows),
    title={
        'text': '<b>Fastpath CPU Usage Metrics Over Time</b>',
        'font': {'size': 24, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'x': 0.5,
        'xanchor': 'center'
    },
    legend=dict(
        title={'text': '<b>Metrics</b>', 'font': {'size': 14}},
        orientation="h",
        x=0.5,
        y=-0.15,
        xanchor="center",
        yanchor="top",
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#34495E',
        borderwidth=2,
        font={'size': 11, 'color': '#2C3E50'}
    ),
    margin=dict(t=180, b=150, l=60, r=60),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified'
)

# Apply consistent axis styling to all subplots
for i in range(len(unique_fpcpus)):
    row = i // 2 + 1
    col = i % 2 + 1
    
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
    
    # Y-axis styling with dynamic range
    fig.update_yaxes(
        showgrid=True,
        gridcolor='#E5E5E5',
        gridwidth=1,
        zeroline=True,
        zerolinecolor='#CCCCCC',
        zerolinewidth=1.5,
        title_text='Value',
        title_font=dict(size=12, color='#34495E'),
        tickfont=dict(size=10, color='#34495E'),
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickformat='.1f',
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=11, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.01

# Generate per-FPCPU data tables
fpcpu_tables_html = []
for fpcpu in unique_fpcpus:
    fpcpu_data = df[df['cpu'] == fpcpu].sort_values('datetime').copy()
    
    # Create table with key metrics
    table_df = pd.DataFrame({
        'Datetime': fpcpu_data['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S'),
        'FPCPU Usage': fpcpu_data['u'].round(2),
        'FPCPU Cycles': fpcpu_data['c'].round(2),
        'FPCPU Cycles/Sec': fpcpu_data['cs'].round(2)
    })
    
    table_html = table_df.to_html(index=False, classes='fpcpu-table fpcpu-table--metric', border=0)
    fpcpu_tables_html.append(f'''
    <div class="fpcpu-table-card">
        <h3 class="fpcpu-table-title">📊 FPCPU: {fpcpu}</h3>
        <div class="fpcpu-table-container">
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
    
    .fpcpu-tables-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 25px;
        margin-top: 30px;
        margin-bottom: 50px;
    }
    
    .fpcpu-table-card {
        background: white;
        border-radius: 8px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        padding: 20px;
        min-width: 0;
        overflow: hidden;
    }
    
    .fpcpu-table-title {
        color: #2C3E50;
        font-size: 16px;
        margin-top: 0;
        margin-bottom: 15px;
        padding-bottom: 10px;
        border-bottom: 2px solid #3498DB;
    }
    
    .fpcpu-table-container {
        max-height: 320px;
        overflow-y: auto;
        overflow-x: auto;
        border: 1px solid #D7E1EC;
        border-radius: 4px;
    }
    
    .fpcpu-table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        font-size: 11px;
        min-width: 100%;
    }
    
    .fpcpu-table thead {
        position: sticky;
        top: 0;
        z-index: 10;
        background-color: #DCE9F7;
    }
    
    .fpcpu-table th {
        padding: 10px 6px;
        text-align: left;
        font-weight: 600;
        color: #2C3E50;
        border-bottom: 2px solid #C6D3E1;
        border-right: 1px solid #D7E1EC;
        white-space: nowrap;
        font-size: 11px;
    }
    
    .fpcpu-table th:last-child {
        border-right: none;
    }
    
    .fpcpu-table td {
        padding: 8px 6px;
        border-bottom: 1px solid #E8EEF4;
        border-right: 1px solid #E8EEF4;
        color: #34495E;
        white-space: nowrap;
    }
    
    .fpcpu-table td:last-child {
        border-right: none;
    }
    
    .fpcpu-table tbody tr:nth-child(even) {
        background-color: #F7FBFF;
    }
    
    .fpcpu-table tbody tr:hover {
        background-color: #EEF5FD;
    }
    
    .fpcpu-table td:not(:first-child) {
        text-align: right;
        font-variant-numeric: tabular-nums;
    }
    
    .fpcpu-table-container::-webkit-scrollbar {
        width: 10px;
        height: 10px;
    }
    
    .fpcpu-table-container::-webkit-scrollbar-track {
        background: #F1F1F1;
        border-radius: 5px;
    }
    
    .fpcpu-table-container::-webkit-scrollbar-thumb {
        background: #BDC3C7;
        border-radius: 5px;
    }
    
    .fpcpu-table-container::-webkit-scrollbar-thumb:hover {
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
    <title>FPCPU Usage Dashboard</title>
    {table_css}
</head>
<body>
    {plotly_html}
    <div class="fpcpu-tables-grid">
        {''.join(fpcpu_tables_html)}
    </div>
</body>
</html>
'''

# Write to file
with open('fpcpu_usage_dashboard.html', 'w', encoding='utf-8') as f:
    f.write(final_html)

print("✅ FPCPU Dashboard saved as fpcpu_usage_dashboard.html")
print("📊 Enhanced with per-FPCPU statistics and scrollable data tables")
print("🎨 Features: Per-FPCPU graphs with min/max stats, legend 30px+ below graphs, aesthetic tables")
print(f"🔧 Analyzed {len(unique_fpcpus)} FPCPU(s)")
EOF

python3 ${FPCPU_PY}

rm ${FPCPU_PY}


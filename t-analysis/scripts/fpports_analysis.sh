#!/bin/bash

FPPORT_PY='fpport_data.py'
FPPORT_LOG='fpport_data.csv'
GNUPLOT_FILE='plot_from_fpport.gp'

# Start the python script
cat <<EOF > ${FPPORT_PY}
import glob
import os
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import plotly.io as pio
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
time_pattern = re.compile(r"TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")
fpports_pattern = re.compile(r"FPPORTS\s+(port\d+)\s+(.*)")
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t
    else:
        match = fpports_pattern.search(line)
        if match and current_time:
            port = match.group(1)
            kv_string = match.group(2)
            kv_pairs = re.findall(r"(\w+)\s+(\d+)", kv_string)
            data = {k: int(v) for k, v in kv_pairs}
            data.update({"datetime": pd.to_datetime(current_time), "port": port})
            records.append(data)
df = create_dataframe(records, sort_by=["port", "datetime"])
# Compute diffs and QPS for each port and add as columns
if not df.empty:
    for col in ["ip", "op", "im", "in"]:
        if col in df.columns:
            df[f"{col}_diff"] = df.groupby("port")[col].diff()
            df[f"{col}_qps"] = df[f"{col}_diff"] / 60
    df = df.fillna(0)

df.to_csv('all_foports_data.csv', index=False)
print(df.head())

# Define modern, aesthetic colors for each metric
colors = {
    'ip_qps': '#3366CC',      # Royal Blue - User CPU
    'op_qps': '#109618',     # Green - User+System
    'im_qps': '#DC3912',     # Red - System CPU
    'in_qps': '#FF9900'      # Orange - Nice CPU
}

# Metric display names for better readability
metric_names = {
    'ip_qps': 'Input QPS',
    'op_qps': 'Output QPS',
    'im_qps': 'IM QPS',
    'in_qps': 'IN QPS'
}

# Get unique FPPORTs
unique_fpports = df['port'].unique()

# Calculate statistics for each port
port_stats = {}
for port in unique_fpports:
    port_data = df[df['port'] == port]
    
    # Calculate max/min for key metrics
    ip_qps_max = port_data['ip_qps'].clip(lower=0).max()
    ip_qps_min = port_data['ip_qps'].clip(lower=0).min()
    op_qps_max = port_data['op_qps'].clip(lower=0).max()
    op_qps_min = port_data['op_qps'].clip(lower=0).min()
    
    port_stats[port] = {
        'ip_qps_max': ip_qps_max,
        'ip_qps_min': ip_qps_min,
        'op_qps_max': op_qps_max,
        'op_qps_min': op_qps_min
    }

# Create subplot titles with stats
subplot_titles = [
    f'<b>{port.upper()}</b><br><sub>IP Max: {port_stats[port]["ip_qps_max"]:.1f} | Min: {port_stats[port]["ip_qps_min"]:.1f}<br>OP Max: {port_stats[port]["op_qps_max"]:.1f} | Min: {port_stats[port]["op_qps_min"]:.1f}</sub>'
    for port in unique_fpports
]

# Create subplots manually in 2-column layout with enhanced styling
from plotly.subplots import make_subplots
rows = (len(unique_fpports) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    subplot_titles=subplot_titles,
    vertical_spacing=0.14,
    horizontal_spacing=0.10
)

# Add traces for each FPPORT with enhanced styling
for idx, port in enumerate(unique_fpports):
    port_data = df[df['port'] == port]
    row = idx // 2 + 1
    col = idx % 2 + 1
    
    # Collect all values for this port to calculate dynamic y-axis range
    port_values = []
    
    for metric in ['ip_qps', 'op_qps', 'im_qps', 'in_qps']:
        # Clip negative values (from counter resets) to zero
        metric_values = port_data[metric].clip(lower=0)
        port_values.extend(metric_values.tolist())
        
        fig.add_trace(
            go.Scatter(
                x=port_data['datetime'],
                y=metric_values,
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
                              'QPS: %{y:.2f}<br>' +
                              '<extra></extra>',
                showlegend=(idx == 0)  # Show legend only once
            ),
            row=row,
            col=col
        )
    
    # Calculate dynamic y-axis range for this specific port
    positive_values = [v for v in port_values if v > 0]
    if positive_values:
        y_max = max(positive_values)
        y_range = [0, y_max * 1.1]  # Add 10% padding at top
    else:
        y_range = [0, 10]  # Default range if no positive values
    
    # Apply dynamic range to this subplot
    fig.update_yaxes(range=y_range, row=row, col=col)

# Update layout with modern aesthetic
fig.update_layout(
    height=300 * rows,
    title={
        'text': '<b>FPPORTS Usage Metrics Over Time</b>',
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
    margin=dict(t=180, b=110, l=60, r=60),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified'
)

# Apply consistent axis styling to all subplots
for i in range(1, len(unique_fpports) + 1):
    row = (i - 1) // 2 + 1
    col = (i - 1) % 2 + 1
    
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
        title_text='QPS',
        title_font=dict(size=12, color='#34495E'),
        tickfont=dict(size=10, color='#34495E'),
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickformat='.2f',
        # Dynamic range is set per port above
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=11, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.01

# Generate per-port data tables
port_tables_html = []
for port in unique_fpports:
    port_data = df[df['port'] == port].sort_values('datetime').copy()
    
    # Create table with key metrics
    table_df = pd.DataFrame({
        'Datetime': port_data['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S'),
        'IP QPS': port_data['ip_qps'].clip(lower=0).round(2),
        'OP QPS': port_data['op_qps'].clip(lower=0).round(2),
        'IM QPS': port_data['im_qps'].clip(lower=0).round(2),
        'IN QPS': port_data['in_qps'].clip(lower=0).round(2)
    })
    
    table_html = table_df.to_html(index=False, classes='fpport-table fpport-table--metric', border=0)
    port_tables_html.append(f'''
    <div class="fpport-table-card">
        <h3 class="fpport-table-title">📊 Port: {port.upper()}</h3>
        <div class="fpport-table-container">
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
    
    .fpport-tables-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 25px;
        margin-top: 30px;
        margin-bottom: 50px;
    }
    
    .fpport-table-card {
        background: white;
        border-radius: 8px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        padding: 20px;
        min-width: 0;
        overflow: hidden;
    }
    
    .fpport-table-title {
        color: #2C3E50;
        font-size: 16px;
        margin-top: 0;
        margin-bottom: 15px;
        padding-bottom: 10px;
        border-bottom: 2px solid #3498DB;
    }
    
    .fpport-table-container {
        max-height: 320px;
        overflow-y: auto;
        overflow-x: auto;
        border: 1px solid #D7E1EC;
        border-radius: 4px;
    }
    
    .fpport-table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        font-size: 11px;
        min-width: 100%;
    }
    
    .fpport-table thead {
        position: sticky;
        top: 0;
        z-index: 10;
        background-color: #DCE9F7;
    }
    
    .fpport-table th {
        padding: 10px 6px;
        text-align: left;
        font-weight: 600;
        color: #2C3E50;
        border-bottom: 2px solid #C6D3E1;
        border-right: 1px solid #D7E1EC;
        white-space: nowrap;
        font-size: 11px;
    }
    
    .fpport-table th:last-child {
        border-right: none;
    }
    
    .fpport-table td {
        padding: 8px 6px;
        border-bottom: 1px solid #E8EEF4;
        border-right: 1px solid #E8EEF4;
        color: #34495E;
        white-space: nowrap;
    }
    
    .fpport-table td:last-child {
        border-right: none;
    }
    
    .fpport-table tbody tr:nth-child(even) {
        background-color: #F7FBFF;
    }
    
    .fpport-table tbody tr:hover {
        background-color: #EEF5FD;
    }
    
    .fpport-table td:not(:first-child) {
        text-align: right;
        font-variant-numeric: tabular-nums;
    }
    
    .fpport-table-container::-webkit-scrollbar {
        width: 10px;
        height: 10px;
    }
    
    .fpport-table-container::-webkit-scrollbar-track {
        background: #F1F1F1;
        border-radius: 5px;
    }
    
    .fpport-table-container::-webkit-scrollbar-thumb {
        background: #BDC3C7;
        border-radius: 5px;
    }
    
    .fpport-table-container::-webkit-scrollbar-thumb:hover {
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
    <title>FPPORTS Usage Dashboard</title>
    {table_css}
</head>
<body>
    {plotly_html}
    <div class="fpport-tables-grid">
        {''.join(port_tables_html)}
    </div>
</body>
</html>
'''

# Write to file
with open('port_usage_dashboard.html', 'w', encoding='utf-8') as f:
    f.write(final_html)

print("✅ FPPORTS Dashboard saved as port_usage_dashboard.html")
print("📊 Enhanced with per-port statistics and scrollable data tables")
print("🎨 Features: Per-port graphs with min/max stats, spline smoothing, aesthetic tables")
print(f"🔌 Analyzed {len(unique_fpports)} port(s): {', '.join([p.upper() for p in unique_fpports])}")
EOF


python3 ${FPPORT_PY}

rm ${FPPORT_PY}

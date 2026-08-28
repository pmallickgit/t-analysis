#!/bin/bash

NET_PY='net_data.py'
NET_LOG='net_data.csv'

# Start the python script
cat <<EOF > ${NET_PY}
import os
import pandas as pd
import glob
import re
import sys
from datetime import datetime
import plotly.io as pio
import plotly.graph_objs as go

#NET    lo rk 61.6 9.3 tk 61.6 9.3 rd 0.0 td 0.0
#NET ifstat    lo 188421368 24660487074 188421368 24660487074 0 0 
#NET ifstatdocker0 0 0 0 0 0 0 
#NET ifstatdummy0 0 0 0 0 0 0 
#NET  eth0 rk 10.8 1.3 tk 10.8 2.2 rd 0.0 td 0.0
#NET ifstat  eth0 42328228 5595039673 43859081 8407234201 8 0 
#NET  eth3 rk 0.2 0.0 tk 0.0 0.0 rd 0.0 td 0.0
#NET ifstat  eth3 1125596 79314116 0 0 0 0 
#NET  eth1 rk 17.5 1.4 tk 17.8 1.4 rd 0.0 td 0.0
#NET ifstat  eth1 11476508658 1145655315454 10908707443 1220166533513 141 0 
#NET  eth2 rk 0.4 0.0 tk 0.0 0.0 rd 0.0 td 0.0
#NET ifstat  eth2 1889060 122426858 0 0 0 0 
#NET ifstatfp_linux 0 0 0 0 0 0 
#NET bond0 rk 17.7 1.4 tk 17.8 1.4 rd 0.0 td 0.0
#NET ifstat bond0 11477247356 1099872140786 10922124458 1178061605632 0 0 
#NET  tun2 rk 3.5 0.3 tk 3.4 0.2 rd 0.0 td 0.0
#NET ifstat  tun2 2432871 236732345 2326941 201248142 0 0 
#NETfptun0 rk 17.2 1.6 tk 0.0 0.0 rd 0.0 td 0.0
#NET ifstatfptun0 359493415 88156449078 267 30880 0 0 

directory_path = "./"
ptop_files = sorted(glob.glob(os.path.join(directory_path, "ptop-*.log")))

# TIME 5617816.8 1760698841 2025-10-17 12:00:42
time_pattern = re.compile(r'^TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})')
# NET ifstat  eth1 11476508658 1145655315454 10908707443 1220166533513 141 0 
net_pattern = re.compile(r"^NET\s+ifstat\s*(\w+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)")

raw_data = ""
for file in ptop_files:
    with open(file, "r", encoding="utf-8", errors="ignore") as f:
        raw_data = raw_data + f.read() + "\n"

current_time = None
records = []
time_data = None

for line in raw_data.splitlines():
    time_match = time_pattern.search(line)
    if time_match:
        try:
            if len(time_match.groups()) == 2:
                date_str, time_str = time_match.groups()
                time_data = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M:%S")
            elif len(time_match.groups()) == 1:
                time_data = datetime.strptime(time_match.group(1), "%Y-%m-%d %H:%M:%S")
        except Exception:
            print("exception caught while processing time data")

        if time_data:
            current_time = time_data
    else:
        net_match = net_pattern.search(line)
        if net_match and current_time:
            if_name = net_match.group(1)
            rk = net_match.group(2)
            rkb = net_match.group(3)
            tk = net_match.group(4)
            tkb = net_match.group(5)
            rd = net_match.group(6)
            td = net_match.group(7)
            records.append({
                'datetime': current_time,
                'if_name': if_name,
                'rk': rk,
                'rkb': rkb,
                'tk': tkb,
                'tkb': tkb,
                'rd': rd,
                'td': td
            })

df = pd.DataFrame(records) 

print(df.head())
col_list = df.columns.tolist()
selected_columns = col_list[2:]
print(selected_columns)

print("\n columns:\n")
for c in col_list[2:]:
    df[c] = pd.to_numeric(df[c], errors='coerce')
    df[f'{c}_diff'] = df[c].diff()
    print(df[c].diff().head())
print(df.head())
print(df.info())

# Display the final DataFrame
df = df.round(2)
df = df.fillna(0)

# Plot using Plotly
required_cols = ["datetime", "rk_diff", "tk_diff", "rd_diff", "td_diff"]
if not all(col in df.columns for col in required_cols):
    print("No data found for this dashboard")
    exit()

# Define modern, aesthetic colors for each metric with better contrast
colors = {
    'rk_diff': '#3366CC',      # Royal Blue
    'tk_diff': '#109618',      # Green
    'rd_diff': '#DC3912',      # Red
    'td_diff': '#FF9900'       # Orange
}

# Metric display names for better readability
metric_names = {
    'rk_diff': 'RX Packets',
    'tk_diff': 'TX Packets',
    'rd_diff': 'RX Dropped',
    'td_diff': 'TX Dropped'
}

# Get unique interfaces
unique_ifs = df['if_name'].unique()

# Calculate min and max for each interface across all metrics
if_stats = {}
for ifc in unique_ifs:
    if_data = df[df['if_name'] == ifc]
    all_vals = pd.concat([if_data['rk_diff'], if_data['tk_diff'], if_data['rd_diff'], if_data['td_diff']]).clip(lower=0)
    if_stats[ifc] = {
        'max': all_vals.max() if len(all_vals) > 0 else 0,
        'min': all_vals.min() if len(all_vals) > 0 else 0
    }

# Create subplots manually in 2-column layout with enhanced styling
from plotly.subplots import make_subplots
rows = (len(unique_ifs) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    subplot_titles=[f'<b>{ifc}</b><br><sub>Max: {if_stats[ifc]["max"]:,.0f} | Min: {if_stats[ifc]["min"]:,.0f}</sub>' for ifc in unique_ifs],
    vertical_spacing=0.14,
    horizontal_spacing=0.08
)

# Add traces for each interface with enhanced styling
for idx, ifc in enumerate(unique_ifs):
    if_data = df[df['if_name'] == ifc]
    row = idx // 2 + 1
    col = idx % 2 + 1
    for metric in ['rk_diff', 'tk_diff', 'rd_diff', 'td_diff']:
        # Clip negative values to zero (negative diffs are artifacts from counter resets)
        metric_values = if_data[metric].clip(lower=0)
        
        fig.add_trace(
            go.Scatter(
                x=if_data['datetime'],
                y=metric_values,
                mode='lines',
                name=metric_names[metric],
                legendgroup=metric,
                line=dict(
                    color=colors[metric],
                    width=2.5,
                    shape='spline',  # Smooth lines
                ),
                hovertemplate='<b>%{fullData.name}</b><br>' +
                              'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                              'Value: %{y:,.0f}<br>' +
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
        'text': '<b>Network Usage Metrics Over Time</b>',
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
        y=-0.11,
        xanchor="center",
        yanchor="top",
        bgcolor='rgba(255, 255, 255, 0.9)',
        bordercolor='#CCCCCC',
        borderwidth=1,
        font={'size': 12}
    ),
    margin=dict(t=150, b=150, l=60, r=60),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified'
)

# Apply consistent axis styling to all subplots with dynamic y-axis ranges
for i in range(1, len(unique_ifs) + 1):
    row = (i - 1) // 3 + 1
    col = (i - 1) % 3 + 1
    
    # Get interface-specific data to calculate y-axis range
    ifc = unique_ifs[i - 1]
    if_data = df[df['if_name'] == ifc]
    
    # Calculate dynamic y-axis range (exclude negative values for better scaling)
    all_values = pd.concat([
        if_data['rk_diff'].dropna(),
        if_data['tk_diff'].dropna(),
        if_data['rd_diff'].dropna(),
        if_data['td_diff'].dropna()
    ])
    
    # Filter positive values only for range calculation
    positive_values = all_values[all_values > 0]
    
    if len(positive_values) > 0:
        y_max = positive_values.max()
        y_min = 0  # Always start from 0 for cleaner visualization
        
        # Add 10% padding at the top for better visibility
        y_range = [y_min, y_max * 1.1]
    else:
        y_range = None  # Let Plotly auto-scale if no positive values
    
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
        title_font=dict(size=12, color='#34495E'),
        tickfont=dict(size=10, color='#34495E'),
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickformat=',',
        range=y_range,  # Apply dynamic range
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=14, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.01  # Slightly adjust title position

# Build per-interface scrollable tables
if_tables_html = []
for ifc in unique_ifs:
    if_data = df[df['if_name'] == ifc].sort_values('datetime').copy()
    table_df = pd.DataFrame({
        'Datetime': if_data['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S'),
        'RX Packets': if_data['rk_diff'].clip(lower=0).round(0).astype(int),
        'TX Packets': if_data['tk_diff'].clip(lower=0).round(0).astype(int),
        'RX Dropped': if_data['rd_diff'].clip(lower=0).round(0).astype(int),
        'TX Dropped': if_data['td_diff'].clip(lower=0).round(0).astype(int)
    })
    
    table_html = table_df.to_html(index=False, classes='net-table net-table--metric', border=0)
    if_tables_html.append(f"""
    <div class=\"net-table-card\">
        <h3>{ifc}</h3>
        <div class=\"net-table-scroll\">{table_html}</div>
    </div>
    """)

plot_html = fig.to_html(full_html=False, include_plotlyjs='cdn')
final_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset=\"utf-8\" />
    <title>Network Usage Dashboard</title>
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
        .net-tables-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(520px, 1fr));
            gap: 16px;
        }}
        .net-table-card {{
            border: 1px solid #D9E2EC;
            border-radius: 12px;
            background: linear-gradient(180deg, #FBFCFE 0%, #F7FAFD 100%);
            padding: 12px;
            box-shadow: 0 2px 10px rgba(31, 45, 61, 0.06);
        }}
        .net-table-card h3 {{
            margin: 2px 6px 10px;
            font-size: 16px;
            font-weight: 700;
            color: #243447;
        }}
        .net-table-scroll {{
            max-height: 320px;
            overflow-y: auto;
            overflow-x: auto;
            background: #FFFFFF;
            border: 1px solid #B8C7D9;
            border-radius: 8px;
        }}
        .net-table-scroll::-webkit-scrollbar {{
            width: 10px;
            height: 10px;
        }}
        .net-table-scroll::-webkit-scrollbar-thumb {{
            background: #C7D3E0;
            border-radius: 8px;
        }}
        .net-table-scroll::-webkit-scrollbar-track {{
            background: #F1F5F9;
            border-radius: 8px;
        }}
        table.net-table {{
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12px;
            border: 1px solid #C6D3E1;
        }}
        .net-table th, .net-table td {{
            border-bottom: 1px solid #D7E1EC;
            border-right: 1px solid #D7E1EC;
            padding: 8px 10px;
            text-align: left;
            white-space: nowrap;
        }}
        .net-table th:last-child,
        .net-table td:last-child {{
            border-right: 0;
        }}
        .net-table th {{
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
        .net-table tbody tr:nth-child(even) {{
            background: #FAFCFE;
        }}
        .net-table tbody tr:hover {{
            background: #EEF5FD;
        }}
        .net-table td:nth-child(n+2) {{
            text-align: right;
            font-variant-numeric: tabular-nums;
            color: #1F3A5A;
        }}
    </style>
</head>
<body>
    <div class=\"dashboard\">
        {plot_html}
        <h2 class=\"tables-title\">Per-Interface Scrollable Tables</h2>
        <div class=\"net-tables-grid\">
            {''.join(if_tables_html)}
        </div>
    </div>
</body>
</html>
"""

with open("net_usage_dashboard.html", "w", encoding="utf-8") as f:
    f.write(final_html)

print("✅ Network dashboard saved as net_usage_dashboard.html")
print("📊 Enhanced with min/max statistics and per-interface aesthetic scrollable tables")
EOF



python3 ${NET_PY}

rm ${NET_PY}

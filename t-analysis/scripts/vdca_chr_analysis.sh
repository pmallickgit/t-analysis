#!/bin/bash

VDCA_CHR_PY='vdca_chr_data.py'
VDCA_CHR_LOG='vdca_chr_data.csv'

# Start the python script
cat <<EOF > ${VDCA_CHR_PY}
import os
import glob
import pandas as pd
import plotly.express as px
import re
import glob
import plotly.io as pio
import plotly.graph_objs as go


directory_path="./"

log_files = sorted(glob.glob(os.path.join(directory_path, "ptop-*.log")))

# Initialize list to collect data
data_records = []

# Iterate over all matching files
for filepath in log_files:
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as file:
        content = file.read()

        # Example: Extract all lines with a specific pattern (customize as needed)
        # For demonstration, let's assume we are extracting lines with 'FPS iod' and 'TIME'
        time_matches = re.findall(r'TIME\s+[\d.]+\s+\d+\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', content)
        fps_matches = re.findall(r'FPS\s+iod\s+(\d+)\s+(\d+)\s+(\d+)\s+mhb\s+(\d+)\s+(\d+)\s+(\d+)', content)

        # Pair each FPS with the most recent TIME
        time_index = 0
        for match in fps_matches:
            if time_index < len(time_matches):
                record = {
                    'datetime': time_matches[time_index],
                    'input': int(match[0]),
                    'output': int(match[1]),
                    'drop': int(match[2]),
                    'miss': int(match[3]),
                    'hit': int(match[4]),
                    'bypass': int(match[5])
                    #'source_file': os.path.basename(filepath)
                }
                data_records.append(record)
                time_index += 1

# Create DataFrame
df = pd.DataFrame(data_records)
if df.empty or 'datetime' not in df.columns:
    print("[DEBUG] No data found or 'datetime' column missing. Returning empty DataFrame.")
    exit()

# Convert datetime column to datetime type
df['datetime'] = pd.to_datetime(df['datetime'])

# Sort by datetime
df.sort_values('datetime', inplace=True)

print(df.head())

# Compute diffs and QPS
for col in ['input', 'output', 'drop', 'miss', 'hit', 'bypass']:
    df[f'{col}_diff'] = df[col].diff()

df['mhqps'] = (df['hit_diff'] + df['miss_diff']) / 60
df['ouvin'] = (df['input_diff']-df['output_diff'])
df['misspc'] = (df['miss_diff'] / (df['hit_diff']+df['miss_diff']))*100
df['hitpc'] = (df['hit_diff'] / (df['hit_diff']+df['miss_diff']))*100

# Reset index
df.reset_index(drop=True, inplace=True)

# Display the full DataFrame
#with pd.option_context('display.max_rows', None, 'display.max_columns', None):
#print(df)

# Display the final DataFrame
df = df.round(2)
df = df.fillna(0)

# Plot using Plotly
required_cols = ["datetime", "input_diff", "output_diff", "drop_diff", "miss_diff", "hit_diff", "bypass_diff", "mhqps"]
if not all(col in df.columns for col in required_cols):
    print("No data found for this dashboard")
    exit()

# Define modern color palette for vDCA CHR metrics
metric_colors = {
    'input_diff': '#3366CC',      # Royal Blue - Input
    'output_diff': '#109618',     # Green - Output (success)
    'drop_diff': '#DC3912',       # Red - Drops (critical)
    'miss_diff': '#FF9900',       # Orange - Cache Miss
    'hit_diff': '#22AA99',        # Teal - Cache Hit (good)
    'bypass_diff': '#990099',     # Purple - Bypass
    'mhqps': '#DD4477'            # Pink - QPS metric
}

# Metric display names for better readability
metric_names = {
    'input_diff': 'Input Packets',
    'output_diff': 'Output Packets',
    'drop_diff': 'Dropped Packets',
    'miss_diff': 'Cache Misses',
    'hit_diff': 'Cache Hits',
    'bypass_diff': 'Bypass Count',
    'mhqps': 'Miss+Hit QPS'
}

# Create enhanced figure
fig = go.Figure()

# Add traces with modern styling
metrics = ['input_diff', 'output_diff', 'drop_diff', 'miss_diff', 'hit_diff', 'bypass_diff', 'mhqps']
for metric in metrics:
    fig.add_trace(go.Scatter(
        x=df["datetime"], 
        y=df[metric], 
        mode='lines',
        name=metric_names[metric],
        line=dict(
            color=metric_colors[metric],
            width=2.5,
            shape='spline'
        ),
        hovertemplate='<b>' + metric_names[metric] + '</b><br>' +
                     'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                     'Value: %{y:,.2f}<br>' +
                     '<extra></extra>'
    ))

# Update layout with modern aesthetic
fig.update_layout(
    title={
        'text': '<b>vDCA Cache Hit Ratio (CHR) Metrics Over Time</b><br>' +
                '<sub>Cache Performance, Packet Flow, and QPS Analysis</sub>',
        'x': 0.5,
        'xanchor': 'center',
        'font': {'size': 20, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'y': 0.97,
        'yanchor': 'top',
        'pad': {'t': 10}
    },
    xaxis_title="<b>Date & Time</b>",
    yaxis_title="<b>Count / Rate</b>",
    legend=dict(
        title={'text': '<b>CHR Metrics</b>', 'font': {'size': 14}},
        orientation="h",
        yanchor="top",
        y=-0.15,
        xanchor="center",
        x=0.5,
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#CCCCCC',
        borderwidth=1,
        font={'size': 12}
    ),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    margin=dict(l=80, r=80, t=140, b=150),
    font={'family': 'Arial, sans-serif', 'size': 12, 'color': '#2C3E50'},
    hovermode="x unified",
    width=1800,
    height=700
)

# Calculate dynamic y-axis range for better visibility of variations
all_values = pd.concat([
    df[metric].dropna() for metric in metrics
])

# Filter positive values only for range calculation
positive_values = all_values[all_values > 0]

if len(positive_values) > 0:
    y_max = positive_values.max()
    y_min = max(0, positive_values.min() * 0.9)  # Start slightly below minimum positive value
    
    # Add 10% padding at the top for better visibility
    y_range = [y_min, y_max * 1.1]
else:
    y_range = None  # Let Plotly auto-scale if no positive values

# Enhanced axis styling with dynamic range
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
    tickfont=dict(color='#34495E', size=11),
    title_font=dict(size=14, color='#34495E')
)

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
    tickfont=dict(color='#34495E', size=11),
    zeroline=True,
    zerolinecolor='#CCCCCC',
    zerolinewidth=1.5,
    tickformat=',.2f',
    title_font=dict(size=14, color='#34495E'),
    range=y_range  # Apply dynamic range
)

pio.write_html(fig, file="vdca_chr_dashboard.html", full_html=True)
print("✅ vDCA CHR Dashboard saved as vdca_chr_dashboard.html")
print("📊 Enhanced with modern aesthetic design")

required_cols = ["datetime", "input_diff", "output_diff", "ouvin", "drop_diff", "miss_diff", "misspc", "hit_diff", "hitpc", "bypass_diff", "mhqps"]
html_table = df[required_cols].to_html(classes="table table-striped text-center table-hover", justify='center', index=True, header=True)

# Enhanced HTML content with modern aesthetic styling
html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>vDCA CHR Data Table</title>
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
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
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
        }}
        .table-container {{
            width: 100%;
            max-height: 600px;
            overflow-y: auto;
            overflow-x: auto;
            border: 2px solid #34495E;
        }}
        table {{
            border-collapse: collapse;
            width: 100%;
            font-size: 13px;
        }}
        th, td {{
            border: 1px solid #BDC3C7;
            padding: 12px 10px;
            text-align: center;
        }}
        th {{
            background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%);
            color: white;
            font-weight: 600;
            position: sticky;
            top: 0;
            z-index: 10;
            text-transform: uppercase;
            font-size: 12px;
            letter-spacing: 0.5px;
        }}
        tr:nth-child(even) {{
            background-color: #F8F9FA;
        }}
        tr:nth-child(odd) {{
            background-color: #FFFFFF;
        }}
        tr:hover {{
            background-color: #E8F4F8;
            transition: background-color 0.3s ease;
        }}
        td {{
            color: #2C3E50;
        }}
        /* Scrollbar styling */
        .table-container::-webkit-scrollbar {{
            width: 10px;
            height: 10px;
        }}
        .table-container::-webkit-scrollbar-track {{
            background: #ECF0F1;
        }}
        .table-container::-webkit-scrollbar-thumb {{
            background: #95A5A6;
            border-radius: 5px;
        }}
        .table-container::-webkit-scrollbar-thumb:hover {{
            background: #7F8C8D;
        }}
        .stats {{
            padding: 20px;
            background: #ECF0F1;
            text-align: center;
            color: #2C3E50;
            font-size: 14px;
            border-top: 2px solid #BDC3C7;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h2>📊 vDCA Cache Hit Ratio (CHR) Data</h2>
        <div class="subtitle">
            Cache Performance Metrics: Input/Output, Hits/Misses, Drops, Bypass, and QPS
        </div>
        <div class="table-container">
            {html_table}
        </div>
        <div class="stats">
            Total Records: {len(df)} | Updated: {df['datetime'].max() if not df.empty else 'N/A'}
        </div>
    </div>
</body>
</html>
"""

# Save to HTML file
with open("vdca_chr_table.html", "w") as f:
    f.write(html_content)

print("✅ HTML table with modern design created: vdca_chr_table.html")
EOF

python3 ${VDCA_CHR_PY}

rm ${VDCA_CHR_PY}

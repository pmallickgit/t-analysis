#!/bin/bash

BIND_CHR_PY='bind_chr_data.py'
BIND_CHR_LOG='bind_chr_data.csv'

# Start the python script
cat <<EOF > ${BIND_CHR_PY}
import os
import pandas as pd
import re
import gzip
import shutil
import plotly.express as px
from datetime import datetime
import glob
import plotly.io as pio
import plotly.graph_objs as go


# Configure pandas to display all rows and columns without truncation
#pd.set_option('display.max_rows', None)
#pd.set_option('display.max_columns', None)
#pd.set_option('display.width', None)
#pd.set_option('display.max_colwidth', None)

#messages.0:2025-07-09T11:01:29+02:00 daemon dnsmovrsnb01.vodafone.es named[28489]: info general: Recursion cache view "_default": size = 1879033822, hits = 10941935089, misses = 561053023

directory_path="./"

# Walk through the directory recursively
gz_files = []
gz_files = sorted(glob.glob(os.path.join(directory_path, "messages.?.gz")))
if len(gz_files) == 0:
    gz_files = sorted(glob.glob(os.path.join(directory_path, "syslog.?.gz")))

for file in gz_files:
    if file.endswith(".gz"):
        gz_path = file
        output_path = file[:-3]  # Remove .gz extension

        # Unzip the file
        with gzip.open(gz_path, 'rb') as f_in:
            with open(output_path, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)

log_files = []
log_files = sorted(glob.glob(os.path.join(directory_path, "messages.?")))
if len(log_files) == 0:
    log_files = sorted(glob.glob(os.path.join(directory_path, "syslog.?")))

#pattern = re.compile(r'(?P<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\+\d{2}:\d{2}.*?view \"(?P<view>.*?)\": size = (?P<size>\d+), hits = (?P<hits>\d+), misses = (?P<misses>\d+)'
pattern = re.compile(r'(?P<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\+\d{2}:\d{2}.*?view "(?P<view>.*?)": size = (?P<size>\d+), hits = (?P<hits>\d+), misses = (?P<misses>\d+)')

records = []

for filename in log_files:
    #filename = f"messages.{i}"
    if os.path.exists(filename):
        with open(filename, 'r', encoding="latin-1") as f: 
            content = f.read()
            matches = pattern.findall(content)
            for match in matches:
                records.append({
                    "time": datetime.strptime(match[0], "%Y-%m-%dT%H:%M:%S"),
                    "view": match[1],
                    "size": int(match[2]),
                    "hits": int(match[3]),
                    "misses": int(match[4])
                })

# Create DataFrame
df = pd.DataFrame(records)
if df.empty:
    print("There are no data.")
    exit()

df.sort_values("time", inplace=True)

# Calculate differences
#df["hits_diff"] = df["hits"].diff()
#df["misses_diff"] = df["misses"].diff()

# Covert data into MB
df["size"]=df["size"]/(1024*1024)

# Calculate percentages
#df["hits %"] = df["hits"] / (df["hits"] + df["misses"]) * 100
#df["misses %"] = df["misses"] / (df["hits"] + df["misses"]) * 100

# Calculate QPS (Queries per second) over 5-minute intervals
#interval_seconds = 5 * 60
#df["qps"] = (df["hits_diff"] + df["misses_diff"]) / interval_seconds

# Display the final DataFrame
#df=df.round(2)


print(df.head())

# Define modern, aesthetic color palette for BIND CHR metrics
metric_colors = {
    'hits': '#22AA99',           # Teal - Cache Hits (good)
    'misses': '#DC3912',         # Red - Cache Misses (warning)
    'hits_diff': '#3366CC',      # Royal Blue - Hit Rate
    'misses_diff': '#FF9900',    # Orange - Miss Rate
    'qps': '#109618'             # Green - Queries Per Second
}

# Metric display names for better readability
metric_names = {
    'hits_diff': 'Cache Hits/Interval',
    'misses_diff': 'Cache Misses/Interval',
    'qps': 'Queries Per Second (QPS)'
}

# Get unique VIEWs
unique_views = df['view'].unique()

# Create subplots manually in 2-column layout with enhanced styling
from plotly.subplots import make_subplots
rows = (len(unique_views) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    subplot_titles=[f'<b>View: {view}</b>' for view in unique_views],
    vertical_spacing=0.08,
    horizontal_spacing=0.10
)

# Add traces for each View with enhanced styling
for idx, view in enumerate(unique_views):
    view_data = df[df['view'] == view].copy()
    print(view_data.head(10))
    view_data["hits_diff"] = view_data["hits"].diff()
    view_data["misses_diff"] = view_data["misses"].diff()

    # Calculate percentages
    view_data["hits %"] = view_data["hits"] / (view_data["hits"] + view_data["misses"]) * 100
    view_data["misses %"] = view_data["misses"] / (view_data["hits"] + view_data["misses"]) * 100

    # Calculate QPS (Queries per second) over 5-minute intervals
    interval_seconds = 5 * 60
    view_data["qps"] = (view_data["hits_diff"] + view_data["misses_diff"]) / interval_seconds

    # Display the final DataFrame
    view_data = view_data.round(2)

    print(view_data.head(30))

    row = idx // 2 + 1
    col = idx % 2 + 1
    for metric in ['hits_diff', 'misses_diff', 'qps']:
        fig.add_trace(
            go.Scatter(
                x=view_data['time'],
                y=view_data[metric],
                mode='lines',
                name=metric_names[metric],
                legendgroup=metric,
                line=dict(
                    color=metric_colors[metric],
                    width=2.5,
                    shape='spline'
                ),
                hovertemplate='<b>' + metric_names[metric] + '</b><br>' +
                              'Time: %{x|%Y-%m-%d %H:%M:%S}<br>' +
                              'Value: %{y:,.2f}<br>' +
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
        'text': '<b>BIND DNS Cache Hit Ratio (CHR) Analysis</b><br>' +
                '<sub>Cache Performance Metrics by View: Hits, Misses, and QPS</sub>',
        'font': {'size': 20, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'x': 0.5,
        'xanchor': 'center',
        'y': 0.97,
        'yanchor': 'top',
        'pad': {'t': 10}
    },
    legend=dict(
        title={'text': '<b>Metrics</b>', 'font': {'size': 14}},
        orientation="h",
        x=0.5,
        y=-0.05,
        xanchor="center",
        yanchor="top",
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#CCCCCC',
        borderwidth=1,
        font={'size': 12}
    ),
    margin=dict(t=140, b=100, l=60, r=60),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified'
)

# Apply consistent axis styling to all subplots with dynamic y-axis ranges
for i, view in enumerate(unique_views, start=1):
    row = (i - 1) // 2 + 1
    col = (i - 1) % 2 + 1
    
    # Get view-specific data to calculate y-axis range
    view_data = df[df['view'] == view].copy()
    view_data["hits_diff"] = view_data["hits"].diff()
    view_data["misses_diff"] = view_data["misses"].diff()
    interval_seconds = 5 * 60
    view_data["qps"] = (view_data["hits_diff"] + view_data["misses_diff"]) / interval_seconds
    
    # Calculate dynamic y-axis range (exclude NaN and negative values for better scaling)
    all_values = pd.concat([
        view_data['hits_diff'].dropna(),
        view_data['misses_diff'].dropna(),
        view_data['qps'].dropna()
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
    
    # X-axis styling with date formatting
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
        tickformat=',.0f',
        range=y_range,  # Apply dynamic range
        row=row,
        col=col
    )

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=14, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.01

#
#fig = go.Figure()
#fig.add_trace(go.Scatter(x=df["time"], y=df["hits_diff"], mode="lines", name="hits"))
#fig.add_trace(go.Scatter(x=df["time"], y=df["misses_diff"], mode="lines", name="misses"))
#fig.add_trace(go.Scatter(x=df["time"], y=df["qps"], mode="lines", name="qps"))
#fig.update_layout(
#    height=600,
#    plot_bgcolor='white',
#    margin=dict(l=0, r=0, t=40, b=40),
#    font=dict(family="Inter, Arial, Helvetica, sans-serif", size=15, color="#222")
#)
#fig.update_xaxes(showgrid=False, showline=True, linecolor='black', linewidth=2)
#fig.update_yaxes(showgrid=False, showline=True, linecolor='black', linewidth=2)
#
pio.write_html(fig, file="bind_chr_dashboard.html", full_html=True)

print("✅ BIND CHR Dashboard saved as bind_chr_dashboard.html")
print("📊 Enhanced with modern aesthetic design")

# Prepare comprehensive table with calculated metrics for all views
table_data = []
view_tables_html = ""

for view in unique_views:
    view_data = df[df['view'] == view].copy()
    view_data = view_data.sort_values('time')
    
    # Calculate diff and qps for this view
    view_data["hits_diff"] = view_data["hits"].diff()
    view_data["misses_diff"] = view_data["misses"].diff()
    
    # Calculate percentages
    view_data["hit_pct"] = (view_data["hits"] / (view_data["hits"] + view_data["misses"]) * 100).round(2)
    view_data["miss_pct"] = (view_data["misses"] / (view_data["hits"] + view_data["misses"]) * 100).round(2)
    
    # Calculate QPS (Queries per second) over 5-minute intervals
    interval_seconds = 5 * 60
    view_data["qps"] = ((view_data["hits_diff"] + view_data["misses_diff"]) / interval_seconds).round(2)
    
    # Round diff columns
    view_data["hits_diff"] = view_data["hits_diff"].round(0)
    view_data["misses_diff"] = view_data["misses_diff"].round(0)
    
    table_data.append(view_data)
    
    # Select columns for display
    display_cols = ['time', 'size', 'hits', 'hits_diff', 'hit_pct', 'misses', 'misses_diff', 'miss_pct', 'qps']
    table_df = view_data[display_cols].copy()
    
    # Fill NaN values with empty string for better display
    table_df = table_df.fillna('')
    
    # Generate HTML table for this view
    html_table = table_df.to_html(classes="table table-striped text-center table-hover", index=False, justify='center', border=0)
    
    # Create view-specific section
    view_tables_html += f"""
    <div class="view-section">
        <div class="view-header">
            <h3>📊 View: <span class="view-name">{view}</span></h3>
            <div class="view-stats">
                Records: {len(table_df)} | Avg QPS: {table_df['qps'].replace('', 0).astype(float).mean():.2f} | 
                Avg Hit %: {table_df['hit_pct'].replace('', 0).astype(float).mean():.2f}%
            </div>
        </div>
        <div class="table-container">
            {html_table}
        </div>
    </div>
    """

# Combine all view data for overall stats
combined_df = pd.concat(table_data, ignore_index=False)

# Enhanced HTML content with modern aesthetic styling and separate tables per view
html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BIND CHR Data Table</title>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            font-family: 'Arial', 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            padding: 30px 20px;
            min-height: 100vh;
        }}
        .container {{
            max-width: 95%;
            margin: 0 auto;
        }}
        .main-header {{
            text-align: center;
            padding: 25px;
            background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%);
            color: white;
            font-size: 28px;
            font-weight: 600;
            margin-bottom: 30px;
            letter-spacing: 0.5px;
            border-radius: 12px 12px 0 0;
            box-shadow: 0 5px 20px rgba(0,0,0,0.2);
        }}
        .subtitle {{
            text-align: center;
            padding: 15px;
            background: #ECF0F1;
            color: #2C3E50;
            font-size: 14px;
            margin-bottom: 30px;
            border-radius: 0 0 12px 12px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
        }}
        .view-section {{
            background: #ffffff;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
            margin-bottom: 30px;
        }}
        .view-header {{
            background: linear-gradient(135deg, #34495E 0%, #2C3E50 100%);
            padding: 20px;
            color: white;
        }}
        .view-header h3 {{
            margin: 0 0 10px 0;
            font-size: 22px;
            font-weight: 600;
        }}
        .view-name {{
            color: #3498DB;
            font-weight: 700;
        }}
        .view-stats {{
            font-size: 13px;
            color: #ECF0F1;
            margin-top: 8px;
        }}
        .table-container {{
            width: 100%;
            max-height: 500px;
            overflow-y: auto;
            overflow-x: auto;
            border-top: 2px solid #34495E;
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
            font-size: 11px;
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
        .overall-stats {{
            padding: 20px;
            background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%);
            color: white;
            text-align: center;
            font-size: 14px;
            border-radius: 12px;
            margin-top: 20px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.2);
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="main-header">🌐 BIND DNS Cache Hit Ratio (CHR) Data</div>
        <div class="subtitle">
            DNS Cache Performance by View: Size, Hits, Misses, Percentages, and QPS
        </div>
        
        {view_tables_html}
        
        <div class="overall-stats">
            Total Views: {len(unique_views)} | Total Records: {len(combined_df)} | Last Updated: {combined_df['time'].max() if not combined_df.empty else 'N/A'}
        </div>
    </div>
</body>
</html>
"""

# Save to HTML file
with open("bind_chr_table.html", "w") as f:
    f.write(html_content)

print("✅ HTML table with modern design created: bind_chr_table.html")
EOF

python3 ${BIND_CHR_PY}

rm ${BIND_CHR_PY}

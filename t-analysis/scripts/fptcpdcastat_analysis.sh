#!/bin/bash

FPTCPDCASTAT_PY='fptcpdcastat_data.py'
FPTCPDCASTAT_LOG='fptcpdcastat_data.csv'

# Start the python script
cat <<EOF > ${FPTCPDCASTAT_PY}
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

# TCP_DCA_STAT pattern - assuming format like: TCP_DCA_STAT <ip_address> key1 value1 key2 value2 ...
fptcpdcastat_pattern = re.compile(r'TCP_DCA_STAT\s+(\S+)\s+(.*)')
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t 
    else:
        fptcp_match = fptcpdcastat_pattern.search(line)
        if fptcp_match and current_time:
            ip_address = fptcp_match.group(1)
            kv_string = fptcp_match.group(2)
            # Extract key-value pairs
            kv_pairs = re.findall(r'(\w+)\s+(\d+)', kv_string)
            record = {'datetime': current_time, 'ip': ip_address}
            for key, value in kv_pairs:
                record[key] = int(value)
            records.append(record)

df = create_dataframe(records, sort_by=['ip', 'datetime'])

if df.empty:
    print("⚠️  No FPTCPDCASTAT data found in logs!")
    print("Please check if the log files contain FPTCPDCASTAT entries.")
    sys.exit(0)

df['datetime'] = pd.to_datetime(df['datetime'])
df.to_csv('all_fptcpdcastat_data.csv', index=False)

print("📊 FPTCPDCASTAT Data Sample:")
print(df.head(10))
print(f"\n✅ Total records: {len(df)}")
print(f"📍 Unique IPs: {df['ip'].nunique()}")
print(f"📋 Available metrics: {[col for col in df.columns if col not in ['datetime', 'ip']]}")

# Get numeric columns (exclude datetime and ip)
numeric_cols = [col for col in df.columns if col not in ['datetime', 'ip']]

if not numeric_cols:
    print("⚠️  No numeric metrics found!")
    sys.exit(0)

# Calculate diffs for rate-based metrics
for col in numeric_cols:
    df[f'{col}_diff'] = df.groupby('ip')[col].diff().clip(lower=0)

# Modern color palette
color_palette = ['#3366CC', '#109618', '#DC3912', '#FF9900', '#990099', '#22AA99', 
                 '#DD4477', '#66AA00', '#0099C6', '#316395', '#994499', '#AAAA11']

# Get unique IPs
unique_ips = sorted(df['ip'].unique())

# Create subplots in 2-column layout
rows = (len(unique_ips) + 1) // 2
fig = make_subplots(
    rows=rows, 
    cols=2, 
    subplot_titles=[f'<b>{ip}</b>' for ip in unique_ips],
    vertical_spacing=0.14,
    horizontal_spacing=0.12
)

# Add traces for each IP
for idx, ip in enumerate(unique_ips):
    ip_data = df[df['ip'] == ip].sort_values('datetime')
    row = idx // 2 + 1
    col = idx % 2 + 1
    
    # Collect all values for dynamic y-axis scaling
    all_values = []
    
    # Plot diff metrics (rates)
    diff_cols = [c for c in df.columns if c.endswith('_diff')]
    for metric_idx, metric in enumerate(diff_cols):
        if metric in ip_data.columns:
            metric_values = ip_data[metric].clip(lower=0)
            all_values.extend(metric_values.tolist())
            
            display_name = metric.replace('_diff', '').replace('_', ' ').title()
            color = color_palette[metric_idx % len(color_palette)]
            
            fig.add_trace(
                go.Scatter(
                    x=ip_data['datetime'],
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
                    showlegend=(idx == 0)  # Show legend only for first IP
                ),
                row=row,
                col=col
            )
    
    # Calculate dynamic y-axis range for this IP
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
        'text': '<b>FPTCPDCASTAT Metrics by IP Address</b><br><sub>TCP DCA Statistics Over Time</sub>',
        'font': {'size': 24, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'x': 0.5,
        'xanchor': 'center',
        'y': 0.97
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
    margin=dict(t=170, b=150, l=70, r=70),
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    font={'family': 'Arial, sans-serif', 'color': '#2C3E50'},
    hovermode='x unified'
)

# Apply consistent axis styling to all subplots
for i in range(1, len(unique_ips) + 1):
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
        title_text='Rate',
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
    annotation['font'] = dict(size=13, color='#2C3E50', family='Arial, sans-serif', weight='bold')
    annotation['y'] = annotation['y'] + 0.003

# Build per-IP scrollable tables
table_metric_cols = [c for c in df.columns if c.endswith('_diff')]
ip_tables_html = []

for ip in unique_ips:
    ip_data = df[df['ip'] == ip].sort_values('datetime')

    table_df = pd.DataFrame({
        'Datetime': ip_data['datetime'].dt.strftime('%Y-%m-%d %H:%M:%S')
    })

    for col in table_metric_cols:
        if col in ip_data.columns:
            label = col.replace('_diff', '').replace('_', ' ').title()
            table_df[label] = ip_data[col].fillna(0).round(2)

    table_html = table_df.to_html(index=False, classes='ip-table ip-table--metric', border=0)
    ip_tables_html.append(f"""
    <div class=\"ip-table-card\">
        <h3>{ip}</h3>
        <div class=\"ip-table-scroll\">{table_html}</div>
    </div>
    """)

plot_html = fig.to_html(full_html=False, include_plotlyjs='cdn')

final_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset=\"utf-8\" />
    <title>FPTCPDCASTAT Dashboard</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 0;
            background: #FFFFFF;
            color: #2C3E50;
        }}
        .dashboard {{
            padding: 30px 24px 28px;
        }}
        .tables-title {{
            margin: 16px 0 14px;
            font-size: 21px;
            font-weight: 700;
            color: #1F2D3D;
        }}
        .ip-tables-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(520px, 1fr));
            gap: 16px;
        }}
        .ip-table-card {{
            border: 1px solid #D9E2EC;
            border-radius: 12px;
            background: linear-gradient(180deg, #FBFCFE 0%, #F7FAFD 100%);
            padding: 12px;
            box-shadow: 0 2px 10px rgba(31, 45, 61, 0.06);
        }}
        .ip-table-card h3 {{
            margin: 2px 6px 10px;
            font-size: 16px;
            font-weight: 700;
            color: #243447;
        }}
        .ip-table-scroll {{
            max-height: 320px;
            overflow-y: auto;
            overflow-x: auto;
            background: #FFFFFF;
            border: 1px solid #B8C7D9;
            border-radius: 8px;
        }}
        .ip-table-scroll::-webkit-scrollbar {{
            width: 10px;
            height: 10px;
        }}
        .ip-table-scroll::-webkit-scrollbar-thumb {{
            background: #C7D3E0;
            border-radius: 8px;
        }}
        .ip-table-scroll::-webkit-scrollbar-track {{
            background: #F1F5F9;
            border-radius: 8px;
        }}
        table.ip-table {{
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12px;
            border: 1px solid #C6D3E1;
        }}
        .ip-table th, .ip-table td {{
            border-bottom: 1px solid #D7E1EC;
            border-right: 1px solid #D7E1EC;
            padding: 8px 10px;
            text-align: left;
            white-space: nowrap;
        }}
        .ip-table th:last-child,
        .ip-table td:last-child {{
            border-right: 0;
        }}
        .ip-table th {{
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
        .ip-table tbody tr:nth-child(even) {{
            background: #FAFCFE;
        }}
        .ip-table tbody tr:hover {{
            background: #EEF5FD;
        }}
        .ip-table td:nth-child(n+2) {{
            text-align: right;
            font-variant-numeric: tabular-nums;
            color: #1F3A5A;
        }}
    </style>
</head>
<body>
    <div class=\"dashboard\">
        {plot_html}
        <h2 class=\"tables-title\">Per-IP Scrollable Tables</h2>
        <div class=\"ip-tables-grid\">
            {''.join(ip_tables_html)}
        </div>
    </div>
</body>
</html>
"""

with open('fptcpdcastat_dashboard.html', 'w', encoding='utf-8') as f:
    f.write(final_html)

print("\n✅ FPTCPDCASTAT Dashboard saved as fptcpdcastat_dashboard.html")
print("📊 Enhanced with dynamic y-axis scaling per IP for better visibility")
print("🎨 Features: Per-IP graphs, spline smoothing, negative value clipping, and aesthetic per-IP tables")
EOF

python3 ${FPTCPDCASTAT_PY}

rm ${FPTCPDCASTAT_PY}

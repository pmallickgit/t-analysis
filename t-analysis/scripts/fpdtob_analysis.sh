#!/bin/bash

FPDTOB_PY='fpdtob_data.py'
FPDTOB_LOG='fpdtob_data.csv'
GNUPLOT_FILE='plot_from_fpdtob.gp'

# Start the python script
cat <<EOF > ${FPDTOB_PY}
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

"""Parse FPDTOB logs and return a DataFrame with calculated diffs and QPS."""
raw_data = read_log_files(directory_path, "ptop-*.log")
time_pattern = re.compile(r"TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")
fpdtob_pattern = re.compile(r"FPDTOB\s+(.*)")
records = []
current_time = None

for line in raw_data.splitlines():
    t = extract_time(line, time_pattern)
    if t:
        current_time = t
    else:
        fpdtob_match = fpdtob_pattern.search(line)
        if fpdtob_match and current_time:
            kv_pairs = re.findall(r"(\w+)\s+(\d+)", fpdtob_match.group(1))
            record = {"datetime": current_time}
            for key, value in kv_pairs:
                record[key] = int(value)
            records.append(record)
df = create_dataframe(records, sort_by="datetime")
print(df.head())
df.to_csv('fpdtob_data.csv', index=False)

use_df=df
if not df.empty:
    df.set_index("datetime", inplace=True)
    df.sort_index(inplace=True)
    diff_df = df.diff().add_suffix("_diff")
    qps_df = pd.DataFrame()
    if "hit_diff" in diff_df.columns and "miss_diff" in diff_df.columns:
        qps_df["qps"] = (diff_df["hit_diff"] + diff_df["miss_diff"]) / 60
    final_df = pd.concat([df, diff_df, qps_df], axis=1)
    final_df = final_df.fillna(0)
    use_df = final_df

# Modern color palette for professional look
metric_colors = {
    'hit_diff': '#109618',      # Green
    'miss_diff': '#DC3912',     # Red
    'qps': '#3366CC',           # Royal Blue
    'input_diff': '#FF9900',    # Orange
    'output_diff': '#990099',   # Purple
    'drop_diff': '#DD4477',     # Pink
    'bypass_diff': '#22AA99',   # Teal
    'ouvin_diff': '#66AA00',    # Lime Green
}

# Friendly metric names for better readability
metric_names = {
    'hit_diff': 'Cache Hits/min',
    'miss_diff': 'Cache Misses/min',
    'qps': 'Queries Per Second',
    'input_diff': 'Input Packets/min',
    'output_diff': 'Output Packets/min',
    'drop_diff': 'Dropped Packets/min',
    'bypass_diff': 'Bypassed Packets/min',
    'ouvin_diff': 'OUVIN/min',
}

metric_columns = [col for col in use_df.columns if col.endswith("_diff") or col == "qps"]
default_colors = ['#3366CC', '#109618', '#DC3912', '#FF9900', '#990099', '#22AA99', '#DD4477', '#66AA00', '#0099C6', '#316395']

if not metric_columns:
    print("⚠️  No derived metrics (_diff/qps) found to plot")
    metric_columns = []

subplot_rows = max(1, (len(metric_columns) + 1) // 2)
fig = make_subplots(
    rows=subplot_rows,
    cols=2,
    subplot_titles=[f"<b>{metric_names.get(col, col)}</b>" for col in metric_columns],
    vertical_spacing=0.06,
    horizontal_spacing=0.10
)

for idx, col in enumerate(metric_columns):
    row = idx // 2 + 1
    col_pos = idx % 2 + 1

    metric_values = use_df[col].clip(lower=0)
    display_name = metric_names.get(col, col.replace('_diff', '').replace('_', ' ').title())
    color = metric_colors.get(col, default_colors[idx % len(default_colors)])

    fig.add_trace(
        go.Scatter(
            x=use_df.index,
            y=metric_values,
            mode='lines',
            name=display_name,
            line=dict(width=2.5, color=color, shape='spline'),
            connectgaps=True,
            hovertemplate='<b>%{fullData.name}</b><br>Time: %{x}<br>Value: %{y:,.2f}<extra></extra>',
            showlegend=True
        ),
        row=row,
        col=col_pos
    )

    positive_values = metric_values[metric_values > 0]
    if len(positive_values) > 0:
        y_max = positive_values.max()
        y_range = [0, y_max * 1.1]
    else:
        y_range = [0, 10]

    fig.update_yaxes(range=y_range, row=row, col=col_pos)

fig.update_layout(
    height=300 * subplot_rows,
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    margin=dict(l=80, r=80, t=165, b=130),
    title=dict(
        text="<b>FPDTOB Performance Metrics</b><br><sub>vDCA to BIND Traffic Analysis</sub>", 
        x=0.5, 
        xanchor='center',
        font=dict(size=24, color='#2C3E50', family='Arial Black, sans-serif'),
        y=0.99,
        yanchor='top',
        pad=dict(t=8, b=8)
    ),
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
    showlegend=True,
    font=dict(family="'Segoe UI', Arial, Helvetica, sans-serif", size=13, color="#34495E"),
    hovermode="x unified",
    hoverlabel=dict(
        bgcolor="white",
        font_size=12,
        font_family="Arial, sans-serif"
    )
)

for idx in range(len(metric_columns)):
    row = idx // 2 + 1
    col_pos = idx % 2 + 1

    fig.update_xaxes(
        showgrid=True,
        gridcolor='#E0E0E0',
        gridwidth=1,
        showline=True,
        mirror=True,
        linecolor='#34495E',
        linewidth=2,
        tickcolor='#34495E',
        ticklen=6,
        tickwidth=1.5,
        tickfont=dict(color='#2C3E50', size=11),
        type='date',
        title=dict(text='Time', font=dict(size=13, color='#2C3E50')),
        row=row,
        col=col_pos
    )

    fig.update_yaxes(
        showgrid=True,
        gridcolor='#E8E8E8',
        gridwidth=1,
        showline=True,
        mirror=True,
        linecolor='#34495E',
        linewidth=2,
        tickcolor='#34495E',
        ticklen=6,
        tickwidth=1.5,
        tickfont=dict(color='#2C3E50', size=11),
        zeroline=True,
        zerolinecolor='#BDC3C7',
        zerolinewidth=2,
        title=dict(text='Count', font=dict(size=13, color='#2C3E50')),
        row=row,
        col=col_pos
    )

# Build table data (Datetime + derived metrics)
table_source = use_df.copy()
if 'datetime' not in table_source.columns:
    table_source = table_source.reset_index()

table_cols = ['datetime'] + [c for c in table_source.columns if c.endswith('_diff') or c == 'qps']
table_cols = [c for c in table_cols if c in table_source.columns]
table_df = table_source[table_cols].copy() if table_cols else pd.DataFrame()

if not table_df.empty and 'datetime' in table_df.columns:
    table_df['datetime'] = pd.to_datetime(table_df['datetime']).dt.strftime('%Y-%m-%d %H:%M:%S')

# Friendly column names
rename_map = {'datetime': 'Datetime'}
for c in table_df.columns:
    if c in metric_names:
        rename_map[c] = metric_names[c]
table_df.rename(columns=rename_map, inplace=True)

for c in table_df.columns:
    if c != 'Datetime':
        table_df[c] = pd.to_numeric(table_df[c], errors='coerce').fillna(0).round(2)

table_html = table_df.to_html(index=False, classes='fpdtob-table', border=0) if not table_df.empty else '<p class="empty-msg">No table data available.</p>'

plot_html = fig.to_html(full_html=False, include_plotlyjs='cdn')

final_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset=\"utf-8\" />
    <title>FPDTOB Dashboard</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 0;
            background: #FFFFFF;
            color: #2C3E50;
        }}
        .dashboard {{
            padding: 24px 24px 28px;
        }}
        .table-title {{
            margin: 16px 0 12px;
            font-size: 21px;
            font-weight: 700;
            color: #1F2D3D;
        }}
        .table-card {{
            border: 1px solid #D9E2EC;
            border-radius: 12px;
            background: linear-gradient(180deg, #FBFCFE 0%, #F7FAFD 100%);
            padding: 12px;
            box-shadow: 0 2px 10px rgba(31, 45, 61, 0.06);
        }}
        .table-scroll {{
            max-height: 360px;
            overflow-y: auto;
            overflow-x: auto;
            background: #FFFFFF;
            border: 1px solid #B8C7D9;
            border-radius: 8px;
        }}
        .table-scroll::-webkit-scrollbar {{
            width: 10px;
            height: 10px;
        }}
        .table-scroll::-webkit-scrollbar-thumb {{
            background: #C7D3E0;
            border-radius: 8px;
        }}
        .table-scroll::-webkit-scrollbar-track {{
            background: #F1F5F9;
            border-radius: 8px;
        }}
        table.fpdtob-table {{
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12px;
            border: 1px solid #C6D3E1;
        }}
        .fpdtob-table th, .fpdtob-table td {{
            border-bottom: 1px solid #D7E1EC;
            border-right: 1px solid #D7E1EC;
            padding: 8px 10px;
            text-align: left;
            white-space: nowrap;
        }}
        .fpdtob-table th:last-child,
        .fpdtob-table td:last-child {{
            border-right: 0;
        }}
        .fpdtob-table th {{
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
        .fpdtob-table tbody tr:nth-child(even) {{
            background: #FAFCFE;
        }}
        .fpdtob-table tbody tr:hover {{
            background: #EEF5FD;
        }}
        .fpdtob-table td:nth-child(n+2) {{
            text-align: right;
            font-variant-numeric: tabular-nums;
            color: #1F3A5A;
        }}
        .empty-msg {{
            margin: 8px;
            color: #52667A;
        }}
    </style>
</head>
<body>
    <div class=\"dashboard\">
        {plot_html}
        <h2 class=\"table-title\">FPDTOB Scrollable Metrics Table</h2>
        <div class=\"table-card\">
            <div class=\"table-scroll\">{table_html}</div>
        </div>
    </div>
</body>
</html>
"""

with open("fpdtob_dashboard.html", "w", encoding="utf-8") as f:
    f.write(final_html)

print("✅ FPDTOB Dashboard saved as fpdtob_dashboard.html")
print("📊 Enhanced with modern aesthetic design, dynamic scaling, and a scrollable metrics table")
print("🎨 Features: Spline smoothing, color-coded metrics, optimized y-axis ranges, and aesthetic table UI")
EOF

python3 ${FPDTOB_PY}

rm ${FPDTOB_PY}
rm ${FPDTOB_LOG}

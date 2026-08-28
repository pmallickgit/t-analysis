#!/bin/bash

FPRRSTAT_PY='fprrstat_data.py'
FPRRSTAT_LOG='fprrstat_data.csv'
GNUPLOT_FILE='plot_from_fprrstat.gp'

# Start the python script
cat <<EOF > ${FPRRSTAT_PY}

import pandas as pd
import plotly.graph_objects as go
import re
from datetime import datetime
import glob
import os
import sys
import plotly.io as pio
import plotly.express as px
from plotly.subplots import make_subplots

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

# Step 1: Read all files matching the pattern 'data*.log'
log_files = sorted(glob.glob(os.path.join(directory_path, "ptop*.log")))

# Patterns
# FPRRSTATS REQ A 0 AAAA 0 MX 0 PTR 0 CNAME 0 TYPE64 0 TYPE65 0 RES A 0 AAAA 0 MX 0 PTR 0 CNAME 0 TYPE64 0 TYPE65 0
time_pattern = re.compile(r"TIME\s+\S+\s+\S+\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})")
#mem_pattern = re.compile(r"MEM\s+t\s+\d+\s+f\s+([\d.]+)\s+b\s+\d+\s+c\s+\d+\s+s\s+\d+\s+a\s+([\d.]+)\s+sh\s+\d+\s+sw\s+([\d.]+)\s+\d+\s+h\s+\d+\s+\d+\s+pio\s+([\d.]+)\s+\d+\s+sio\s+([\d.]+)\s+\d+")
#rrstat_pattern = re.compile(r"FPRRSTATS REQ A\s+(\d+)\s+AAAA\s+(\d+)\s+MX\s+(\d+)\s+PTR\s+(\d+)\s+CNAME\s+(\d+)\s+TYPE64\s+(\d+)\s+TYPE65\s+(\d+)\s+RES\s+A\s+(\d+)\s+AAAA\s+(\d+)\s+MX\s+(\d+)\s+PTR\s+(\d+)\s+CNAME\s+(\d+)\s+TYPE64\s+(\d+)\s+TYPE65\s+(\d+)")
rrstat_pattern = re.compile(
    r"FPRRSTATS REQ A (?P<req_A>\d+)"
    r"\s+AAAA (?P<req_AAAA>\d+)"
    r"\s+MX (?P<req_MX>\d+)"
    r"\s+PTR (?P<req_PTR>\d+)"
    r"\s+CNAME (?P<req_CNAME>\d+)"
    r"\s+TYPE64 (?P<req_TYPE64>\d+)"
    r"\s+TYPE65 (?P<req_TYPE65>\d+)"
    r"\s+RES A (?P<res_A>\d+)"
    r"\s+AAAA (?P<res_AAAA>\d+)"
    r"\s+MX (?P<res_MX>\d+)"
    r"\s+PTR (?P<res_PTR>\d+)"
    r"\s+CNAME (?P<res_CNAME>\d+)"
    r"\s+TYPE64 (?P<res_TYPE64>\d+)"
    r"\s+TYPE65 (?P<res_TYPE65>\d+)"
)

# Prepare list to hold parsed data
records = []

# Parse each TIME and FPRRSTAT line
raw_data = ""
for file in log_files:
    with open(file, "r", encoding="utf-8", errors="ignore") as f:
        raw_data += f.read() + "\n"

lines = raw_data.splitlines()
current_time = None

for line in lines:
    time_match = time_pattern.search(line)

    if time_match:
        date_str, time_str = time_match.groups()
        current_time = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M:%S")
    else:
        rrstat_match = rrstat_pattern.search(line)
        if rrstat_match and current_time:
            extracted_data = rrstat_match.groupdict()

            for key, value in extracted_data.items():
                extracted_data[key] = int(value)

            rrstat_qa  = extracted_data['req_A']
            rrstat_qaaaa  = extracted_data['req_AAAA']
            rrstat_qmx  = extracted_data['req_MX']
            rrstat_qptr  = extracted_data['req_PTR']
            rrstat_qcname  = extracted_data['req_CNAME']
            rrstat_qtype64  = extracted_data['req_TYPE64']
            rrstat_qtype65  = extracted_data['req_TYPE65']

            rrstat_ra  = extracted_data['res_A']
            rrstat_raaaa  = extracted_data['res_AAAA']
            rrstat_rmx  = extracted_data['res_MX']
            rrstat_rptr  = extracted_data['res_PTR']
            rrstat_rcname  = extracted_data['res_CNAME']
            rrstat_rtype64  = extracted_data['res_TYPE64']
            rrstat_rtype65  = extracted_data['res_TYPE65']

            records.append({
                'datetime': current_time,
                'q_a': rrstat_qa,
                'q_aaaa': rrstat_qaaaa,
                'q_mx': rrstat_qmx,
                'q_ptr': rrstat_qptr,
                'q_cname': rrstat_qcname,
                'q_type64': rrstat_qtype64,
                'q_type65': rrstat_qtype65,

                'r_a': rrstat_ra,
                'r_aaaa': rrstat_raaaa,
                'r_mx': rrstat_rmx,
                'r_ptr': rrstat_rptr,
                'r_cname': rrstat_rcname,
                'r_type64': rrstat_rtype64,
                'r_type65': rrstat_rtype65,
            })

# Create DataFrame
df = pd.DataFrame(records)

# Exit early if no data found
if df.empty:
    print("⚠️  No FPRRSTATS data found in ptop logs!")
    print("Please check if the log files contain FPRRSTATS entries.")
    sys.exit(0)

#df.set_index("datetime", inplace=True)
#df.sort_index(inplace=True)

# Only compute diffs if columns exist
diff_cols = [
    'q_a', 'q_aaaa', 'q_mx', 'q_ptr', 'q_cname', 'q_type64', 'q_type65',
    'r_a', 'r_aaaa', 'r_mx', 'r_ptr', 'r_cname', 'r_type64', 'r_type65'
]
for col in diff_cols:
    if col in df.columns:
        df[f'{col}_d'] = df[col].diff()
df = df.fillna(0)
print(df.head())

# Modern color palette with better aesthetics
metric_colors = {
    'query': {
        'A': '#3366CC',       # Royal Blue
        'AAAA': '#109618',    # Green
        'MX': '#FF9900',      # Orange
        'PTR': '#DC3912',     # Red
        'CNAME': '#990099',   # Purple
        'TYPE64': '#22AA99',  # Teal
        'TYPE65': '#DD4477'   # Pink
    },
    'response': {
        'A': '#5B8BD0',       # Lighter Blue
        'AAAA': '#2DB12D',    # Lighter Green
        'MX': '#FFB84D',      # Lighter Orange
        'PTR': '#E85C5C',     # Lighter Red
        'CNAME': '#B84DB8',   # Lighter Purple
        'TYPE64': '#4DC4BA',  # Lighter Teal
        'TYPE65': '#E87696'   # Lighter Pink
    }
}

metric_names = [
    ("A", "q_a_d", "r_a_d"),
    ("AAAA", "q_aaaa_d", "r_aaaa_d"),
    ("MX", "q_mx_d", "r_mx_d"),
    ("PTR", "q_ptr_d", "r_ptr_d"),
    ("CNAME", "q_cname_d", "r_cname_d"),
    ("TYPE64", "q_type64_d", "r_type64_d"),
    ("TYPE65", "q_type65_d", "r_type65_d"),
]

# Create 2-column layout (4 rows, with last row having only 1 graph)
rows = 4
fig = make_subplots(
    rows=rows, cols=2, 
    shared_xaxes=False,
    subplot_titles=[f"<b>{name} Record Type</b> - Query vs Response" for name, _, _ in metric_names],
    vertical_spacing=0.08,
    horizontal_spacing=0.10
)

# Check for required columns
if 'datetime' not in df.columns:
     print("No 'datetime' column found in RRSTAT data. Please check your log files.")

for i, (name, q_col, r_col) in enumerate(metric_names, 1):
    if q_col not in df.columns or r_col not in df.columns:
        continue  # Skip missing metrics
    
    # Calculate row and column for 2-column layout
    row = (i - 1) // 2 + 1
    col = (i - 1) % 2 + 1
    
    # Clip negative values to zero (negative diffs are artifacts from counter resets)
    q_values = df[q_col].clip(lower=0)
    r_values = df[r_col].clip(lower=0)
    
    fig.add_trace(
        go.Scatter(
            x=df["datetime"], 
            y=q_values, 
            mode='lines',
            name=f"{name} Query", 
            line=dict(color=metric_colors['query'][name], width=2.5, shape='spline'),
            legendgroup=name,
            hovertemplate=f"<b>{name} Query</b><br>Time: %{{x|%Y-%m-%d %H:%M:%S}}<br>Value: %{{y:,.0f}}<extra></extra>"
        ), row=row, col=col
    )
    fig.add_trace(
        go.Scatter(
            x=df["datetime"], 
            y=r_values, 
            mode='lines',
            name=f"{name} Response", 
            line=dict(color=metric_colors['response'][name], width=2.5, dash='dash', shape='spline'),
            legendgroup=name,
            hovertemplate=f"<b>{name} Response</b><br>Time: %{{x|%Y-%m-%d %H:%M:%S}}<br>Value: %{{y:,.0f}}<extra></extra>"
        ), row=row, col=col
    )
    
    # Calculate dynamic y-axis range for this subplot using clipped values
    subplot_values = pd.concat([q_values, r_values]).dropna()
    positive_values = subplot_values[subplot_values > 0]
    
    if len(positive_values) > 0:
        y_max = positive_values.max()
        y_min = 0  # Always start from 0 for cleaner visualization
        y_range = [y_min, y_max * 1.1]
    else:
        y_range = [0, 1]  # Default range if no positive values
    
    # Apply styling to this subplot's axes
    fig.update_xaxes(
        type='date',
        showgrid=True,
        gridcolor='#E5E5E5',
        gridwidth=1,
        showline=True,
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickfont=dict(color='#34495E', size=10),
        row=row, col=col
    )
    
    fig.update_yaxes(
        showgrid=True,
        gridcolor='#E5E5E5',
        gridwidth=1,
        showline=True,
        linecolor='#34495E',
        linewidth=1.5,
        mirror=True,
        ticks='outside',
        ticklen=5,
        tickcolor='#34495E',
        tickfont=dict(color='#34495E', size=10),
        zeroline=True,
        zerolinecolor='#CCCCCC',
        zerolinewidth=1.5,
        tickformat=',.0f',
        range=y_range,
        row=row, col=col
    )

fig.update_layout(
    height=300 * rows,
    plot_bgcolor='#FAFAFA',
    paper_bgcolor='#FFFFFF',
    margin=dict(l=80, r=80, t=120, b=150),
    title={
        'text': '<b>DNS RRSet Statistics Dashboard</b><br>' +
                '<sub>Query and Response Metrics by Record Type</sub>',
        'x': 0.5,
        'xanchor': 'center',
        'font': {'size': 22, 'color': '#2C3E50', 'family': 'Arial, sans-serif'},
        'y': 0.98,
        'yanchor': 'top',
        'pad': {'t': 10}
    },
    legend=dict(
        title={'text': '<b>Metrics</b>', 'font': {'size': 14}},
        orientation="h",
        yanchor="top",
        y=-0.15,
        xanchor="center",
        x=0.5,
        bgcolor='rgba(255, 255, 255, 0.95)',
        bordercolor='#CCCCCC',
        borderwidth=1,
        font={'size': 11}
    ),
    font={'family': 'Arial, sans-serif', 'size': 12, 'color': '#2C3E50'},
    hovermode="x unified"
)

# Update subplot title styling
for annotation in fig['layout']['annotations']:
    annotation['font'] = dict(size=13, color='#2C3E50', family='Arial, sans-serif')
    annotation['y'] = annotation['y'] + 0.005

# Build a scrollable table for each RR type
rr_tables_html = []
for name, q_col, r_col in metric_names:
    if q_col not in df.columns or r_col not in df.columns:
        continue

    q_values = df[q_col].clip(lower=0)
    r_values = df[r_col].clip(lower=0)
    table_df = pd.DataFrame({
        "Datetime": df["datetime"].dt.strftime("%Y-%m-%d %H:%M:%S"),
        "Query Delta": q_values.astype(int),
        "Response Delta": r_values.astype(int)
    })

    table_html = table_df.to_html(index=False, classes="rr-table rr-table--metric", border=0)
    rr_tables_html.append(f"""
    <div class=\"rr-table-card\">
        <h3>{name} Record Type</h3>
        <div class=\"rr-table-scroll\">{table_html}</div>
    </div>
    """)

plot_html = fig.to_html(full_html=False, include_plotlyjs='cdn')
final_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset=\"utf-8\" />
    <title>DNS RRSet Statistics Dashboard</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 0;
            background: #FFFFFF;
            color: #2C3E50;
        }}
        .dashboard {{
            padding: 16px 24px 28px;
        }}
        .tables-title {{
            margin: 18px 0 14px;
            font-size: 21px;
            font-weight: 700;
            color: #1F2D3D;
        }}
        .rr-tables-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(420px, 1fr));
            gap: 16px;
        }}
        .rr-table-card {{
            border: 1px solid #D9E2EC;
            border-radius: 12px;
            background: linear-gradient(180deg, #FBFCFE 0%, #F7FAFD 100%);
            padding: 12px;
            box-shadow: 0 2px 10px rgba(31, 45, 61, 0.06);
        }}
        .rr-table-card h3 {{
            margin: 2px 6px 10px;
            font-size: 16px;
            font-weight: 700;
            color: #243447;
        }}
        .rr-table-scroll {{
            max-height: 300px;
            overflow-y: auto;
            overflow-x: auto;
            background: #FFFFFF;
            border: 1px solid #B8C7D9;
            border-radius: 8px;
        }}
        .rr-table-scroll::-webkit-scrollbar {{
            width: 10px;
            height: 10px;
        }}
        .rr-table-scroll::-webkit-scrollbar-thumb {{
            background: #C7D3E0;
            border-radius: 8px;
        }}
        .rr-table-scroll::-webkit-scrollbar-track {{
            background: #F1F5F9;
            border-radius: 8px;
        }}
        table.rr-table {{
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12px;
            border: 1px solid #C6D3E1;
        }}
        .rr-table th, .rr-table td {{
            border-bottom: 1px solid #D7E1EC;
            border-right: 1px solid #D7E1EC;
            padding: 8px 10px;
            text-align: left;
            white-space: nowrap;
        }}
        .rr-table th:last-child,
        .rr-table td:last-child {{
            border-right: 0;
        }}
        .rr-table th {{
            position: sticky;
            top: 0;
            background-color: #DCE9F7;
            z-index: 1;
            text-transform: uppercase;
            letter-spacing: 0.03em;
            font-size: 11px;
            color: #334E68;
            border-bottom: 2px solid #AFC3D8;
        }}
        .rr-table tbody tr:nth-child(even) {{
            background: #FAFCFE;
        }}
        .rr-table tbody tr:hover {{
            background: #EEF5FD;
        }}
        .rr-table td:nth-child(2),
        .rr-table td:nth-child(3) {{
            text-align: right;
            font-variant-numeric: tabular-nums;
            color: #1F3A5A;
        }}
    </style>
</head>
<body>
    <div class=\"dashboard\">
        {plot_html}
        <h2 class=\"tables-title\">Per-RR Scrollable Tables</h2>
        <div class=\"rr-tables-grid\">
            {''.join(rr_tables_html)}
        </div>
    </div>
</body>
</html>
"""

with open("fprrstat_dashboard.html", "w", encoding="utf-8") as f:
    f.write(final_html)

print("✅ DNS RRSet Statistics Dashboard saved as fprrstat_dashboard.html")
print("📊 Enhanced with modern aesthetic design, dynamic scaling, and per-RR scrollable tables")
EOF

python3 ${FPRRSTAT_PY}

rm ${FPRRSTAT_PY}

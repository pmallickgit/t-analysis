#!/bin/bash

INFOBLOX_PY='infoblox_data.py'
INFOBLOX_LOG='infoblox.log'

# Start the python script
cat <<'EOF' > ${INFOBLOX_PY}
import re
import sys
import csv
from datetime import datetime
from collections import Counter, defaultdict

# Check if log file exists
try:
    with open('infoblox.log', 'r', encoding='utf-8', errors='ignore') as f:
        raw_data = f.read()
except FileNotFoundError:
    print("❌ Error: infoblox.log not found")
    print("Please check the file path and try again.")
    sys.exit(1)

print(f"📄 Reading Infoblox log file: infoblox.log")
print(f"📊 File size: {len(raw_data):,} bytes")

# Initialize data structures
all_events = []
process_counts = defaultdict(int)
hourly_events = defaultdict(int)
event_types = defaultdict(int)

# Patterns
timestamp_pattern = re.compile(r'\[(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})\.\d+\]')
process_pattern = re.compile(r'\((\d+)\s+([^)]+)\)\s*:?\s*(.+)')  # Made colon optional
error_pattern = re.compile(r'(error|failed|fail|denied|timeout|critical)', re.IGNORECASE)
warning_pattern = re.compile(r'(warning|warn)', re.IGNORECASE)
appliance_reboot_pattern = re.compile(r'Appliance REBOOT')
system_restart_pattern = re.compile(r'System restart')
service_restart_pattern = re.compile(r'(starting|started|stopping|stopped|restarting)', re.IGNORECASE)
database_pattern = re.compile(r'(database|db_|onedb|mysql)', re.IGNORECASE)
mount_pattern = re.compile(r'(mount|unmount)', re.IGNORECASE)

lines = raw_data.splitlines()
print(f"📝 Total log lines: {len(lines):,}")

# Process each line
processed_lines = 0
for line_num, line in enumerate(lines, 1):
    # Extract timestamp
    timestamp = None
    ts_match = timestamp_pattern.search(line)
    if ts_match:
        try:
            ts_str = ts_match.group(1)
            timestamp = datetime.strptime(ts_str, "%Y/%m/%d %H:%M:%S")
        except:
            pass
    
    if not timestamp:
        continue
    
    processed_lines += 1
    
    # Extract process info
    process_match = process_pattern.search(line)
    if process_match:
        pid = process_match.group(1)
        process_path = process_match.group(2)
        message = process_match.group(3).strip()
        
        # Get process name from path
        process_name = process_path.split('/')[-1] if '/' in process_path else process_path
        
        # Classify event type with specific priority
        event_type = 'INFO'
        if appliance_reboot_pattern.search(message):
            event_type = 'APPLIANCE_REBOOT'
        elif system_restart_pattern.search(message):
            event_type = 'SYSTEM_RESTART'
        elif error_pattern.search(message):
            event_type = 'ERROR'
        elif warning_pattern.search(message):
            event_type = 'WARNING'
        elif database_pattern.search(message):
            event_type = 'DATABASE'
        elif mount_pattern.search(message):
            event_type = 'MOUNT'
        elif service_restart_pattern.search(message):
            event_type = 'SERVICE_RESTART'
        
        # Store event
        all_events.append({
            'datetime': timestamp,
            'pid': pid,
            'process_name': process_name,
            'process_path': process_path,
            'event_type': event_type,
            'message': message[:200]  # Truncate long messages
        })
        
        # Count process occurrences
        process_counts[process_name] += 1
        
        # Count events by hour
        hour_key = timestamp.strftime('%Y-%m-%d %H:00:00')
        hourly_events[hour_key] += 1
        
        # Count event types
        event_types[event_type] += 1

print(f"✅ Processed {processed_lines:,} lines with timestamps")
print(f"📊 Captured {len(all_events):,} events")

# Sort events by datetime
all_events.sort(key=lambda x: x['datetime'])

# Save to CSV
with open('all_infoblox_data.csv', 'w', newline='', encoding='utf-8') as csvfile:
    if all_events:
        fieldnames = ['datetime', 'pid', 'process_name', 'process_path', 'event_type', 'message']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for event in all_events:
            writer.writerow({
                'datetime': event['datetime'].strftime('%Y-%m-%d %H:%M:%S'),
                'pid': event['pid'],
                'process_name': event['process_name'],
                'process_path': event['process_path'],
                'event_type': event['event_type'],
                'message': event['message']
            })
print(f"💾 Saved all events to all_infoblox_data.csv")

# Calculate statistics
if all_events:
    min_time = min(e['datetime'] for e in all_events)
    max_time = max(e['datetime'] for e in all_events)
    duration = max_time - min_time
else:
    min_time = max_time = duration = None

# Print summary statistics
print("\n" + "="*80)
print("SUMMARY STATISTICS")
print("="*80)
if all_events:
    print(f"\n📅 Time Range:")
    print(f"   Start: {min_time}")
    print(f"   End:   {max_time}")
    print(f"   Duration: {duration}")

    print(f"\n📊 Event Type Distribution:")
    for event_type, count in sorted(event_types.items(), key=lambda x: x[1], reverse=True):
        print(f"   {event_type:12s}: {count:,}")

    print(f"\n🔝 Top 10 Processes by Activity:")
    for process, count in sorted(process_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"   {process[:30]:30s}: {count:,}")

# Generate HTML Report
errors = [e for e in all_events if e['event_type'] == 'ERROR'][:50]
warnings = [e for e in all_events if e['event_type'] == 'WARNING'][:50]
appliance_reboots = [e for e in all_events if e['event_type'] == 'APPLIANCE_REBOOT']
system_restarts = [e for e in all_events if e['event_type'] == 'SYSTEM_RESTART']
service_restarts = [e for e in all_events if e['event_type'] == 'SERVICE_RESTART']
databases = [e for e in all_events if e['event_type'] == 'DATABASE'][:30]

# Create hierarchical structure for reboots/restarts
# Group service restarts that occur within 5 minutes after a major reboot/restart
from datetime import timedelta

def group_service_restarts(major_events, all_events_list, window_minutes=5):
    """Group errors, warnings, and failures under major reboot/restart events"""
    # Compile patterns for filtering
    error_keywords = re.compile(r'(error|failed|fail|denied|timeout|critical)', re.IGNORECASE)
    warning_keywords = re.compile(r'(warning|warn)', re.IGNORECASE)
    
    grouped = []
    for major_event in major_events:
        major_time = major_event['datetime']
        # Find important events within the time window after this major event
        related_services = []
        for event in all_events_list:
            service_time = event['datetime']
            time_diff = service_time - major_time
            # Check if event is within 0 to window_minutes after major event
            if timedelta(0) <= time_diff <= timedelta(minutes=window_minutes):
                # Only include ERROR, WARNING events or events with error/warning/failure keywords
                if (event['event_type'] in ['ERROR', 'WARNING'] or 
                    error_keywords.search(event['message']) or 
                    warning_keywords.search(event['message'])):
                    related_services.append(event)
        
        grouped.append({
            'major_event': major_event,
            'service_restarts': related_services
        })
    
    return grouped

appliance_reboot_groups = group_service_restarts(appliance_reboots, all_events)
system_restart_groups = group_service_restarts(system_restarts, all_events)

# Add event type to each group for identification
for group in appliance_reboot_groups:
    group['event_type'] = 'Appliance REBOOT'
    group['event_short'] = 'AR'
    
for group in system_restart_groups:
    group['event_type'] = 'System Restart'
    group['event_short'] = 'SR'

# Combine and sort all reboot/restart events chronologically (oldest first)
combined_reboot_restart_groups = appliance_reboot_groups + system_restart_groups
combined_reboot_restart_groups.sort(key=lambda x: x['major_event']['datetime'])

# Analyze process lifecycle across reboots/restarts
def analyze_process_lifecycle(all_events_list, reboot_restart_list):
    """Analyze process lifecycle: started, stopped, running time across reboots"""
    # Keywords to identify lifecycle events
    started_keywords = re.compile(r'(started|starting|initialized|init|begin)', re.IGNORECASE)
    stopped_keywords = re.compile(r'(stopped|stopping|terminated|shutdown|killed|exit)', re.IGNORECASE)
    
    # Group all reboot/restart events by time for context
    reboot_times = sorted([e['datetime'] for e in reboot_restart_list])
    
    # Track process lifecycle by process name
    process_lifecycle = defaultdict(list)
    
    # Track service restarts by process name
    service_restarts = defaultdict(list)
    
    for event in all_events_list:
        process_name = event['process_name']
        timestamp = event['datetime']
        message = event['message']
        event_type = event.get('event_type', 'INFO')
        
        # Track service restart events
        if event_type == 'SERVICE_RESTART':
            service_restarts[process_name].append({
                'timestamp': timestamp,
                'message': message[:100],
                'pid': event['pid']
            })
        
        # Determine event state
        state = None
        if started_keywords.search(message):
            state = 'STARTED'
        elif stopped_keywords.search(message):
            state = 'STOPPED'
        
        if state:
            # Find which reboot/restart period this belongs to
            period_index = 0
            for i, reboot_time in enumerate(reboot_times):
                if timestamp >= reboot_time:
                    period_index = i
                else:
                    break
            
            process_lifecycle[process_name].append({
                'timestamp': timestamp,
                'state': state,
                'message': message[:100],
                'pid': event['pid'],
                'period_index': period_index,
                'reboot_time': reboot_times[period_index] if period_index < len(reboot_times) else None
            })
    
    # Calculate runtime and startup times
    process_summary = {}
    for process_name, events in process_lifecycle.items():
        if len(events) < 2:
            continue  # Need at least 2 events to calculate duration
        
        # Sort by timestamp
        events.sort(key=lambda x: x['timestamp'])
        
        # Calculate periods between starts and stops
        periods = []
        start_event = None
        
        for event in events:
            if event['state'] == 'STARTED':
                if start_event is None:
                    start_event = event
            elif event['state'] == 'STOPPED' and start_event is not None:
                duration = event['timestamp'] - start_event['timestamp']
                
                # Find service restarts during this period
                restarts_during_period = []
                if process_name in service_restarts:
                    restarts_during_period = [
                        r for r in service_restarts[process_name]
                        if start_event['timestamp'] <= r['timestamp'] <= event['timestamp']
                    ]
                
                periods.append({
                    'start': start_event['timestamp'],
                    'stop': event['timestamp'],
                    'duration': duration,
                    'startup_time': (start_event['timestamp'] - start_event['reboot_time']).total_seconds() if start_event['reboot_time'] else None,
                    'period_index': start_event['period_index'],
                    'service_restarts': restarts_during_period
                })
                start_event = None
        
        if periods:
            avg_runtime = sum([p['duration'].total_seconds() for p in periods]) / len(periods)
            avg_startup = sum([p['startup_time'] for p in periods if p['startup_time'] is not None]) / len([p for p in periods if p['startup_time'] is not None]) if any(p['startup_time'] is not None for p in periods) else None
            
            process_summary[process_name] = {
                'total_cycles': len(periods),
                'periods': periods,
                'avg_runtime_seconds': avg_runtime,
                'avg_startup_seconds': avg_startup,
                'last_start': events[-1]['timestamp'] if events[-1]['state'] == 'STARTED' else None
            }
    
    # Sort by total cycles (most active processes first)
    sorted_processes = sorted(process_summary.items(), key=lambda x: x[1]['total_cycles'], reverse=True)[:20]
    
    return sorted_processes

process_lifecycle_data = analyze_process_lifecycle(all_events, appliance_reboots + system_restarts)

# Create timeline data for reboot/restart events
timeline_events = []
for event in appliance_reboots:
    timeline_events.append({
        'datetime': event['datetime'],
        'type': 'APPLIANCE_REBOOT',
        'label': 'AR',
        'full_label': 'Appliance REBOOT',
        'color': '#DC3912'  # Red color
    })
for event in system_restarts:
    timeline_events.append({
        'datetime': event['datetime'],
        'type': 'SYSTEM_RESTART',
        'label': 'SR',
        'full_label': 'System Restart',
        'color': '#7FB3D5'  # Faded blue color
    })

# Sort timeline events by datetime
timeline_events.sort(key=lambda x: x['datetime'])

# Calculate time intervals between events with collision detection
timeline_html_items = []
if timeline_events:
    first_event_time = timeline_events[0]['datetime']
    last_event_time = timeline_events[-1]['datetime']
    total_duration = (last_event_time - first_event_time).total_seconds()
    
    # Calculate initial positions
    event_positions = []
    for i, event in enumerate(timeline_events):
        if total_duration > 0:
            time_from_start = (event['datetime'] - first_event_time).total_seconds()
            position_pct = (time_from_start / total_duration) * 100
        else:
            position_pct = i * 5  # Spread evenly if all at same time
        event_positions.append(position_pct)
    
    # Adjust positions to avoid collisions (minimum 2% gap, roughly 20px on 1000px width)
    min_gap_pct = 2.0
    for i in range(len(event_positions) - 1):
        if event_positions[i + 1] - event_positions[i] < min_gap_pct:
            event_positions[i + 1] = event_positions[i] + min_gap_pct
    
    # Normalize if we went over 100%
    if event_positions[-1] > 100:
        scale_factor = 100 / event_positions[-1]
        event_positions = [pos * scale_factor for pos in event_positions]
    
    # Generate HTML for each event
    for i, event in enumerate(timeline_events):
        position_pct = event_positions[i]
        
        # Calculate time from previous event for tooltip
        if i > 0:
            prev_event = timeline_events[i - 1]
            time_from_prev = (event['datetime'] - prev_event['datetime']).total_seconds()
            
            days = int(time_from_prev // 86400)
            hours = int((time_from_prev % 86400) // 3600)
            minutes = int((time_from_prev % 3600) // 60)
            
            if days > 0:
                time_from_prev_str = f"{days}d {hours}h {minutes}m"
            elif hours > 0:
                time_from_prev_str = f"{hours}h {minutes}m"
            else:
                time_from_prev_str = f"{minutes}m"
            
            tooltip_text = f"{event['full_label']}\nTime: {event['datetime'].strftime('%Y-%m-%d %H:%M:%S')}\nTime from previous: {time_from_prev_str}"
        else:
            tooltip_text = f"{event['full_label']}\nTime: {event['datetime'].strftime('%Y-%m-%d %H:%M:%S')}\nFirst event in timeline"
        
        # Calculate duration until next event (bar length)
        if i < len(timeline_events) - 1:
            next_position_pct = event_positions[i + 1]
            duration_pct = next_position_pct - position_pct
            
            # Calculate actual time duration for label
            next_event = timeline_events[i + 1]
            duration_seconds = (next_event['datetime'] - event['datetime']).total_seconds()
            
            days = int(duration_seconds // 86400)
            hours = int((duration_seconds % 86400) // 3600)
            minutes = int((duration_seconds % 3600) // 60)
            
            if days > 0:
                duration_str = f"{days}d {hours}h"
            elif hours > 0:
                duration_str = f"{hours}h {minutes}m"
            else:
                duration_str = f"{minutes}m"
        else:
            duration_pct = 0
            duration_str = "End"
        
        timeline_html_items.append(f"""
        <div class="timeline-event" style="left: {position_pct}%;" title="{tooltip_text}">
            <div class="timeline-marker" style="background: {event['color']};"></div>
            <div class="timeline-type">{event['label']}</div>
        </div>
        {"" if duration_pct == 0 else f'<div class="timeline-bar" style="left: {position_pct}%; width: {duration_pct}%;"><span class="timeline-duration">{duration_str}</span></div>'}
        """)

timeline_html = ''.join(timeline_html_items) if timeline_html_items else '<p style="text-align:center; padding:20px;">No timeline data available</p>'

# Group events by process for process-wise logs section
process_groups = defaultdict(list)
for event in all_events:
    process_groups[event['process_name']].append(event)

# Sort processes by number of events (descending)
sorted_processes = sorted(process_groups.items(), key=lambda x: len(x[1]), reverse=True)

# Function to normalize messages by replacing variable parts
def normalize_message(message):
    """Normalize error/warning messages by replacing variable parts with placeholders"""
    import re
    normalized = message
    # Replace PIDs (pid=1234, PID:1234, pid 1234, etc.)
    normalized = re.sub(r'pid[=:\s]+\d+', 'pid=<PID>', normalized, flags=re.IGNORECASE)
    # Replace process IDs in other formats
    normalized = re.sub(r'process\s+id[=:\s]+\d+', 'process id=<PID>', normalized, flags=re.IGNORECASE)
    # Replace IP addresses
    normalized = re.sub(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', '<IP>', normalized)
    # Replace standalone numbers (but preserve error codes in context)
    normalized = re.sub(r'(?<!\w)(\d{4,})(?!\w)', '<NUM>', normalized)
    # Replace hex addresses (0x1234abcd)
    normalized = re.sub(r'0x[0-9a-fA-F]+', '<HEX>', normalized)
    # Replace file descriptors (fd=123, fd:123)
    normalized = re.sub(r'fd[=:\s]+\d+', 'fd=<NUM>', normalized, flags=re.IGNORECASE)
    # Replace ports
    normalized = re.sub(r'port[=:\s]+\d+', 'port=<NUM>', normalized, flags=re.IGNORECASE)
    return normalized

# Generate process-wise logs HTML
def generate_process_logs_html(process_groups_sorted, max_processes=50):
    """Generate collapsible process-wise logs HTML - show counts of unique errors and warnings"""
    if not process_groups_sorted:
        return "<p>No process logs available.</p>"
    
    # Event types to include
    important_event_types = {'ERROR', 'WARNING', 'APPLIANCE_REBOOT', 'SYSTEM_RESTART', 'SERVICE_RESTART'}
    
    html_parts = []
    for process_name, events in process_groups_sorted[:max_processes]:
        # Filter events to only include important types
        filtered_events = [e for e in events if e['event_type'] in important_event_types]
        
        # Skip process if no important events
        if not filtered_events:
            continue
        
        # Count event types for this process (only filtered events)
        event_type_counts = defaultdict(int)
        for event in filtered_events:
            event_type_counts[event['event_type']] += 1
        
        # Create summary string (excluding SERVICE_RESTART from display)
        type_summary = ', '.join([f"{etype}: {count}" for etype, count in sorted(event_type_counts.items()) if etype != 'SERVICE_RESTART'])
        
        # Group errors and warnings by normalized message
        error_message_counts = defaultdict(lambda: {'count': 0, 'first_time': None, 'last_time': None, 'pids': set(), 'unique_pids': set(), 'sample_msg': None})
        warning_message_counts = defaultdict(lambda: {'count': 0, 'first_time': None, 'last_time': None, 'pids': set(), 'unique_pids': set(), 'sample_msg': None})
        restart_reboot_events = []
        
        for event in filtered_events:
            if event['event_type'] == 'ERROR':
                msg = event['message'][:200]  # Truncate message
                normalized_msg = normalize_message(msg)
                error_message_counts[normalized_msg]['count'] += 1
                error_message_counts[normalized_msg]['pids'].add(event['pid'])
                # Extract PIDs from the original message
                import re
                pids_in_msg = re.findall(r'pid[=:\s]+(\d+)', msg, re.IGNORECASE)
                for pid in pids_in_msg:
                    error_message_counts[normalized_msg]['unique_pids'].add(pid)
                # Store a sample message
                if error_message_counts[normalized_msg]['sample_msg'] is None:
                    error_message_counts[normalized_msg]['sample_msg'] = msg
                if error_message_counts[normalized_msg]['first_time'] is None or event['datetime'] < error_message_counts[normalized_msg]['first_time']:
                    error_message_counts[normalized_msg]['first_time'] = event['datetime']
                if error_message_counts[normalized_msg]['last_time'] is None or event['datetime'] > error_message_counts[normalized_msg]['last_time']:
                    error_message_counts[normalized_msg]['last_time'] = event['datetime']
                    
            elif event['event_type'] == 'WARNING':
                msg = event['message'][:200]  # Truncate message
                normalized_msg = normalize_message(msg)
                warning_message_counts[normalized_msg]['count'] += 1
                warning_message_counts[normalized_msg]['pids'].add(event['pid'])
                # Extract PIDs from the original message
                import re
                pids_in_msg = re.findall(r'pid[=:\s]+(\d+)', msg, re.IGNORECASE)
                for pid in pids_in_msg:
                    warning_message_counts[normalized_msg]['unique_pids'].add(pid)
                # Store a sample message
                if warning_message_counts[normalized_msg]['sample_msg'] is None:
                    warning_message_counts[normalized_msg]['sample_msg'] = msg
                if warning_message_counts[normalized_msg]['first_time'] is None or event['datetime'] < warning_message_counts[normalized_msg]['first_time']:
                    warning_message_counts[normalized_msg]['first_time'] = event['datetime']
                if warning_message_counts[normalized_msg]['last_time'] is None or event['datetime'] > warning_message_counts[normalized_msg]['last_time']:
                    warning_message_counts[normalized_msg]['last_time'] = event['datetime']
                    
            elif event['event_type'] in ['APPLIANCE_REBOOT', 'SYSTEM_RESTART', 'SERVICE_RESTART']:
                restart_reboot_events.append(event)
        
        # Sort errors and warnings by count (descending)
        sorted_errors = sorted(error_message_counts.items(), key=lambda x: x[1]['count'], reverse=True)
        sorted_warnings = sorted(warning_message_counts.items(), key=lambda x: x[1]['count'], reverse=True)
        sorted_restarts = sorted(restart_reboot_events, key=lambda x: x['datetime'], reverse=True)
        
        # Count critical events excluding SERVICE_RESTART
        critical_count = sum(1 for e in filtered_events if e['event_type'] != 'SERVICE_RESTART')
        
        # Main process header
        html_parts.append(f"""
        <div class="process-group">
            <div class="process-main" onclick="toggleProcessGroup(this)" title="Click to expand/collapse logs for {process_name}">
                <span class="process-icon">📦</span>
                <span class="collapse-indicator">▶</span>
                <span class="process-name">{process_name}</span>
                <span class="process-count">({critical_count} critical events)</span>
                <span class="process-summary">{type_summary}</span>
            </div>
            <div class="process-logs collapsed">
        """)
        
        # Add Errors section if there are errors
        if sorted_errors:
            html_parts.append(f"""
                <div class="log-subsection">
                    <h4 class="subsection-title">🔴 Errors ({sum(e[1]['count'] for e in sorted_errors)} total, {len(sorted_errors)} unique)</h4>
                    <table class="process-log-table">
                        <thead>
                            <tr>
                                <th width="180">Timestamp</th>
                                <th>Message</th>
                                <th width="80">Count</th>
                                <th width="100">Unique PIDs</th>
                            </tr>
                        </thead>
                        <tbody>
            """)
            
            for message, info in sorted_errors:
                unique_pids_count = len(info['unique_pids']) if info['unique_pids'] else 0
                unique_pids_display = f"{unique_pids_count} PIDs" if unique_pids_count > 0 else "-"
                html_parts.append(f"""
                            <tr class="event-error">
                                <td class="log-time">{info['first_time'].strftime('%Y-%m-%d %H:%M:%S')}</td>
                                <td class="log-message">{message}</td>
                                <td class="log-count">{info['count']}</td>
                                <td class="log-count">{unique_pids_display}</td>
                            </tr>
                """)
            
            html_parts.append("""
                        </tbody>
                    </table>
                </div>
            """)
        
        # Add Warnings section if there are warnings
        if sorted_warnings:
            html_parts.append(f"""
                <div class="log-subsection">
                    <h4 class="subsection-title">🟠 Warnings ({sum(w[1]['count'] for w in sorted_warnings)} total, {len(sorted_warnings)} unique)</h4>
                    <table class="process-log-table">
                        <thead>
                            <tr>
                                <th width="180">Timestamp</th>
                                <th>Message</th>
                                <th width="80">Count</th>
                                <th width="100">Unique PIDs</th>
                            </tr>
                        </thead>
                        <tbody>
            """)
            
            for message, info in sorted_warnings:
                unique_pids_count = len(info['unique_pids']) if info['unique_pids'] else 0
                unique_pids_display = f"{unique_pids_count} PIDs" if unique_pids_count > 0 else "-"
                html_parts.append(f"""
                            <tr class="event-warning">
                                <td class="log-time">{info['first_time'].strftime('%Y-%m-%d %H:%M:%S')}</td>
                                <td class="log-message">{message}</td>
                                <td class="log-count">{info['count']}</td>
                                <td class="log-count">{unique_pids_display}</td>
                            </tr>
                """)
            
            html_parts.append("""
                        </tbody>
                    </table>
                </div>
            """)
        
        # Close the process-logs div and process-group div
        html_parts.append("""
            </div>
        </div>
        """)
    
    if len(process_groups_sorted) > max_processes:
        html_parts.append(f"""
        <div style="text-align: center; padding: 20px; color: #7f8c8d; font-style: italic;">
            Showing top {max_processes} processes by event count. Total processes: {len(process_groups_sorted)}
        </div>
        """)
    
    return ''.join(html_parts)

process_logs_html = generate_process_logs_html(sorted_processes)

# Helper function for table rows
def generate_table_rows(events):
    rows = []
    for event in events:
        rows.append(f"""
        <tr>
            <td>{event['datetime'].strftime('%Y-%m-%d %H:%M:%S')}</td>
            <td>{event['process_name']}</td>
            <td>{event['pid']}</td>
            <td>{event['message']}</td>
        </tr>
        """)
    return ''.join(rows) if rows else '<tr><td colspan="4" style="text-align:center;">No events found</td></tr>'

# Helper function for process lifecycle display
def generate_process_lifecycle_html(process_lifecycle_data):
    """Generate HTML for process lifecycle across reboots/restarts"""
    if not process_lifecycle_data:
        return "<p>No process lifecycle data available.</p>"
    
    html_parts = []
    html_parts.append('<div class="lifecycle-container">')
    
    for process_name, data in process_lifecycle_data:
        avg_runtime = data['avg_runtime_seconds']
        avg_startup = data['avg_startup_seconds']
        cycles = data['total_cycles']
        
        # Format runtime
        if avg_runtime < 60:
            runtime_str = f"{avg_runtime:.0f}s"
        elif avg_runtime < 3600:
            runtime_str = f"{avg_runtime/60:.1f}m"
        else:
            runtime_str = f"{avg_runtime/3600:.1f}h"
        
        # Format startup time
        if avg_startup is not None:
            startup_str = f"{avg_startup:.1f}s"
        else:
            startup_str = "N/A"
        
        # Create process card with summary header
        html_parts.append(f"""
            <div class='lifecycle-process-card'>
                <div class='lifecycle-process-header'>
                    <div class='lifecycle-header-item'>
                        <span class='lifecycle-header-label'>Process Name</span>
                        <span class='lifecycle-header-value'>{process_name}</span>
                    </div>
                    <div class='lifecycle-header-item'>
                        <span class='lifecycle-header-label'>Total Cycles</span>
                        <span class='lifecycle-header-value lifecycle-cycles-badge'>{cycles}</span>
                    </div>
                    <div class='lifecycle-header-item'>
                        <span class='lifecycle-header-label'>Avg Runtime</span>
                        <span class='lifecycle-header-value lifecycle-runtime-badge'>{runtime_str}</span>
                    </div>
                    <div class='lifecycle-header-item'>
                        <span class='lifecycle-header-label'>Avg Startup Time</span>
                        <span class='lifecycle-header-value lifecycle-startup-badge'>{startup_str}</span>
                    </div>
                </div>
        """)
        
        # Build cycles table
        html_parts.append("""
                <div class='lifecycle-cycles-container'>
                    <table class='lifecycle-cycles-table'>
                        <thead>
                            <tr>
                                <th>Cycle</th>
                                <th>Process Started</th>
                                <th>Process Stopped</th>
                                <th>Alive For</th>
                                <th>Service Restarts</th>
                            </tr>
                        </thead>
                        <tbody>
        """)
        
        # Show ALL cycles (not limited)
        for i, period in enumerate(data['periods']):
            duration_seconds = period['duration'].total_seconds()
            if duration_seconds < 60:
                duration_str = f"{duration_seconds:.0f}s"
            elif duration_seconds < 3600:
                minutes = duration_seconds / 60
                duration_str = f"{minutes:.1f}m"
            else:
                hours = duration_seconds / 3600
                duration_str = f"{hours:.1f}h"
            
            start_time_str = period['start'].strftime('%Y-%m-%d %H:%M:%S')
            stop_time_str = period['stop'].strftime('%Y-%m-%d %H:%M:%S')
            
            # Build service restarts cell
            restart_cell = ""
            if period.get('service_restarts'):
                restart_count = len(period['service_restarts'])
                restart_times = []
                # Show ALL restart times, not limited
                for restart in period['service_restarts']:
                    restart_time = restart['timestamp'].strftime('%H:%M:%S')
                    restart_times.append(restart_time)
                
                if restart_count > 0:
                    restart_cell = f"{restart_count}<br><span style='font-size:11px'>{', '.join(restart_times)}</span>"
                else:
                    restart_cell = "—"
            else:
                restart_cell = "—"
            
            html_parts.append(f"""
                            <tr>
                                <td class='cycle-num'>🔄 {i+1}</td>
                                <td class='cycle-start'>{start_time_str}</td>
                                <td class='cycle-stop'>{stop_time_str}</td>
                                <td class='cycle-duration'>{duration_str}</td>
                                <td class='cycle-restarts'>{restart_cell}</td>
                            </tr>
            """)
        
        html_parts.append("""
                        </tbody>
                    </table>
                </div>
            </div>
        """)
    
    html_parts.append('</div>')
    
    return ''.join(html_parts)

process_lifecycle_html = generate_process_lifecycle_html(process_lifecycle_data)

# Helper function for hierarchical reboot/restart display
def generate_hierarchical_reboot_html(event_groups):
    if not event_groups:
        return "<p>No events found.</p>"
    
    html_parts = []
    for idx, group in enumerate(event_groups):
        major = group['major_event']
        services = group['service_restarts']
        event_type = group.get('event_type', 'Event')
        event_short = group.get('event_short', 'EV')
        
        # Calculate time difference from previous event
        time_diff_str = ""
        if idx > 0:
            prev_major = event_groups[idx - 1]['major_event']
            time_diff = major['datetime'] - prev_major['datetime']
            days = time_diff.days
            hours, remainder = divmod(time_diff.seconds, 3600)
            minutes, seconds = divmod(remainder, 60)
            
            if days > 0:
                time_diff_str = f"{days}d {hours}h {minutes}m"
            elif hours > 0:
                time_diff_str = f"{hours}h {minutes}m"
            else:
                time_diff_str = f"{minutes}m"
        
        # Determine label color based on event type
        label_class = f"reboot-label reboot-label-{event_short.lower()}"
        
        # Main event row
        html_parts.append(f"""
        <div class="reboot-group">
            <div class="reboot-main" onclick="toggleRebootGroup(this)" title="Click to expand/collapse errors, warnings, and failures">
                <span class="reboot-icon">📁</span>
                <span class="collapse-indicator">▶</span>
                <span class="reboot-time">{major['datetime'].strftime('%Y-%m-%d %H:%M:%S')}</span>
                <span class="{label_class}">{event_type} ({event_short})</span>
                <span class="reboot-process">[PID: {major['pid']} | Process: {major['process_name']}]</span>
                {"<span class='time-diff'>⏱ +" + time_diff_str + " from previous</span>" if time_diff_str else ""}
                <span class="reboot-count">({len(services)} errors/warnings)</span>
            </div>
        """)
        
        # Service restart sub-items
        if services:
            html_parts.append('<div class="reboot-services">')
            # Add header row for columns
            html_parts.append(f"""
                <div class="service-header">
                    <span class="service-icon-header">Type</span>
                    <span class="service-time-header">Time</span>
                    <span class="service-name-header">Process Name</span>
                    <span class="service-pid-header">PID</span>
                    <span class="service-message-header">Message</span>
                </div>
            """)
            for svc in services:
                # Determine event icon based on type
                if svc['event_type'] == 'ERROR':
                    event_icon = '🔴'
                    icon_class = 'service-icon service-icon-error'
                elif svc['event_type'] == 'WARNING':
                    event_icon = '🟡'
                    icon_class = 'service-icon service-icon-warning'
                else:
                    event_icon = '⚠️'
                    icon_class = 'service-icon service-icon-failure'
                
                html_parts.append(f"""
                <div class="service-item">
                    <span class="{icon_class}">{event_icon}</span>
                    <span class="service-time">{svc['datetime'].strftime('%H:%M:%S')}</span>
                    <span class="service-name">{svc['process_name']}</span>
                    <span class="service-pid">[PID: {svc['pid']}]</span>
                    <span class="service-message">{svc['message'][:100]}</span>
                </div>
                """)
            html_parts.append('</div>')
        
        html_parts.append('</div>')
    
    return ''.join(html_parts)

combined_reboot_restart_html = generate_hierarchical_reboot_html(combined_reboot_restart_groups)

# Process top 10 chart data
top10_processes = sorted(process_counts.items(), key=lambda x: x[1], reverse=True)[:10]
max_count = max([count for _, count in top10_processes]) if top10_processes else 1

# Event type pie chart data
total_events = sum(event_types.values())
event_colors = {
    'ERROR': '#DC3912',
    'WARNING': '#FF9900',
    'APPLIANCE_REBOOT': '#990099',
    'SYSTEM_RESTART': '#663399',
    'SERVICE_RESTART': '#9966CC',
    'DATABASE': '#3366CC',
    'MOUNT': '#109618',
    'INFO': '#0099C6'
}

html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Infoblox Log Analysis Dashboard - Advanced Analytics</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(20px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}
        @keyframes slideIn {{
            from {{ opacity: 0; transform: translateX(-20px); }}
            to {{ opacity: 1; transform: translateX(0); }}
        }}
        @keyframes pulse {{
            0%, 100% {{ opacity: 1; }}
            50% {{ opacity: 0.8; }}
        }}
        body {{
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            background-attachment: fixed;
            color: #2c3e50;
            padding: 20px;
            min-height: 100vh;
        }}
        body::before {{
            content: '';
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: 
                radial-gradient(circle at 20% 50%, rgba(120, 119, 198, 0.3) 0%, transparent 50%),
                radial-gradient(circle at 80% 80%, rgba(252, 136, 102, 0.3) 0%, transparent 50%),
                radial-gradient(circle at 40% 20%, rgba(249, 187, 87, 0.3) 0%, transparent 50%);
            pointer-events: none;
            z-index: 0;
        }}
        .container {{
            max-width: 1400px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            position: relative;
            z-index: 1;
            animation: fadeIn 0.6s ease-out;
        }}
        h1 {{
            color: #1a2332;
            text-align: center;
            margin-bottom: 10px;
            font-size: 42px;
            font-weight: 800;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            letter-spacing: -1px;
        }}
        .subtitle {{
            text-align: center;
            color: #7f8c8d;
            margin-bottom: 40px;
            font-size: 16px;
            font-weight: 500;
        }}
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 25px;
            margin-bottom: 40px;
        }}
        .stat-card {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 25px;
            border-radius: 16px;
            color: white;
            box-shadow: 0 10px 30px rgba(102, 126, 234, 0.4);
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
            overflow: hidden;
            animation: slideIn 0.6s ease-out;
        }}
        .stat-card::before {{
            content: '';
            position: absolute;
            top: -50%;
            right: -50%;
            width: 200%;
            height: 200%;
            background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
            transition: transform 0.5s ease;
        }}
        .stat-card:hover {{
            transform: translateY(-8px) scale(1.02);
            box-shadow: 0 20px 40px rgba(102, 126, 234, 0.5);
        }}
        .stat-card:hover::before {{
            transform: translate(-25%, -25%);
        }}
        .stat-card.error {{
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            box-shadow: 0 10px 30px rgba(245, 87, 108, 0.4);
        }}
        .stat-card.error:hover {{
            box-shadow: 0 20px 40px rgba(245, 87, 108, 0.5);
        }}
        .stat-card.warning {{
            background: linear-gradient(135deg, #fa709a 0%, #fee140 100%);
            box-shadow: 0 10px 30px rgba(254, 225, 64, 0.4);
        }}
        .stat-card.warning:hover {{
            box-shadow: 0 20px 40px rgba(254, 225, 64, 0.5);
        }}
        .stat-card.info {{
            background: linear-gradient(135deg, #30cfd0 0%, #330867 100%);
            box-shadow: 0 10px 30px rgba(48, 207, 208, 0.4);
        }}
        .stat-card.info:hover {{
            box-shadow: 0 20px 40px rgba(48, 207, 208, 0.5);
        }}
        .stat-card h3 {{
            font-size: 13px;
            font-weight: 600;
            margin-bottom: 12px;
            opacity: 0.95;
            text-transform: uppercase;
            letter-spacing: 1px;
        }}
        .stat-card .value {{
            font-size: 40px;
            font-weight: 800;
            text-shadow: 0 2px 10px rgba(0,0,0,0.2);
        }}
        .section {{
            margin-top: 50px;
            animation: fadeIn 0.8s ease-out;
        }}
        .section-title {{
            font-size: 28px;
            color: #1a2332;
            margin-bottom: 25px;
            padding-bottom: 15px;
            position: relative;
            font-weight: 700;
        }}
        .section-title::before {{
            content: '';
            position: absolute;
            left: 0;
            bottom: 0;
            width: 80px;
            height: 4px;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            border-radius: 2px;
        }}
        .section-title::after {{
            content: '';
            position: absolute;
            left: 0;
            bottom: 0;
            width: 100%;
            height: 1px;
            background: linear-gradient(90deg, rgba(102, 126, 234, 0.3) 0%, transparent 100%);
        }}
        .chart-container {{
            margin: 25px 0;
            padding: 30px;
            background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
            border-radius: 16px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.08);
            border: 1px solid rgba(255,255,255,0.8);
            transition: all 0.3s ease;
        }}
        .chart-container:hover {{
            box-shadow: 0 8px 25px rgba(0,0,0,0.12);
            transform: translateY(-2px);
        }}
        .bar-chart {{
            margin: 15px 0;
        }}
        .bar-item {{
            display: flex;
            align-items: center;
            margin: 12px 0;
            animation: slideIn 0.6s ease-out;
            transition: transform 0.2s ease;
        }}
        .bar-item:hover {{
            transform: translateX(5px);
        }}
        .bar-label {{
            width: 180px;
            font-size: 13px;
            color: #2c3e50;
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }}
        .bar-outer {{
            flex: 1;
            height: 35px;
            background: linear-gradient(90deg, #e8eaf6 0%, #f5f5f5 100%);
            border-radius: 20px;
            margin: 0 15px;
            position: relative;
            overflow: hidden;
            box-shadow: inset 0 2px 4px rgba(0,0,0,0.06);
        }}
        .bar-inner {{
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            border-radius: 20px;
            transition: width 0.8s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
            overflow: hidden;
        }}
        .bar-inner::after {{
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255,255,255,0.3), transparent);
            animation: shimmer 2s infinite;
        }}
        @keyframes shimmer {{
            0% {{ left: -100%; }}
            100% {{ left: 100%; }}
        }}
        .bar-value {{
            width: 90px;
            text-align: right;
            font-weight: 700;
            color: #667eea;
            font-size: 14px;
        }}
        .table-wrapper {{
            overflow-x: auto;
            margin-top: 20px;
            border-radius: 12px;
            border: 1px solid #e0e6ed;
            max-height: 500px;
            overflow-y: auto;
            box-shadow: 0 2px 8px rgba(0,0,0,0.05);
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }}
        thead {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }}
        th {{
            padding: 15px;
            text-align: left;
            font-weight: 600;
            position: sticky;
            top: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            z-index: 10;
            text-transform: uppercase;
            font-size: 11px;
            letter-spacing: 0.5px;
        }}
        td {{
            padding: 12px 15px;
            border-bottom: 1px solid #f0f3f7;
            transition: background 0.2s ease;
        }}
        tbody tr {{
            transition: all 0.2s ease;
        }}
        tbody tr:nth-child(even) {{
            background: #fafbfc;
        }}
        tbody tr:hover {{
            background: linear-gradient(90deg, #e8f4f8 0%, #f0f8ff 100%);
            transform: scale(1.01);
            box-shadow: 0 2px 8px rgba(102, 126, 234, 0.1);
        }}
        .pie-chart {{
            display: flex;
            flex-wrap: wrap;
            gap: 30px;
            align-items: center;
            justify-content: center;
        }}
        .pie-legend {{
            list-style: none;
        }}
        .pie-legend li {{
            margin: 8px 0;
            display: flex;
            align-items: center;
        }}
        .legend-color {{
            width: 20px;
            height: 20px;
            margin-right: 10px;
            border-radius: 3px;
        }}
        .legend-label {{
            font-size: 14px;
            color: #2c3e50;
        }}
        .legend-value {{
            margin-left: auto;
            padding-left: 20px;
            font-weight: 600;
            color: #7f8c8d;
        }}
        /* Hierarchical Reboot/Restart Styles */
        .reboot-container {{
            background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
            border-radius: 12px;
            padding: 20px;
            margin: 20px 0;
            box-shadow: 0 2px 12px rgba(0,0,0,0.06);
        }}
        .reboot-group {{
            margin-bottom: 12px;
            border: 1px solid #e0e6ed;
            border-radius: 12px;
            background: white;
            overflow: hidden;
            transition: all 0.3s ease;
            box-shadow: 0 2px 8px rgba(0,0,0,0.04);
        }}
        .reboot-group:hover {{
            box-shadow: 0 4px 16px rgba(102, 126, 234, 0.15);
            transform: translateY(-2px);
        }}
        .reboot-main {{
            display: flex;
            align-items: center;
            padding: 16px 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-weight: 600;
            font-size: 14px;
            gap: 12px;
            cursor: pointer;
            user-select: none;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }}
        .reboot-main::before {{
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255,255,255,0.2), transparent);
            transition: left 0.5s ease;
        }}
        .reboot-main:hover::before {{
            left: 100%;
        }}
        .reboot-main:hover {{
            background: linear-gradient(135deg, #5568d3 0%, #653a8b 100%);
        }}
        .reboot-icon {{
            font-size: 18px;
        }}
        .collapse-indicator {{
            margin-left: 5px;
            font-size: 12px;
            transition: transform 0.3s;
        }}
        .collapse-indicator.expanded {{
            transform: rotate(90deg);
        }}
        .reboot-time {{
            font-family: 'Courier New', monospace;
            font-weight: 700;
        }}
        .reboot-label {{
            background: rgba(255, 255, 255, 0.2);
            padding: 3px 10px;
            border-radius: 4px;
            font-weight: 700;
        }}
        .reboot-label-ar {{
            background: #DC3912;
            color: white;
        }}
        .reboot-label-sr {{
            background: #7FB3D5;
            color: white;
        }}
        .reboot-process {{
            color: rgba(255, 255, 255, 0.9);
            font-size: 12px;
        }}
        .time-diff {{
            background: rgba(255, 255, 255, 0.3);
            padding: 3px 10px;
            border-radius: 4px;
            font-size: 12px;
            color: rgba(255, 255, 255, 0.95);
            font-weight: 600;
            margin-left: 5px;
        }}
        .reboot-count {{
            margin-left: auto;
            background: rgba(255, 255, 255, 0.25);
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 12px;
        }}
        .reboot-services {{
            background: #fafbfc;
            padding: 5px 15px 5px 30px;
            border-top: 1px solid #e8ebed;
            max-height: 500px;
            overflow-y: auto;
            transition: max-height 0.3s ease-out;
        }}
        .reboot-services.collapsed {{
            max-height: 0;
            padding: 0 15px 0 30px;
            overflow: hidden;
        }}
        .service-header {{
            display: flex;
            align-items: center;
            padding: 8px 10px;
            margin: 1px 0 2px 0;
            background: #34495e;
            color: white;
            font-size: 12px;
            font-weight: 600;
            border-radius: 4px;
            gap: 0;
        }}
        .service-icon-header {{
            width: 50px;
            flex-shrink: 0;
        }}
        .service-time-header {{
            width: 90px;
            flex-shrink: 0;
        }}
        .service-name-header {{
            width: 250px;
            flex-shrink: 0;
        }}
        .service-pid-header {{
            width: 100px;
            flex-shrink: 0;
        }}
        .service-message-header {{
            flex: 1;
            padding-left: 10px;
        }}
        .service-item {{
            display: flex;
            align-items: center;
            padding: 8px 10px;
            margin: 1px 0;
            background: white;
            border-left: 3px solid #3498db;
            border-radius: 4px;
            font-size: 13px;
            gap: 0;
            transition: background 0.2s;
        }}
        .service-item:hover {{
            background: #e8f4f8;
        }}
        .service-icon {{
            color: #7f8c8d;
            font-size: 14px;
            font-family: 'Courier New', monospace;
            width: 50px;
            flex-shrink: 0;
            text-align: center;
        }}
        .service-icon-error {{
            color: #DC3912;
        }}
        .service-icon-warning {{
            color: #FF9900;
        }}
        .service-icon-failure {{
            color: #E67E22;
        }}
        .service-time {{
            font-family: 'Courier New', monospace;
            color: #5a6c7d;
            font-weight: 600;
            width: 90px;
            flex-shrink: 0;
        }}
        .service-name {{
            font-weight: 600;
            color: #2c3e50;
            width: 250px;
            flex-shrink: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }}
        .service-pid {{
            color: #7f8c8d;
            font-size: 11px;
            width: 100px;
            flex-shrink: 0;
        }}
        .service-message {{
            color: #5a6c7d;
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            padding-left: 10px;
        }}
        /* Timeline Styles */
        .timeline-container {{
            background: #f8f9fa;
            border-radius: 8px;
            padding: 30px 20px;
            margin: 20px 0;
            position: relative;
        }}
        .timeline-wrapper {{
            position: relative;
            height: 120px;
            background: white;
            border-radius: 6px;
            border: 1px solid #d1d8e0;
            padding: 40px 20px 20px 20px;
            margin-top: 20px;
        }}
        .timeline-axis {{
            position: absolute;
            top: 50%;
            left: 20px;
            right: 20px;
            height: 4px;
            background: linear-gradient(90deg, #dfe6e9 0%, #b2bec3 100%);
            border-radius: 2px;
        }}
        .timeline-event {{
            position: absolute;
            top: 50%;
            transform: translateX(-50%);
            z-index: 10;
        }}
        .timeline-marker {{
            width: 16px;
            height: 16px;
            border-radius: 50%;
            border: 3px solid white;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
            cursor: pointer;
            transition: transform 0.2s;
            margin: 0 auto;
        }}
        .timeline-marker:hover {{
            transform: scale(1.4);
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        }}

        .timeline-type {{
            position: absolute;
            top: 20px;
            left: 50%;
            transform: translateX(-50%);
            font-size: 11px;
            font-weight: 700;
            color: #2c3e50;
            white-space: nowrap;
            background: white;
            padding: 3px 8px;
            border-radius: 4px;
            border: 1px solid #d1d8e0;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }}
        .timeline-bar {{
            position: absolute;
            top: 50%;
            height: 8px;
            background: rgba(102, 126, 234, 0.15);
            border-radius: 4px;
            margin-top: -2px;
            z-index: 5;
        }}
        .timeline-duration {{
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 10px;
            font-weight: 600;
            color: #667eea;
            background: rgba(255, 255, 255, 0.9);
            padding: 2px 6px;
            border-radius: 3px;
            white-space: nowrap;
        }}
        .timeline-legend {{
            display: flex;
            gap: 20px;
            justify-content: center;
            margin-bottom: 10px;
        }}
        .timeline-legend-item {{
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 12px;
            color: #5a6c7d;
        }}
        .timeline-legend-color {{
            width: 12px;
            height: 12px;
            border-radius: 50%;
            border: 2px solid white;
            box-shadow: 0 1px 3px rgba(0,0,0,0.2);
        }}
        /* Process Lifecycle Styles */
        .lifecycle-container {{
            background: transparent;
            border-radius: 12px;
            overflow: visible;
        }}
        .lifecycle-process-card {{
            background: white;
            border: 1px solid #e0e6ed;
            border-radius: 16px;
            margin-bottom: 30px;
            box-shadow: 0 8px 24px rgba(0,0,0,0.08);
            overflow: hidden;
            transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
            animation: fadeIn 0.6s ease-out;
        }}
        .lifecycle-process-card:hover {{
            box-shadow: 0 12px 32px rgba(102, 126, 234, 0.2);
            transform: translateY(-4px);
        }}
        .lifecycle-process-header {{
            display: grid;
            grid-template-columns: 2fr 1fr 1fr 1fr;
            gap: 20px;
            padding: 25px 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            position: relative;
            overflow: hidden;
        }}
        .lifecycle-process-header::before {{
            content: '';
            position: absolute;
            top: -50%;
            right: -50%;
            width: 200%;
            height: 200%;
            background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
            animation: pulse 4s infinite;
        }}
        .lifecycle-header-item {{
            display: flex;
            flex-direction: column;
            gap: 8px;
            position: relative;
            z-index: 1;
        }}
        .lifecycle-header-label {{
            font-size: 11px;
            opacity: 0.9;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 1px;
        }}
        .lifecycle-header-value {{
            font-size: 20px;
            font-weight: 800;
            text-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .lifecycle-cycles-badge {{
            color: #ffd93d;
            text-shadow: 0 0 10px rgba(255, 217, 61, 0.5);
        }}
        .lifecycle-runtime-badge {{
            color: #6bf178;
            text-shadow: 0 0 10px rgba(107, 241, 120, 0.5);
        }}
        .lifecycle-startup-badge {{
            color: #ffa07a;
            text-shadow: 0 0 10px rgba(255, 160, 122, 0.5);
        }}
        /* Lifecycle Cycles Table */
        .lifecycle-cycles-container {{
            max-height: 450px;
            overflow-y: auto;
            border-top: 3px solid #667eea;
            background: linear-gradient(180deg, #f8f9fa 0%, #ffffff 100%);
        }}
        .lifecycle-cycles-container::-webkit-scrollbar {{
            width: 8px;
        }}
        .lifecycle-cycles-container::-webkit-scrollbar-track {{
            background: #f1f3f5;
        }}
        .lifecycle-cycles-container::-webkit-scrollbar-thumb {{
            background: linear-gradient(180deg, #667eea 0%, #764ba2 100%);
            border-radius: 4px;
        }}
        .lifecycle-cycles-container::-webkit-scrollbar-thumb:hover {{
            background: linear-gradient(180deg, #5568d3 0%, #653a8b 100%);
        }}
        .lifecycle-cycles-table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 11px;
        }}
        .lifecycle-cycles-table thead {{
            position: sticky;
            top: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            z-index: 10;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .lifecycle-cycles-table th {{
            padding: 12px 10px;
            text-align: left;
            font-weight: 700;
            font-size: 11px;
            border-bottom: 2px solid rgba(255,255,255,0.2);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}
        .lifecycle-cycles-table td {{
            padding: 6px 10px;
            border-bottom: 1px solid #e8ecf1;
            transition: all 0.2s ease;
        }}
        .lifecycle-cycles-table tbody tr {{
            transition: all 0.2s ease;
        }}
        .lifecycle-cycles-table tbody tr:hover {{
            background: linear-gradient(90deg, #e8f4f8 0%, #f0f8ff 100%);
            transform: scale(1.005);
        }}
        .cycle-num {{
            font-weight: 700;
            color: #667eea;
            width: 70px;
            text-shadow: 0 1px 2px rgba(102, 126, 234, 0.2);
            white-space: nowrap;
        }}
        .cycle-start {{
            font-family: 'SF Mono', 'Monaco', 'Courier New', monospace;
            font-size: 10px;
            color: #27ae60;
            font-weight: 600;
            width: 155px;
            white-space: nowrap;
        }}
        .cycle-stop {{
            font-family: 'SF Mono', 'Monaco', 'Courier New', monospace;
            font-size: 10px;
            color: #e74c3c;
            font-weight: 600;
            width: 155px;
            white-space: nowrap;
        }}
        .cycle-duration {{
            font-weight: 700;
            color: #8e44ad;
            text-align: center;
            width: 70px;
            white-space: nowrap;
        }}
        .cycle-restarts {{
            text-align: left;
            color: #e67e22;
            font-size: 10px;
            font-weight: 600;
            padding-left: 15px;
            min-width: 150px;
        }}
        .info-box {{
            background: linear-gradient(135deg, #e8f4f8 0%, #f0f8ff 100%);
            border-left: 5px solid #667eea;
            padding: 20px;
            margin-bottom: 25px;
            border-radius: 12px;
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.1);
            transition: all 0.3s ease;
        }}
        .info-box:hover {{
            box-shadow: 0 6px 16px rgba(102, 126, 234, 0.15);
            transform: translateX(5px);
        }}
        .info-box p {{
            margin: 8px 0;
            color: #2c3e50;
            font-size: 14px;
            line-height: 1.6;
        }}
        /* Process-wise Logs Styles */
        .process-container {{
            background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
            border-radius: 12px;
            padding: 20px;
            margin: 20px 0;
            box-shadow: 0 2px 12px rgba(0,0,0,0.06);
        }}
        .process-group {{
            margin-bottom: 20px;
            border: 1px solid #e0e6ed;
            border-radius: 12px;
            background: white;
            overflow: hidden;
            box-shadow: 0 2px 8px rgba(0,0,0,0.04);
            transition: all 0.3s ease;
        }}
        .process-group:hover {{
            box-shadow: 0 4px 16px rgba(102, 126, 234, 0.12);
            transform: translateY(-2px);
        }}
        .process-main {{
            display: flex;
            align-items: center;
            padding: 12px 15px;
            background: linear-gradient(135deg, #3498db 0%, #2980b9 100%);
            color: white;
            font-weight: 600;
            font-size: 14px;
            gap: 10px;
            cursor: pointer;
            user-select: none;
            transition: background 0.2s;
        }}
        .process-main:hover {{
            background: linear-gradient(135deg, #2980b9 0%, #21618c 100%);
        }}
        .process-icon {{
            font-size: 18px;
        }}
        .process-name {{
            font-weight: 700;
            min-width: 200px;
        }}
        .process-count {{
            background: rgba(255, 255, 255, 0.25);
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 12px;
        }}
        .process-summary {{
            flex: 1;
            font-size: 12px;
            color: rgba(255, 255, 255, 0.9);
        }}
        .process-logs {{
            background: #fafbfc;
            padding: 15px;
            border-top: 1px solid #e8ebed;
            max-height: 600px;
            overflow-y: auto;
            transition: max-height 0.3s ease-out;
        }}
        .process-logs.collapsed {{
            max-height: 0;
            padding: 0 15px;
            overflow: hidden;
        }}
        .process-log-table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
            background: white;
        }}
        .process-log-table thead {{
            background: #34495e;
            color: white;
            position: sticky;
            top: 0;
            z-index: 10;
        }}
        .process-log-table th {{
            padding: 10px;
            text-align: left;
            font-weight: 600;
            font-size: 12px;
        }}
        .process-log-table td {{
            padding: 8px 10px;
            border-bottom: 1px solid #ecf0f1;
        }}
        .process-log-table tbody tr:nth-child(even) {{
            background: #f8f9fa;
        }}
        .process-log-table tbody tr:hover {{
            background: #e8f4f8;
        }}
        .event-error {{
            background: #ffebee !important;
        }}
        .event-error:hover {{
            background: #ffcdd2 !important;
        }}
        .event-warning {{
            background: #fff3e0 !important;
        }}
        .event-warning:hover {{
            background: #ffe0b2 !important;
        }}
        .log-time {{
            font-family: 'Courier New', monospace;
            font-size: 12px;
            color: #5a6c7d;
            white-space: nowrap;
        }}
        .log-pid {{
            font-family: 'Courier New', monospace;
            font-size: 12px;
            color: #7f8c8d;
            text-align: center;
        }}
        .log-type {{
            text-align: center;
        }}
        .log-message {{
            color: #2c3e50;
            font-size: 12px;
        }}
        .badge {{
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: 600;
            text-transform: uppercase;
        }}
        .badge-error {{
            background: #ffebee;
            color: #c62828;
        }}
        .badge-warning {{
            background: #fff3e0;
            color: #ef6c00;
        }}
        .badge-appliance-reboot {{
            background: #f3e5f5;
            color: #6a1b9a;
        }}
        .badge-system-restart {{
            background: #e8eaf6;
            color: #3f51b5;
        }}
        .badge-service-restart {{
            background: #e0f2f1;
            color: #00695c;
        }}
        .badge-database {{
            background: #e3f2fd;
            color: #1565c0;
        }}
        .badge-mount {{
            background: #e8f5e9;
            color: #2e7d32;
        }}
        .badge-info {{
            background: #e0f7fa;
            color: #00838f;
        }}
        .log-subsection {{
            margin: 15px 0;
        }}
        .subsection-title {{
            font-size: 15px;
            font-weight: 600;
            color: #2c3e50;
            margin: 10px 0;
            padding: 8px 12px;
            background: #f8f9fa;
            border-left: 4px solid #3498db;
        }}
        .log-count {{
            font-family: 'Courier New', monospace;
            font-size: 13px;
            font-weight: 600;
            color: #2c3e50;
            text-align: center;
        }}
    </style>
    <script>
        function toggleRebootGroup(element) {{
            const servicesDiv = element.nextElementSibling;
            const indicator = element.querySelector('.collapse-indicator');
            
            if (servicesDiv && servicesDiv.classList.contains('reboot-services')) {{
                servicesDiv.classList.toggle('collapsed');
                indicator.classList.toggle('expanded');
            }}
        }}
        
        function toggleProcessGroup(element) {{
            const logsDiv = element.nextElementSibling;
            const indicator = element.querySelector('.collapse-indicator');
            
            if (logsDiv && logsDiv.classList.contains('process-logs')) {{
                logsDiv.classList.toggle('collapsed');
                indicator.classList.toggle('expanded');
            }}
        }}
        
        // Initialize all as collapsed on page load
        document.addEventListener('DOMContentLoaded', function() {{
            const allServices = document.querySelectorAll('.reboot-services');
            allServices.forEach(function(services) {{
                services.classList.add('collapsed');
            }});
            
            const allProcessLogs = document.querySelectorAll('.process-logs');
            allProcessLogs.forEach(function(logs) {{
                logs.classList.add('collapsed');
            }});
        }});
    </script>
</head>
<body>
    <div class="container">
        <h1>🔍 Infoblox Log Analysis Dashboard</h1>
        <div class="subtitle">Analysis of infoblox.log - Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <h3>Total Events</h3>
                <div class="value">{len(all_events):,}</div>
            </div>
            <div class="stat-card error">
                <h3>Errors</h3>
                <div class="value">{event_types.get('ERROR', 0):,}</div>
            </div>
            <div class="stat-card warning">
                <h3>Warnings</h3>
                <div class="value">{event_types.get('WARNING', 0):,}</div>
            </div>
            <div class="stat-card" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
                <h3>Appliance Reboots</h3>
                <div class="value">{event_types.get('APPLIANCE_REBOOT', 0):,}</div>
            </div>
            <div class="stat-card" style="background: linear-gradient(135deg, #a8edea 0%, #fed6e3 100%);">
                <h3>System Restarts</h3>
                <div class="value" style="color: #2c3e50;">{event_types.get('SYSTEM_RESTART', 0):,}</div>
            </div>
            <div class="stat-card info">
                <h3>Unique Processes</h3>
                <div class="value">{len(set(e['process_name'] for e in all_events)):,}</div>
            </div>
        </div>
        
        {"<div class='section'><h2 class='section-title'>📊 Event Type Distribution</h2><div class='chart-container'><div class='pie-chart'><ul class='pie-legend'>" + ''.join([f"<li><span class='legend-color' style='background:{event_colors.get(et, '#ccc')}'></span><span class='legend-label'>{et}</span><span class='legend-value'>{count:,} ({100*count/total_events:.1f}%)</span></li>" for et, count in sorted(event_types.items(), key=lambda x: x[1], reverse=True)]) + "</ul></div></div></div>" if event_types else ""}
        
        <div class="section">
            <h2 class="section-title">📈 Top 10 Most Active Processes</h2>
            <div class="chart-container">
                <div class="bar-chart">
                    {"".join([f"<div class='bar-item'><span class='bar-label' title='{proc}'>{proc}</span><div class='bar-outer'><div class='bar-inner' style='width: {100*count/max_count}%'></div></div><span class='bar-value'>{count:,}</span></div>" for proc, count in top10_processes])}
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2 class="section-title">🚨 Recent Errors (Top 50)</h2>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Timestamp</th>
                            <th>Process</th>
                            <th>PID</th>
                            <th>Message</th>
                        </tr>
                    </thead>
                    <tbody>
                        {generate_table_rows(errors)}
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <h2 class="section-title">⚠️ Recent Warnings (Top 50)</h2>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Timestamp</th>
                            <th>Process</th>
                            <th>PID</th>
                            <th>Message</th>
                        </tr>
                    </thead>
                    <tbody>
                        {generate_table_rows(warnings)}
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <h2 class="section-title">� Reboot & Restart Timeline</h2>
            <div class="timeline-container">
                <div class="timeline-legend">
                    <div class="timeline-legend-item">
                        <span class="timeline-legend-color" style="background: #DC3912;"></span>
                        <span><strong>AR</strong> - Appliance REBOOT ({len(appliance_reboots)})</span>
                    </div>
                    <div class="timeline-legend-item">
                        <span class="timeline-legend-color" style="background: #7FB3D5;"></span>
                        <span><strong>SR</strong> - System Restart ({len(system_restarts)})</span>
                    </div>
                </div>
                <div class="timeline-wrapper">
                    <div class="timeline-axis"></div>
                    {timeline_html}
                </div>
                <div style="text-align: center; margin-top: 15px; font-size: 12px; color: #7f8c8d;">
                    <em>Timeline shows all major reboot/restart events. Hover over markers for details. Bars show time intervals between events. Events are spaced with minimum 20px gap to prevent overlap.</em>
                </div>
            </div>
        </div>
        
        
        <div class="section">
            <h2 class="section-title">🔄 Appliance REBOOT & System Restart Events ({len(combined_reboot_restart_groups)} total: {len(appliance_reboots)} AR, {len(system_restarts)} SR)</h2>
            <div class="reboot-container">
                {combined_reboot_restart_html}
            </div>
        </div>
        
        <div class="section">
            <h2 class="section-title">� Process Lifecycle Across Reboots & Restarts</h2>
            <div class="info-box">
                <p><strong>This section tracks process start/stop cycles across multiple reboot and restart events.</strong></p>
                <p>Shows top 20 processes by activity with their average runtime, startup time, and lifecycle details.</p>
            </div>
            {process_lifecycle_html}
        </div>
        
        <div class="section">
            <h2 class="section-title">�💾 Database Events (Top 30)</h2>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Timestamp</th>
                            <th>Process</th>
                            <th>PID</th>
                            <th>Message</th>
                        </tr>
                    </thead>
                    <tbody>
                        {generate_table_rows(databases)}
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <h2 class="section-title">📋 Process-wise Logs - Errors, Warnings & Restarts</h2>
            <div class="process-container">
                {process_logs_html}
            </div>
            <div style="text-align: center; margin-top: 15px; font-size: 12px; color: #7f8c8d;">
                <em>Click on any process to expand/collapse its logs. Showing only errors, warnings, and restart/reboot events (up to 100 most recent per process).</em>
            </div>
        </div>
    </div>
</body>
</html>
"""

# Save HTML dashboard
with open("infoblox_dashboard.html", "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"\n✅ Dashboard saved as infoblox_dashboard.html")
print(f"📊 Analysis complete!")

EOF

# Run the Python script
python3 ${INFOBLOX_PY}

# Cleanup
rm ${INFOBLOX_PY}

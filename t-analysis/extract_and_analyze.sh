#!/bin/bash
# Extract all support bundles and run error analysis for a ticket
# Usage: ./extract_and_analyze.sh <TICKET_ID>

TICKET_ID="$1"
if [[ -z "$TICKET_ID" ]]; then
    echo "Usage: $0 <TICKET_ID>"
    exit 1
fi

TICKET_DIR="$HOME/analysis_support_tickets/$TICKET_ID"
cd "$TICKET_DIR" || { echo "Ticket directory not found: $TICKET_DIR"; exit 2; }

echo "Extraction starts."

extract_bundle() {
  local bundle_path="$1"
  local bundle_dir
  # Special handling for active_node_*.tar.gz and passive_node_*.tar.gz
  if [[ "$bundle_path" =~ active_node_.*\.tar\.gz$ ]]; then
    local target_dir="$(dirname "$bundle_path")/active"
    mkdir -p "$target_dir"
    echo "Extracting $bundle_path to $target_dir ..."
    tar -xzf "$bundle_path" -C "$target_dir"
    return
  fi
  if [[ "$bundle_path" =~ passive_node_.*\.tar\.gz$ ]]; then
    local target_dir="$(dirname "$bundle_path")/passive"
    mkdir -p "$target_dir"
    echo "Extracting $bundle_path to $target_dir ..."
    tar -xzf "$bundle_path" -C "$target_dir"
    return
  fi
  bundle_dir="${bundle_path%.*}_extract"
  echo "Extracting $bundle_path to $bundle_dir ..."
  mkdir -p "$bundle_dir"
  case "$bundle_path" in
    *.tar.gz|*.tgz) tar -xzf "$bundle_path" -C "$bundle_dir" ;;
    *.tar) tar -xf "$bundle_path" -C "$bundle_dir" ;;
    *.zip) unzip -q "$bundle_path" -d "$bundle_dir" ;;
    *) echo "Unknown bundle type: $bundle_path" ;;
  esac
}

# Extract bundles in ticket root
for bundle in *.tar.gz *.tgz *.zip *.tar; do
  [ -e "$bundle" ] || continue
  extract_bundle "$bundle"
done

# Extract bundles recursively under remote_files/
if [[ -d "remote_files" ]]; then
  find remote_files -type f \( -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" -o -name "*.tar" \) | while read -r bundle; do
    extract_bundle "$bundle"
  done
fi

echo "Extraction complete."

# Step 1b: Extract active_node_*.tar.gz and passive_node_*.tar.gz recursively under all extracted bundle directories
if [[ -d "remote_files" ]]; then
  find remote_files -type d -name "*_extract" | while read -r extract_dir; do
    find "$extract_dir" -type f -name "active_node*.tar.gz" | while read -r node_tar; do
      target_dir="$(dirname "$node_tar")/active"
      mkdir -p "$target_dir"
      echo "Extracting $node_tar to $target_dir ..."
      tar -xzf "$node_tar" -C "$target_dir"
    done
    find "$extract_dir" -type f -name "passive_node*.tar.gz" | while read -r node_tar; do
      target_dir="$(dirname "$node_tar")/passive"
      mkdir -p "$target_dir"
      echo "Extracting $node_tar to $target_dir ..."
      tar -xzf "$node_tar" -C "$target_dir"
    done
  done
fi

# Step 2: Run error extraction script (local only)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/extract-bundle-errors.sh" ]]; then
  bash "$SCRIPT_DIR/extract-bundle-errors.sh" "$TICKET_ID"
else
  echo "Error extraction script not found or not executable: $SCRIPT_DIR/extract-bundle-errors.sh"
  exit 3
fi

echo "Error extraction complete. Review generated/*_errors_warnings.txt for results."

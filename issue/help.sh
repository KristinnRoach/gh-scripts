#!/bin/bash
# ghi-help - Interactive help for ghi commands
# Usage: ghi-help [command]

set -e

# Colors for output
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get script for command
get_script() {
  case "$1" in
    ghi) echo "create.sh" ;;
    ghi-delete) echo "delete.sh" ;;
    *) echo "" ;;
  esac
}

# Get description for command
get_desc() {
  case "$1" in
    ghi) echo "Create a new issue" ;;
    ghi-delete) echo "Delete an issue" ;;
    *) echo "" ;;
  esac
}

# All commands
ALL_COMMANDS="ghi ghi-delete"

# If command specified directly, show its help
if [[ -n "$1" && "$1" != "-h" && "$1" != "--help" ]]; then
  CMD="$1"
  SCRIPT=$(get_script "$CMD")
  if [[ -n "$SCRIPT" ]]; then
    "$SCRIPT_DIR/$SCRIPT" --help
    exit 0
  else
    echo -e "${YELLOW}Unknown command: $CMD${NC}"
    echo "Available: $ALL_COMMANDS"
    exit 1
  fi
fi

# Show help for this command
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "ghi-help - Interactive help for ghi commands"
  echo ""
  echo "Usage: ghi-help [command]"
  echo ""
  echo "If no command specified, opens interactive selection."
  echo ""
  echo "Examples:"
  echo "  ghi-help          # Interactive selection"
  echo "  ghi-help ghi      # Show help for ghi (create)"
  exit 0
fi

# Interactive mode - requires fzf
if ! command -v fzf &>/dev/null; then
  echo -e "${BLUE}Available ghi commands:${NC}"
  echo ""
  for cmd in $ALL_COMMANDS; do
    DESC=$(get_desc "$cmd")
    printf "  %-14s %s\n" "$cmd" "$DESC"
  done
  echo ""
  echo -e "${YELLOW}Install fzf for interactive selection, or run: ghi-help <command>${NC}"
  exit 0
fi

# Build selection list
LIST=""
for cmd in $ALL_COMMANDS; do
  DESC=$(get_desc "$cmd")
  LIST+="${cmd}	${DESC}"$'\n'
done

echo -e "${BLUE}Select a command to see its help:${NC}"

SELECTED=$(echo -n "$LIST" | \
  fzf --height=40% \
      --layout=reverse \
      --prompt="Command: " \
      --header="Enter=select | Esc=exit" \
      --with-nth=1.. \
      --delimiter=$'\t' \
  2>/dev/null) || {
    exit 0
  }

if [[ -n "$SELECTED" ]]; then
  CMD=$(echo "$SELECTED" | cut -f1)
  SCRIPT=$(get_script "$CMD")
  echo ""
  "$SCRIPT_DIR/$SCRIPT" --help
fi

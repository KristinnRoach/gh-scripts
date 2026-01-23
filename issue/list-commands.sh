#!/bin/bash
# ghi-list - List available ghi commands
# Usage: ghi-list

# Colors for output
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Available ghi commands:${NC}"
echo ""
echo "  ghi           Create a new issue"
echo "  ghi-delete    Delete an issue"
echo ""
echo -e "${YELLOW}Use ghi-help or <command> --help for detailed usage.${NC}"

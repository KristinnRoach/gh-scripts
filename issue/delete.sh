#!/bin/bash
# gh-issue-delete - Delete a GitHub issue
# Usage: gh-issue-delete [number] [--yes] [--dry-run]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Aborted.${NC}"; exit 1' INT

# Initialize variables
ISSUE_NUMBER=""
SKIP_CONFIRM=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --yes|-y)
      SKIP_CONFIRM=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "gh-issue-delete - Delete a GitHub issue"
      echo ""
      echo "Usage: gh-issue-delete [number] [options]"
      echo ""
      echo "If no issue number is provided, opens interactive selection."
      echo ""
      echo "Options:"
      echo "  -y, --yes     Skip confirmation prompt"
      echo "  --dry-run     Preview without deleting"
      echo "  -h, --help    Show this help"
      echo ""
      echo "Examples:"
      echo "  gh-issue-delete           # Interactive selection"
      echo "  gh-issue-delete 42        # Delete issue #42"
      echo "  gh-issue-delete 42 --yes  # Delete without confirmation"
      exit 0
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
    *)
      ISSUE_NUMBER="$1"
      shift
      ;;
  esac
done

# Check for git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo -e "${RED}Error: Not inside a git repository${NC}"
  exit 1
fi

# Get repo info from git remote
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ -z "$REMOTE_URL" ]]; then
  echo -e "${RED}Error: No git remote 'origin' found${NC}"
  exit 1
fi

# Extract owner/repo from remote URL
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  echo -e "${RED}Error: Could not parse GitHub repo from remote URL${NC}"
  echo "Remote URL: $REMOTE_URL"
  exit 1
fi

REPO_FULL="$OWNER/$REPO"
echo -e "${BLUE}Repository: ${NC}$REPO_FULL"

# If no issue number provided, select interactively
if [[ -z "$ISSUE_NUMBER" ]]; then
  if ! command -v fzf &>/dev/null; then
    echo -e "${RED}Error: fzf required for interactive selection${NC}"
    echo "Install fzf or provide issue number: gh-issue-delete <number>"
    exit 1
  fi

  echo -e "${YELLOW}Fetching issues...${NC}"

  # Get open issues
  ISSUES=$(gh issue list --repo "$REPO_FULL" --state open --json number,title --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null)

  if [[ -z "$ISSUES" ]]; then
    echo -e "${YELLOW}No open issues found.${NC}"
    exit 0
  fi

  echo -e "${YELLOW}Select issue to delete:${NC}"

  SELECTED=$(echo "$ISSUES" | \
    fzf --height=40% \
        --layout=reverse \
        --prompt="Delete issue: " \
        --header="Enter=select | Esc=abort" \
        --with-nth=1.. \
        --delimiter=$'\t' \
    2>/dev/null) || {
      echo -e "${YELLOW}Aborted.${NC}"
      exit 1
    }

  ISSUE_NUMBER=$(echo "$SELECTED" | cut -f1)
fi

# Validate issue number
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Error: Invalid issue number: $ISSUE_NUMBER${NC}"
  exit 1
fi

# Fetch issue details for confirmation
echo -e "${YELLOW}Fetching issue #$ISSUE_NUMBER...${NC}"
ISSUE_DATA=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO_FULL" --json number,title,state,labels,author 2>/dev/null) || {
  echo -e "${RED}Error: Issue #$ISSUE_NUMBER not found${NC}"
  exit 1
}

ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
ISSUE_STATE=$(echo "$ISSUE_DATA" | jq -r '.state')
ISSUE_AUTHOR=$(echo "$ISSUE_DATA" | jq -r '.author.login')
ISSUE_LABELS=$(echo "$ISSUE_DATA" | jq -r '.labels | map(.name) | join(", ")' | sed 's/^$/none/')

echo ""
echo -e "${BLUE}Issue:${NC}  #$ISSUE_NUMBER - $ISSUE_TITLE"
echo -e "${BLUE}State:${NC}  $ISSUE_STATE"
echo -e "${BLUE}Author:${NC} $ISSUE_AUTHOR"
echo -e "${BLUE}Labels:${NC} $ISSUE_LABELS"
echo ""

# Dry run - show what would be deleted
if [[ "$DRY_RUN" == true ]]; then
  echo -e "${GREEN}=== DRY RUN ===${NC}"
  echo -e "Would delete issue #$ISSUE_NUMBER: $ISSUE_TITLE"
  exit 0
fi

# Confirm deletion
if [[ "$SKIP_CONFIRM" != true ]]; then
  echo -ne "${RED}Delete this issue permanently? (y/N): ${NC}"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 1
  fi
fi

# Delete the issue
gh issue delete "$ISSUE_NUMBER" --repo "$REPO_FULL" --yes

echo -e "${GREEN}Deleted issue #$ISSUE_NUMBER${NC}"

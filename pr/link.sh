#!/bin/bash
# ghpr-link - Link a PR to a GitHub Project
# Usage: ghpr-link [pr-number] [--dry-run]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Aborted.${NC}"; exit 1' INT

# Function to prompt for abort confirmation
prompt_abort() {
  echo -ne "${YELLOW}Abort? (y/N): ${NC}"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 1
  fi
}

# Initialize variables
PR_NUMBER=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "ghpr-link - Link a PR to a GitHub Project and optionally an Issue"
      echo ""
      echo "Usage: ghpr-link [pr-number] [options]"
      echo ""
      echo "If no PR number is provided, opens interactive selection."
      echo "After selecting a project, you can optionally link to an issue:"
      echo "  - Closes #X    (auto-close issue when PR merges)"
      echo "  - Relates to #X (reference only)"
      echo ""
      echo "Options:"
      echo "  --dry-run     Preview without linking"
      echo "  -h, --help    Show this help"
      echo ""
      echo "Examples:"
      echo "  ghpr-link             # Interactive selection"
      echo "  ghpr-link 42          # Link PR #42 to a project"
      echo "  ghpr-link 42 --dry-run"
      exit 0
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
    *)
      PR_NUMBER="$1"
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

# If no PR number provided, select interactively
if [[ -z "$PR_NUMBER" ]]; then
  if ! command -v fzf &>/dev/null; then
    echo -e "${RED}Error: fzf required for interactive selection${NC}"
    echo "Install fzf or provide PR number: ghpr-link <number>"
    exit 1
  fi

  echo -e "${YELLOW}Fetching PRs...${NC}"

  # Get all PRs (open, closed, merged)
  PRS=$(gh pr list --repo "$REPO_FULL" --state all --json number,title,headRefName,state --jq '.[] | "\(.number)\t\(.title)\t(\(.headRefName)) [\(.state)]"' 2>/dev/null)

  if [[ -z "$PRS" ]]; then
    echo -e "${YELLOW}No PRs found.${NC}"
    exit 0
  fi

  echo -e "${YELLOW}Select PR to link:${NC}"

  while true; do
    set +e
    SELECTED=$(echo "$PRS" | \
      fzf --height=40% \
          --layout=reverse \
          --prompt="PR: " \
          --header="Enter=select | Esc=abort" \
          --with-nth=1.. \
          --delimiter=$'\t' \
      2>/dev/null)
    FZF_EXIT=${PIPESTATUS[1]}
    set -e

    if [[ $FZF_EXIT -eq 1 ]]; then
      prompt_abort
      continue
    fi
    break
  done

  if [[ -z "$SELECTED" ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 1
  fi

  PR_NUMBER=$(echo "$SELECTED" | cut -f1)
fi

# Validate PR number
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Error: Invalid PR number: $PR_NUMBER${NC}"
  exit 1
fi

# Fetch PR details
echo -e "${YELLOW}Fetching PR #$PR_NUMBER...${NC}"
PR_DATA=$(gh pr view "$PR_NUMBER" --repo "$REPO_FULL" --json number,title,headRefName,state,url 2>/dev/null) || {
  echo -e "${RED}Error: PR #$PR_NUMBER not found${NC}"
  exit 1
}

PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')
PR_BRANCH=$(echo "$PR_DATA" | jq -r '.headRefName')
PR_STATE=$(echo "$PR_DATA" | jq -r '.state')
PR_URL=$(echo "$PR_DATA" | jq -r '.url')

echo -e "${BLUE}PR:${NC}     #$PR_NUMBER - $PR_TITLE"
echo -e "${BLUE}Branch:${NC} $PR_BRANCH"
echo -e "${BLUE}State:${NC}  $PR_STATE"

# Select project
echo -e "${YELLOW}Finding projects...${NC}"
PROJECTS_JSON=$(gh project list --owner "$OWNER" --format json 2>/dev/null || echo '{"projects":[]}')
PROJECT_COUNT=$(echo "$PROJECTS_JSON" | jq '.projects | length')

if [[ "$PROJECT_COUNT" -eq 0 ]]; then
  echo -e "${RED}No projects found for $OWNER${NC}"
  exit 1
fi

PROJECT_NUMBER=""
if [[ "$PROJECT_COUNT" -eq 1 ]]; then
  PROJECT_NUMBER=$(echo "$PROJECTS_JSON" | jq -r '.projects[0].number')
  PROJECT_TITLE=$(echo "$PROJECTS_JSON" | jq -r '.projects[0].title')
  echo -e "${BLUE}Project: ${NC}$PROJECT_TITLE"
else
  if ! command -v fzf &>/dev/null; then
    echo "Available projects:"
    echo "$PROJECTS_JSON" | jq -r '.projects[] | "  \(.number): \(.title)"'
    echo -ne "${YELLOW}Enter project number: ${NC}"
    read -r PROJECT_NUMBER
  else
    # Try to find a project matching the repo name
    DEFAULT_PROJECT_NUM=$(echo "$PROJECTS_JSON" | jq -r --arg repo "$REPO" \
      '.projects[] | select(.title | ascii_downcase | contains($repo | ascii_downcase)) | .number' | head -1)

    echo -e "${YELLOW}Select project:${NC}"

    PROJECT_LIST=""
    if [[ -n "$DEFAULT_PROJECT_NUM" ]]; then
      DEFAULT_TITLE=$(echo "$PROJECTS_JSON" | jq -r --arg num "$DEFAULT_PROJECT_NUM" \
        '.projects[] | select(.number == ($num | tonumber)) | .title')
      PROJECT_LIST="${DEFAULT_PROJECT_NUM}	${DEFAULT_TITLE} (Default)"
      while IFS= read -r line; do
        [[ -n "$line" ]] && PROJECT_LIST+=$'\n'"$line"
      done < <(echo "$PROJECTS_JSON" | jq -r --arg num "$DEFAULT_PROJECT_NUM" \
        '.projects[] | select(.number != ($num | tonumber)) | "\(.number)\t\(.title)"')
    else
      while IFS= read -r line; do
        if [[ -n "$line" ]]; then
          if [[ -z "$PROJECT_LIST" ]]; then
            PROJECT_LIST="$line"
          else
            PROJECT_LIST+=$'\n'"$line"
          fi
        fi
      done < <(echo "$PROJECTS_JSON" | jq -r '.projects[] | "\(.number)\t\(.title)"')
    fi

    while true; do
      set +e
      SELECTED_PROJECT=$(echo "$PROJECT_LIST" | \
        fzf --height=40% \
            --layout=reverse \
            --prompt="Project: " \
            --header="Enter=select | Esc=abort" \
            --with-nth=2.. \
            --delimiter=$'\t' \
            --no-sort \
        2>/dev/null)
      FZF_EXIT=${PIPESTATUS[1]}
      set -e

      if [[ $FZF_EXIT -eq 1 ]]; then
        prompt_abort
        continue
      fi
      break
    done

    if [[ -n "$SELECTED_PROJECT" ]]; then
      PROJECT_NUMBER=$(echo "$SELECTED_PROJECT" | cut -f1)
      PROJECT_TITLE=$(echo "$SELECTED_PROJECT" | cut -f2 | sed 's/ (Default)$//')
      echo -e "${BLUE}Project: ${NC}$PROJECT_TITLE"
    fi
  fi
fi

if [[ -z "$PROJECT_NUMBER" ]]; then
  echo -e "${RED}Error: No project selected${NC}"
  exit 1
fi

# Optional: Link to an issue
ISSUE_LINK_TYPE=""
ISSUE_NUMBER=""

if command -v fzf &>/dev/null; then
  echo -e "${YELLOW}Link to an issue? (optional)${NC}"

  LINK_OPTIONS="skip	Skip - Don't link to an issue
closes	Closes #X - Auto-close issue when PR merges
relates	Relates to #X - Reference only (no auto-close)"

  while true; do
    set +e
    SELECTED_LINK=$(echo "$LINK_OPTIONS" | \
      fzf --height=20% \
          --layout=reverse \
          --prompt="Issue link: " \
          --header="Enter=select | Esc=abort" \
          --with-nth=2.. \
          --delimiter=$'\t' \
          --no-sort \
      2>/dev/null)
    FZF_EXIT=${PIPESTATUS[1]}
    set -e

    if [[ $FZF_EXIT -eq 1 ]]; then
      prompt_abort
      continue
    fi
    break
  done

  ISSUE_LINK_TYPE=$(echo "$SELECTED_LINK" | cut -f1)

  if [[ "$ISSUE_LINK_TYPE" != "skip" && -n "$ISSUE_LINK_TYPE" ]]; then
    echo -e "${YELLOW}Fetching issues...${NC}"
    ISSUES=$(gh issue list --repo "$REPO_FULL" --state open --json number,title --jq '.[] | "\(.number)\t#\(.number) \(.title)"' 2>/dev/null)

    if [[ -z "$ISSUES" ]]; then
      echo -e "${YELLOW}No open issues found. Skipping issue link.${NC}"
      ISSUE_LINK_TYPE="skip"
    else
      echo -e "${YELLOW}Select issue:${NC}"

      while true; do
        set +e
        SELECTED_ISSUE=$(echo "$ISSUES" | \
          fzf --height=40% \
              --layout=reverse \
              --prompt="Issue: " \
              --header="Enter=select | Esc=skip" \
              --with-nth=2.. \
              --delimiter=$'\t' \
          2>/dev/null)
        FZF_EXIT=${PIPESTATUS[1]}
        set -e

        if [[ $FZF_EXIT -eq 1 ]]; then
          echo -e "${YELLOW}Skipping issue link.${NC}"
          ISSUE_LINK_TYPE="skip"
          break
        fi
        break
      done

      if [[ -n "$SELECTED_ISSUE" ]]; then
        ISSUE_NUMBER=$(echo "$SELECTED_ISSUE" | cut -f1)
        ISSUE_TITLE=$(echo "$SELECTED_ISSUE" | cut -f2)
        echo -e "${BLUE}Issue:${NC}  $ISSUE_TITLE"
      fi
    fi
  fi
fi

# Dry run
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo -e "${GREEN}=== DRY RUN ===${NC}"
  echo -e "Would link PR #$PR_NUMBER to project #$PROJECT_NUMBER"
  if [[ -n "$ISSUE_NUMBER" && "$ISSUE_LINK_TYPE" != "skip" ]]; then
    if [[ "$ISSUE_LINK_TYPE" == "closes" ]]; then
      echo -e "Would add 'Closes #$ISSUE_NUMBER' to PR body"
    else
      echo -e "Would add 'Relates to #$ISSUE_NUMBER' to PR body"
    fi
  fi
  exit 0
fi

# Link PR to project
echo -e "${YELLOW}Linking PR to project...${NC}"
gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$PR_URL" && \
  echo -e "${GREEN}Linked PR #$PR_NUMBER to project${NC}" || \
  echo -e "${RED}Failed to link PR to project${NC}"

# Link to issue if selected
if [[ -n "$ISSUE_NUMBER" && "$ISSUE_LINK_TYPE" != "skip" ]]; then
  echo -e "${YELLOW}Linking to issue...${NC}"

  # Get current PR body
  CURRENT_BODY=$(gh pr view "$PR_NUMBER" --repo "$REPO_FULL" --json body --jq '.body' 2>/dev/null)

  # Build link text
  if [[ "$ISSUE_LINK_TYPE" == "closes" ]]; then
    LINK_TEXT="Closes #$ISSUE_NUMBER"
  else
    LINK_TEXT="Relates to #$ISSUE_NUMBER"
  fi

  # Append to body
  if [[ -z "$CURRENT_BODY" ]]; then
    NEW_BODY="$LINK_TEXT"
  else
    NEW_BODY="$CURRENT_BODY

$LINK_TEXT"
  fi

  # Use REST API directly to avoid deprecated projectCards GraphQL query
  gh api "repos/$REPO_FULL/pulls/$PR_NUMBER" --method PATCH -f body="$NEW_BODY" > /dev/null && \
    echo -e "${GREEN}Added '$LINK_TEXT' to PR body${NC}" || \
    echo -e "${RED}Failed to update PR body${NC}"
fi

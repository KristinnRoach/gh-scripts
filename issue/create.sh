#!/bin/bash
# gh-issue - Quick GitHub issue creation with smart defaults
# Usage: gh-issue "Title" "Description" [-e "errors"] [--dry-run] [--open]

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
  echo -ne "${YELLOW}Abort creating this issue? (y/N): ${NC}"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 1
  fi
}

# Initialize variables
TITLE=""
DESCRIPTION=""
ERRORS=""
DRY_RUN=false
OPEN_AFTER=false
POSITIONAL_ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--title)
      TITLE="$2"
      shift 2
      ;;
    -d|--description)
      DESCRIPTION="$2"
      shift 2
      ;;
    -e|--errors)
      ERRORS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --open)
      OPEN_AFTER=true
      shift
      ;;
    -h|--help)
      echo "gh-issue - Quick GitHub issue creation"
      echo ""
      echo "Usage: gh-issue [title] [options]"
      echo ""
      echo "Interactive by default - prompts for missing info."
      echo "Press Enter to skip/use defaults at any prompt."
      echo ""
      echo "Options:"
      echo "  -t, --title       Issue title (or first positional arg)"
      echo "  -d, --description Issue description (or prompted interactively)"
      echo "  -e, --errors      Error/log content (appended in separate section)"
      echo "  --dry-run         Preview without creating"
      echo "  --open            Open issue in browser after creation"
      echo "  -h, --help        Show this help"
      echo ""
      echo "Examples:"
      echo "  gh-issue \"Fix bug\"                    # Prompts for description, labels, project"
      echo "  gh-issue \"Fix bug\" \"Details here\"     # Skips description prompt"
      echo "  gh-issue -t \"Title\" -d \"Description\"  # Explicit flags"
      echo "  gh-issue \"Title\" -e \"Error logs\"      # With error/log content"
      exit 0
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# Fill in from positional args if flags weren't used
if [[ -z "$TITLE" && ${#POSITIONAL_ARGS[@]} -ge 1 ]]; then
  TITLE="${POSITIONAL_ARGS[0]}"
fi
if [[ -z "$DESCRIPTION" && ${#POSITIONAL_ARGS[@]} -ge 2 ]]; then
  DESCRIPTION="${POSITIONAL_ARGS[1]}"
fi

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

# Prompt for title if not provided
if [[ -z "$TITLE" ]]; then
  echo -ne "${YELLOW}Title: ${NC}"
  read -r TITLE
  if [[ -z "$TITLE" ]]; then
    echo -e "${RED}Error: Title is required${NC}"
    exit 1
  fi
fi

# Prompt for description if not provided
if [[ -z "$DESCRIPTION" ]]; then
  echo -ne "${YELLOW}Description (Enter to skip): ${NC}"
  read -r DESCRIPTION
fi

# Build the issue body
BODY="${DESCRIPTION:-_No description provided_}"
if [[ -n "$ERRORS" ]]; then
  BODY="$BODY

---
**Error/Logs:**
\`\`\`
$ERRORS
\`\`\`"
fi

# Get GitHub username for auto-assign
GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")

# Select labels interactively
LABELS="enhancement"
if command -v fzf &>/dev/null; then
  echo -e "${YELLOW}Labels (Tab=select, Enter=confirm):${NC}"

  # Get all labels, put "enhancement" at top with (Default) hint, filter it from the rest
  ALL_LABELS=$(gh label list --repo "$REPO_FULL" --json name -q '.[].name' 2>/dev/null)
  OTHER_LABELS=$(echo "$ALL_LABELS" | grep -v "^enhancement$" || true)
  LABEL_LIST="enhancement (Default)"$'\n'"$OTHER_LABELS"

  # Loop until user makes a selection or confirms abort
  while true; do
    set +e
    SELECTED_LABELS=$(echo "$LABEL_LIST" | \
      fzf --multi \
          --height=40% \
          --layout=reverse \
          --prompt="Labels: " \
          --header="Tab=select │ Enter=confirm │ Esc=abort" \
          --bind="ctrl-n:execute(echo '__NEW_LABEL__')+abort" \
          --no-sort \
          --preview-window=hidden \
      2>/dev/null)
    FZF_EXIT=${PIPESTATUS[1]}
    set -e

    # Esc pressed - prompt to abort, if no then loop back
    if [[ $FZF_EXIT -eq 1 ]]; then
      prompt_abort
      continue
    fi
    break
  done

  # Clean up the (Default) suffix
  SELECTED_LABELS=$(echo "$SELECTED_LABELS" | sed 's/ (Default)$//')

  if [[ "$SELECTED_LABELS" == "__NEW_LABEL__" ]]; then
    echo -ne "${YELLOW}New label name: ${NC}"
    read -r NEW_LABEL_NAME
    if [[ -n "$NEW_LABEL_NAME" ]]; then
      echo -ne "${YELLOW}Label color (hex without #, e.g. 'ff6600'): ${NC}"
      read -r NEW_LABEL_COLOR
      gh label create "$NEW_LABEL_NAME" --repo "$REPO_FULL" --color "${NEW_LABEL_COLOR:-cccccc}" 2>/dev/null || true
      LABELS="$NEW_LABEL_NAME"
    fi
  elif [[ -n "$SELECTED_LABELS" ]]; then
    # Convert newlines to commas
    LABELS=$(echo "$SELECTED_LABELS" | tr '\n' ',' | sed 's/,$//')
  fi
fi

echo -e "${BLUE}Labels: ${NC}$LABELS"

# Find linked projects
echo -e "${YELLOW}Finding linked projects...${NC}"
PROJECTS_JSON=$(gh project list --owner "$OWNER" --format json 2>/dev/null || echo '{"projects":[]}')
PROJECT_COUNT=$(echo "$PROJECTS_JSON" | jq '.projects | length')

PROJECT_NUMBER=""
if [[ "$PROJECT_COUNT" -eq 0 ]]; then
  echo -e "${YELLOW}No projects found. Issue will be created without a project.${NC}"
elif [[ "$PROJECT_COUNT" -eq 1 ]]; then
  PROJECT_NUMBER=$(echo "$PROJECTS_JSON" | jq -r '.projects[0].number')
  PROJECT_TITLE=$(echo "$PROJECTS_JSON" | jq -r '.projects[0].title')
  echo -e "${BLUE}Project: ${NC}$PROJECT_TITLE"
else
  # Try to find a project matching the repo name (case-insensitive)
  DEFAULT_PROJECT_NUM=$(echo "$PROJECTS_JSON" | jq -r --arg repo "$REPO" \
    '.projects[] | select(.title | ascii_downcase | contains($repo | ascii_downcase)) | .number' | head -1)

  if command -v fzf &>/dev/null; then
    echo -e "${YELLOW}Select project:${NC}"

    # Build project list with proper formatting
    PROJECT_LIST=""
    if [[ -n "$DEFAULT_PROJECT_NUM" ]]; then
      # Default project first with (Default) hint
      DEFAULT_TITLE=$(echo "$PROJECTS_JSON" | jq -r --arg num "$DEFAULT_PROJECT_NUM" \
        '.projects[] | select(.number == ($num | tonumber)) | .title')
      PROJECT_LIST="${DEFAULT_PROJECT_NUM}	${DEFAULT_TITLE} (Default)"
      PROJECT_LIST+=$'\n'"0	Skip (Don't link to a Project)"
      # Add other projects
      while IFS= read -r line; do
        [[ -n "$line" ]] && PROJECT_LIST+=$'\n'"$line"
      done < <(echo "$PROJECTS_JSON" | jq -r --arg num "$DEFAULT_PROJECT_NUM" \
        '.projects[] | select(.number != ($num | tonumber)) | "\(.number)\t\(.title)"')
    else
      # No default found, skip first
      PROJECT_LIST="0	Skip (Don't link to a Project)"
      while IFS= read -r line; do
        [[ -n "$line" ]] && PROJECT_LIST+=$'\n'"$line"
      done < <(echo "$PROJECTS_JSON" | jq -r '.projects[] | "\(.number)\t\(.title)"')
    fi

    # Loop until user makes a selection or confirms abort
    while true; do
      set +e
      SELECTED_PROJECT=$(echo "$PROJECT_LIST" | \
        fzf --height=40% \
            --layout=reverse \
            --prompt="Project: " \
            --header="Enter=select │ Esc=abort" \
            --with-nth=2.. \
            --delimiter=$'\t' \
            --no-sort \
        2>/dev/null)
      FZF_EXIT=${PIPESTATUS[1]}
      set -e

      # Esc pressed - prompt to abort, if no then loop back
      if [[ $FZF_EXIT -eq 1 ]]; then
        prompt_abort
        continue
      fi
      break
    done

    if [[ -n "$SELECTED_PROJECT" && ! "$SELECTED_PROJECT" =~ ^0$'\t' ]]; then
      PROJECT_NUMBER=$(echo "$SELECTED_PROJECT" | cut -f1)
      PROJECT_TITLE=$(echo "$SELECTED_PROJECT" | cut -f2 | sed 's/ (Default)$//')
      echo -e "${BLUE}Project: ${NC}$PROJECT_TITLE"
    else
      echo -e "${BLUE}Project: ${NC}(none)"
    fi
  else
    # No fzf, list projects and ask for number
    echo "Available projects:"
    echo "$PROJECTS_JSON" | jq -r '.projects[] | "  \(.number): \(.title)"'
    echo -ne "${YELLOW}Enter project number (or Enter to skip): ${NC}"
    read -r PROJECT_NUMBER
  fi
fi

# Dry run - show what would be created
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo -e "${GREEN}=== DRY RUN - Would create: ===${NC}"
  echo -e "${BLUE}Repository:${NC} $REPO_FULL"
  echo -e "${BLUE}Title:${NC} $TITLE"
  echo -e "${BLUE}Labels:${NC} $LABELS"
  [[ -n "$PROJECT_NUMBER" ]] && echo -e "${BLUE}Project:${NC} #$PROJECT_NUMBER"
  [[ -n "$GH_USER" ]] && echo -e "${BLUE}Assignee:${NC} $GH_USER"
  echo -e "${BLUE}Body:${NC}"
  echo "$BODY"
  exit 0
fi

# Create the issue
echo -e "${YELLOW}Creating issue...${NC}"

CREATE_CMD="gh issue create --repo \"$REPO_FULL\" --title \"$TITLE\" --label \"$LABELS\""
[[ -n "$GH_USER" ]] && CREATE_CMD="$CREATE_CMD --assignee \"$GH_USER\""

# Use a temp file for the body to handle special characters
BODY_FILE=$(mktemp)
echo "$BODY" > "$BODY_FILE"

ISSUE_URL=$(gh issue create \
  --repo "$REPO_FULL" \
  --title "$TITLE" \
  --label "$LABELS" \
  ${GH_USER:+--assignee "$GH_USER"} \
  --body-file "$BODY_FILE" \
  2>&1)

rm -f "$BODY_FILE"

# Extract issue number from URL
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$' || echo "")

echo -e "${GREEN}✓ Issue created: ${NC}$ISSUE_URL"

# Add to project if selected
if [[ -n "$PROJECT_NUMBER" && -n "$ISSUE_URL" ]]; then
  echo -e "${YELLOW}Adding to project...${NC}"
  gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$ISSUE_URL" 2>/dev/null && \
    echo -e "${GREEN}✓ Added to project${NC}" || \
    echo -e "${YELLOW}Warning: Could not add to project${NC}"
fi

# Open in browser if requested
if [[ "$OPEN_AFTER" == true && -n "$ISSUE_URL" ]]; then
  open "$ISSUE_URL" 2>/dev/null || xdg-open "$ISSUE_URL" 2>/dev/null || echo "Open: $ISSUE_URL"
fi

echo -e "${GREEN}Done!${NC}"

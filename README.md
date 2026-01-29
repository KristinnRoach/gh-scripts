# gh-scripts

GitHub CLI helper scripts with interactive defaults.

## Installation

```bash
# Clone to your scripts directory
git clone https://github.com/KristinnRoach/gh-scripts.git ~/kidScripts/gh

# Add to ~/.zshrc
[ -f ~/kidScripts/gh/aliases.sh ] && source ~/kidScripts/gh/aliases.sh
```

## Commands

### Issues (`ghi` / `gh-issue`)

| Command           | Alias        | Description                  |
| ----------------- | ------------ | ---------------------------- |
| `gh-issue`        | `ghi`        | Create issue (interactive)   |
| `gh-issue-delete` | `ghi-delete` | Delete an issue              |
| `gh-issue-close`  | `ghi-close`  | Close an issue               |
| `gh-issue-list`   | `ghi-list`   | List issues                  |
| `gh-issue-move`   | `ghi-move`   | Move between project columns |
| `gh-issue-task`   | `ghi-task`   | Manage issue task lists      |
| `gh-issue-help`   | `ghi-help`   | Show all commands            |

### Pull Requests (`ghpr` / `gh-pr`)

| Command      | Alias       | Description                           |
| ------------ | ----------- | ------------------------------------- |
| `gh-pr-link` | `ghpr-link` | Link PR to project (+ optional issue) |

### Projects (`ghp` / `gh-project`)

_Coming soon_

## Usage

```bash
# Interactive (prompts for description, labels, project)
ghi "Issue title"

# With description
ghi "Issue title" "Description here"

# Preview without creating
ghi "Issue title" --dry-run

# Flags
ghi -t "Title" -d "Description" -e "Error logs"
ghi "Issue title" --open  # Opens in browser after creation

# Tips
# In the label picker, choose "New label…" (or press Ctrl+N) to create a label and return with it preselected.

## Dry-run policy
`--dry-run` must never have side-effects unless explicitly documented and made obvious during execution.
```

## Requirements

- [GitHub CLI](https://cli.github.com/) (`gh`)
- [fzf](https://github.com/junegunn/fzf) (for interactive selection)

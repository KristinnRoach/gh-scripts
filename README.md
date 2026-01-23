# gh-scripts

GitHub CLI helper scripts with interactive defaults.

## Installation

```bash
# Clone to your scripts directory
git clone https://github.com/KristinnRoach/gh-scripts.git ~/kidScripts/gh

# Add aliases to ~/.zshrc
alias gh-issue="~/kidScripts/gh/issue/create.sh"
alias ghi="~/kidScripts/gh/issue/create.sh"
```

## Commands

### Issues (`ghi` / `gh-issue`)

| Command | Alias | Description |
|---------|-------|-------------|
| `gh-issue` | `ghi` | Create issue (interactive) |
| `gh-issue-close` | `ghi-close` | Close an issue |
| `gh-issue-list` | `ghi-list` | List issues |
| `gh-issue-move` | `ghi-move` | Move between project columns |
| `gh-issue-task` | `ghi-task` | Manage issue task lists |
| `gh-issue-help` | `ghi-help` | Show all commands |

### Projects (`ghp` / `gh-project`)

*Coming soon*

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
```

## Requirements

- [GitHub CLI](https://cli.github.com/) (`gh`)
- [fzf](https://github.com/junegunn/fzf) (for interactive selection)

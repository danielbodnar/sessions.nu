# AGENTS.md - sessions.nu

Guidelines for AI coding agents working on this Nushell module.

## Project Overview

A pure Nushell module for tracking shell command history and browser sessions.
No build step required - modules are loaded directly by Nushell.

**Repository**: `https://github.com/danielbodnar/sessions.nu.git`

## Architecture

```
sessions/
├── mod.nu       # Public API, CLI commands, exports
├── core.nu      # Session building logic, atuin queries
├── utils.nu     # Utilities, date formatting, config loading
├── browser.nu   # Browser history parsing (Chrome/Firefox)
├── reports.nu   # Aggregation and reporting functions
└── data/        # Test data (gitignored)
```

## Commands

### Loading the Module

```nushell
# Load with namespace
use ~/.config/nushell/modules/sessions

# Load all exports into current scope
use ~/.config/nushell/modules/sessions *
```

### Testing Commands

No automated test framework. Test manually:

```nushell
# Verify module loads
sessions --help

# Test specific commands
sessions weekly
sessions browser paths
sessions --grace-period 30min
```

### Running Nushell Scripts

```nushell
# Execute a script file
nu path/to/script.nu

# Check syntax without running
nu --ide-check path/to/file.nu
```

## Code Style

### Naming Conventions

| Element      | Convention           | Example                        |
|--------------|----------------------|--------------------------------|
| Functions    | `kebab-case`         | `resolve-patterns`, `to-date`  |
| Variables    | `snake_case`         | `grace_period`, `total_dur`    |
| Constants    | `SCREAMING_SNAKE`    | `DEFAULT_GRACE_PERIOD`         |
| Flags        | `--kebab-case (-x)`  | `--grace-period (-g)`          |

### Import Style

```nushell
# Explicit named imports (preferred for public APIs)
export use utils.nu [
    DEFAULT_GRACE_PERIOD
    config-dir
    format-hours
]

# Wildcard for internal use within module
use utils.nu *
use core.nu *
```

### Type Annotations

All exported functions MUST have explicit type signatures:

```nushell
# Full signature with input/output types
export def process-data [
    patterns: list<string>     # Required parameter
    --grace (-g): duration     # Optional flag
    --verbose (-v)             # Boolean flag
]: table -> table {
    # implementation
}

# When no input expected
export def get-config []: nothing -> record {
    # implementation
}
```

### Documentation

```nushell
# Brief description on first line
#
# Longer explanation if needed.
#
# # Examples
#
# ```nushell
# command --flag value
# # => expected output
# ```
export def command-name [
    arg: type    # Inline param description
]: input -> output {
    # ...
}
```

### Error Handling

```nushell
# Custom errors with context
error make {
    msg: "Descriptive error message"
    help: "Suggestion for resolution"
    label: {
        text: "What went wrong"
        span: (metadata $variable).span
    }
}

# Try/catch for recoverable errors
try {
    risky-operation
} catch { |e|
    print $"Warning: ($e.msg)"
    $default_value
}
```

### Pipeline Patterns

Design functions to work with pipelines and `$in`:

```nushell
# Good: Pipeline-friendly
export def transform []: table -> table {
    $in
    | each { |r| { ...$r, processed: true } }
    | where valid == true
}

# Usage
data | transform | save output.json
```

### Record Construction

```nushell
# Spread operator for extending records
{ ...$existing, new_field: $value }

# Multi-line for complex records
{
    date: ($timestamp | to-date)
    duration: $dur
    commands: ($cmds | length)
}
```

### Conditional Logic

```nushell
# Ternary-style
let result = if $condition { $a } else { $b }

# Match expressions for multiple branches
match $option {
    "day" => { daily-report }
    "week" => { weekly-report }
    "month" => { monthly-report }
    _ => { error make { msg: "Invalid option" } }
}
```

### Mutable Variables

Use `mut` only when necessary (building lists in loops):

```nushell
mut results = []
for item in $items {
    $results = ($results | append (process $item))
}
```

## Git Conventions

### Commit Messages

Use conventional-ish commits:

```
feat: add browser history tracking support
fix: correct timestamp parsing for Firefox
docs: update README with configuration examples
refactor: extract date formatting to utils
```

### Branch Naming

```
feat/feature-name
fix/bug-description
```

## Dependencies

**Runtime**: Nushell v0.100+

**External Tools** (optional):
- [atuin](https://atuin.sh/) - Shell history database (required for shell tracking)
- Chrome/Firefox - For browser history tracking

**No npm/Node dependencies** - pure Nushell module.

## Database Queries

Uses Nushell's built-in SQLite support:

```nushell
open ~/.local/share/atuin/history.db
| query db "
    SELECT timestamp, command, cwd
    FROM history
    WHERE deleted_at IS NULL
    ORDER BY timestamp
"
```

## Duration Literals

Nushell supports duration literals:

```nushell
30min    # 30 minutes
1hr      # 1 hour  
1day     # 1 day
60sec    # 60 seconds
```

## Common Patterns

### Guard Clauses

Validate early, fail fast:

```nushell
export def process [data: any]: nothing -> table {
    if ($data | is-empty) {
        return []
    }
    # ... rest of function
}
```

### Higher-Order Functions

```nushell
$data
| each { |row| transform $row }
| where { |r| $r.valid }
| group-by category
| transpose key items
```

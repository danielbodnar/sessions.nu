# sessions.nu

> Time tracking from your shell and browser history — beautifully

A Nushell module that analyzes your [atuin](https://atuin.sh/) shell history and browser history to track time spent on projects. Groups commands and page visits into sessions based on time gaps, with configurable grace periods and flexible pattern matching.

## Features

- **Automatic session detection** — Groups commands/visits into work sessions based on configurable time gaps
- **Shell history tracking** — Via [atuin](https://atuin.sh/) for directory-based pattern matching
- **Browser history tracking** — Chrome Canary, Chrome Unstable, Firefox Developer Edition, and more
- **Flexible pattern matching** — Filter by directory paths, project names, IP addresses, or domains
- **Multiple aggregation levels** — View by session, day, week, or month
- **Native Nushell types** — All dates are `datetime` objects for powerful filtering
- **Configurable** — Via config files, CLI flags, or piped input
- **Beautiful output** — Tables, CSV, JSON, Markdown, and more

## Installation

### Prerequisites

- [Nushell](https://www.nushell.sh/) v0.100+
- [atuin](https://atuin.sh/) for shell history (optional but recommended)
- Chrome/Chromium or Firefox for browser history (optional)

### Setup

```bash
# Clone the repo
git clone https://github.com/danielbodnar/sessions.nu ~/.config/nushell/modules/sessions

# Add to your config.nu
echo 'use ~/.config/nushell/modules/sessions' >> ~/.config/nushell/config.nu
echo 'use ~/.config/nushell/modules/sessions *' >> ~/.config/nushell/config.nu
```

Or manually add to `~/.config/nushell/config.nu`:

```nushell
use ~/.config/nushell/modules/sessions      # Makes 'sessions' command available
use ~/.config/nushell/modules/sessions *    # Makes subcommands available
```

## Quick Start

### Shell History

```nushell
# View weekly time summary (uses current directory as pattern)
sessions weekly

# Pipe patterns directly
["myproject" "work-server"] | sessions weekly

# Use a config profile
sessions --profile work -g week

# Export to CSV
sessions -g week -f csv > timesheet.csv
```

### Browser History

```nushell
# View browser sessions (uses domains from config)
sessions browser

# Weekly browser report
sessions browser weekly

# Pipe domains directly
["github.com" "docs.example.com"] | sessions browser

# Specific browsers only
sessions browser --browsers ["chrome-canary" "firefox-dev"]
```

## Configuration

### Config File

Create `~/.config/sessions/config.nu`:

```nushell
{
    # Shell history patterns (match against cwd)
    patterns: ["myproject" "work" "192.168.1.100"]

    # Browser history domains (match against URLs)
    domains: [
        "github.com/myorg"
        "dash.cloudflare.com/account-id"
        "gitlab.com/username"
    ]

    # Preferred browsers (checked in order)
    browsers: [
        "chrome-canary"
        "chrome-unstable"
        "firefox-dev"
    ]

    # Shell session grace period
    grace_period: 60min

    # Browser session grace period (shorter since browsing is more continuous)
    browser_grace_period: 30min
}
```

Or use TOML (`config.toml`) or JSON (`config.json`).

### Named Profiles

Create project-specific configs:

```bash
# ~/.config/sessions/config-work.nu
{
    patterns: ["company-repo" "staging.example.com"]
    domains: ["jira.company.com" "github.com/company"]
    grace_period: 90min
}
```

Use with: `sessions --profile work`

### Initialize Config

```nushell
sessions init                  # Create default config
sessions init --profile work   # Create named profile
sessions config                # View current configuration
```

## Usage

### Pattern Resolution

Patterns are resolved in this order:
1. `--patterns` or `--domains` flag
2. Piped input (`["p1" "p2"] | sessions`)
3. Config file patterns/domains
4. Current directory name (shell only)

### Shell History Commands

```nushell
# All sessions (default grouping)
sessions

# Aggregate by time period
sessions daily
sessions weekly
sessions monthly

# Overall statistics
sessions summary

# Pattern analysis
sessions by-dow      # By day of week
sessions by-time     # By time of day
```

### Browser History Commands

```nushell
# All browser sessions
sessions browser

# Aggregate by time period
sessions browser daily
sessions browser weekly
sessions browser monthly

# Show discovered browser paths
sessions browser paths

# Limit to specific browsers
sessions browser --browsers ["chrome-canary"]
```

### Output Formats

```nushell
sessions weekly                    # Table (default)
sessions weekly -f csv             # CSV
sessions weekly -f json            # JSON
sessions weekly -f md              # Markdown
sessions weekly -f tsv             # Tab-separated
sessions weekly -f nuon            # Nushell Object Notation
```

### Filtering

```nushell
# By date range
sessions --start 2025-01-01 --end 2025-12-31

# By hours worked
sessions -g week --min-hours 20

# Combine filters
sessions -g day --start 2025-12-01 --min-hours 4 -f md
```

### Nested Data for Exploration

```nushell
# Get nested data for drill-down
sessions weekly --nested

# Explore interactively
sessions weekly --nested | explore

# Drill into specific week
sessions weekly --nested | last | get days | get sessions | flatten
```

### Nushell Pipeline Magic

All date fields are native `datetime` objects:

```nushell
# Filter weeks starting after a date
sessions -g week | where ($it.week_start > ("2025-12-01" | into datetime))

# Find long sessions
sessions | where ($it.duration > 3hr)

# Last 7 days
sessions | where ($it.date >= ((date now) - 7day))
```

## Supported Browsers

Browser history files are auto-discovered in priority order:

| Browser | Config Name | Type |
|---------|-------------|------|
| Google Chrome Canary | `chrome-canary` | Chromium |
| Google Chrome Unstable | `chrome-unstable` | Chromium |
| Firefox Developer Edition | `firefox-dev` | Firefox |
| Google Chrome | `chrome` | Chromium |
| Chromium | `chromium` | Chromium |
| Firefox | `firefox` | Firefox |

Use `sessions browser paths` to see which browsers are detected on your system.

## Output Fields

### Shell Sessions

| Field | Type | Description |
|-------|------|-------------|
| `date` | `datetime` | Session date |
| `start` | `datetime` | Session start time |
| `end` | `datetime` | Session end time |
| `duration` | `duration` | Total session length |
| `commands` | `int` | Number of commands |
| `primary_cwd` | `string` | Most-used directory |

### Browser Sessions

| Field | Type | Description |
|-------|------|-------------|
| `date` | `datetime` | Session date |
| `start` | `datetime` | Session start time |
| `end` | `datetime` | Session end time |
| `duration` | `duration` | Total session length |
| `page_views` | `int` | Number of page visits |
| `primary_domain` | `string` | Most-visited domain |
| `browsers` | `string` | Browsers used in session |

### Weekly/Monthly

| Field | Type | Description |
|-------|------|-------------|
| `week_start` | `datetime` | Start of week (Monday) |
| `week_end` | `datetime` | End of week (Sunday) |
| `hours` | `float` | Total hours worked |
| `days_active` | `int` | Days with activity |
| `session_count` | `int` | Number of sessions |

## How It Works

### Shell History
1. **Query atuin** — Searches your shell history database for commands matching patterns
2. **Group into sessions** — Commands within the grace period (default 60min) form one session
3. **Add grace time** — Each session gets grace time added (accounts for thinking/reading time)
4. **Aggregate** — Roll up into daily/weekly/monthly summaries

### Browser History
1. **Discover browsers** — Finds Chrome/Firefox history files on your system
2. **Query SQLite** — Searches visit history for URLs matching domain patterns
3. **Handle timestamps** — Converts Chrome (Windows epoch) and Firefox (Unix epoch) timestamps
4. **Group into sessions** — Visits within the grace period (default 30min) form one session
5. **Aggregate** — Roll up into daily/weekly/monthly summaries

## Examples

### Timesheet Report

```nushell
# Generate a weekly timesheet for the current month
sessions -g week --start (date now | format date "%Y-%m-01") -f md
```

### Project Comparison

```nushell
# Compare time across projects
["project-a"] | sessions summary | get total_hours  # => 45.5
["project-b"] | sessions summary | get total_hours  # => 32.2
```

### Combined Shell + Browser Analysis

```nushell
# How much time on Cloudflare this week?
sessions browser weekly | last | get hours  # Browser time
sessions weekly | last | get hours          # Shell time
```

### Export All Reports

```nushell
sessions export ~/timesheets --format csv
```

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Credits

Built with [Nushell](https://www.nushell.sh/) and powered by [atuin](https://atuin.sh/) shell history.

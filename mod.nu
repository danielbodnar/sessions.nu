# Sessions - Time tracking from shell history
#
# A Nushell module for analyzing work sessions from atuin shell history.
# Calculates time spent on projects by grouping commands into sessions
# based on time gaps, with configurable grace periods.
#
# # Installation
#
# Add to your config.nu:
# ```nushell
# use ~/.config/nushell/modules/sessions      # Makes 'sessions' command available
# use ~/.config/nushell/modules/sessions *    # Makes subcommands available
# ```
#
# # Configuration
#
# Create a config file at $XDG_CONFIG_HOME/sessions/config.nu:
# ```nushell
# {
#     patterns: ["myproject" "work" "192.168.1.100"]
#     grace_period: 60min
# }
# ```
#
# Or use config.toml or config.json format.
# Named profiles: config-work.nu, config-personal.nu, etc.
#
# # Usage
#
# ```nushell
# # Uses patterns from config, or current directory name
# sessions
#
# # Pipe patterns directly
# ["project1" "project2"] | sessions weekly
#
# # Use a named profile
# sessions --profile work
#
# # Override with explicit patterns
# sessions --patterns ["myproject"]
#
# # Aggregate reports
# sessions daily | to csv
# sessions weekly | to md
# sessions monthly | to nuon
# ```

export use utils.nu [
    DEFAULT_GRACE_PERIOD
    config-dir
]

use utils.nu *
use core.nu *
use reports.nu *

# Get all work sessions from shell history
#
# Queries atuin history for commands in matching directories,
# groups them into sessions based on time gaps, and returns
# structured session data with timing information.
#
# All date fields are native nushell datetime values for filtering.
#
# Pattern resolution priority:
# 1. --patterns flag (explicit)
# 2. Piped input (["pattern1" "pattern2"] | sessions)
# 3. Config file ($XDG_CONFIG_HOME/sessions/config.nu)
# 4. Current directory name
#
# # Examples
#
# ```nushell
# # Uses config patterns or current directory
# sessions
#
# # Pipe patterns
# ["myproject" "work"] | sessions weekly
#
# # Use a named profile
# sessions --profile work
#
# # Group by week, output as CSV
# sessions --group week --format csv
#
# # Filter by date range
# sessions --start 2026-01-01 --end 2026-01-31
# ```
export def main [
    --patterns (-p): list<string>       # Directory patterns to match
    --profile: string                   # Config profile name (loads config-{profile}.nu)
    --grace: duration                   # Max gap between commands in session
    --group (-g): string = "session"    # Group by: session, day, week, month
    --format (-f): string = "table"     # Output: table, csv, tsv, json, nuon, md
    --start (-s): string                # Start date filter (YYYY-MM-DD)
    --end (-e): string                  # End date filter (YYYY-MM-DD)
    --min-hours: float                  # Minimum hours filter
    --max-hours: float                  # Maximum hours filter
    --flat                              # Flatten nested data for exports
    --help (-h)                         # Show help
]: [nothing -> any, list<string> -> any] {
    # Capture piped input if present
    let piped = $in

    if $help {
        print "Sessions - Time tracking from shell history"
        print ""
        print "Usage: sessions [OPTIONS]"
        print "       <patterns> | sessions [OPTIONS]"
        print ""
        print "Pattern Resolution (in order of priority):"
        print "  1. --patterns flag"
        print "  2. Piped input: [\"proj1\" \"proj2\"] | sessions"
        print "  3. Config file: $XDG_CONFIG_HOME/sessions/config.nu"
        print "  4. Current directory name"
        print ""
        print "Options:"
        print "  -p, --patterns <list>    Directory patterns to match"
        print "  --profile <name>         Use named config profile (config-{name}.nu)"
        print "  --grace <duration>       Gap between sessions (default: 60min or from config)"
        print "  -g, --group <level>      Group by: session, day, week, month (default: session)"
        print "  -f, --format <format>    Output: table, csv, tsv, json, nuon, md (default: table)"
        print "  -s, --start <date>       Start date filter (YYYY-MM-DD)"
        print "  -e, --end <date>         End date filter (YYYY-MM-DD)"
        print "  --min-hours <float>      Minimum hours filter"
        print "  --max-hours <float>      Maximum hours filter"
        print "  --flat                   Flatten nested data for export formats"
        print "  -h, --help               Show this help"
        print ""
        print "Subcommands:"
        print "  sessions daily           Daily report (use --nested for drill-down)"
        print "  sessions weekly          Weekly report"
        print "  sessions monthly         Monthly report"
        print "  sessions summary         Overall statistics"
        print "  sessions by-dow          Breakdown by day of week"
        print "  sessions by-time         Breakdown by time of day"
        print "  sessions export <dir>    Export all reports"
        print "  sessions init            Create config directory and sample config"
        print ""
        print "Examples:"
        print "  sessions                                    # Auto-detect patterns"
        print "  [\"myproject\"] | sessions weekly            # Pipe patterns"
        print "  sessions --profile work -g week             # Use work profile"
        print "  sessions -g week -f csv                     # Weekly CSV"
        print "  sessions --start 2026-01-01 -f md           # Filter by date"
        return null
    }

    # Validate group option
    let valid_groups = ["session" "day" "week" "month"]
    if not ($group in $valid_groups) {
        error make {
            msg: $"Invalid group: ($group)"
            help: $"Valid groups: ($valid_groups | str join ', ')"
        }
    }

    # Validate format option
    let valid_formats = ["table" "csv" "tsv" "json" "nuon" "md"]
    if not ($format in $valid_formats) {
        error make {
            msg: $"Invalid format: ($format)"
            help: $"Valid formats: ($valid_formats | str join ', ')"
        }
    }

    # Resolve patterns from flag, stdin, config, or cwd
    let explicit = if $patterns != null { $patterns } else { [] }
    let piped_list = if $piped != null { $piped } else { [] }
    let resolved_patterns = (resolve-patterns $explicit $piped_list $profile)
    let resolved_grace = if $grace != null {
        resolve-grace-period $profile --explicit $grace
    } else {
        resolve-grace-period $profile
    }

    # Get data based on grouping
    let data = match $group {
        "session" => { core-sessions --patterns $resolved_patterns --grace-period $resolved_grace }
        "day" => { report-daily --patterns $resolved_patterns --grace-period $resolved_grace }
        "week" => { report-weekly --patterns $resolved_patterns --grace-period $resolved_grace }
        "month" => { report-monthly --patterns $resolved_patterns --grace-period $resolved_grace }
    }

    if ($data | is-empty) {
        return []
    }

    # Apply filters using closures for dynamic field access
    let after_start = if $start != null {
        let start_dt = ($start | into datetime)
        match $group {
            "session" => { $data | where {|r| $r.date >= $start_dt } }
            "day" => { $data | where {|r| $r.date >= $start_dt } }
            "week" => { $data | where {|r| $r.week_start >= $start_dt } }
            "month" => { $data | where {|r| $r.month >= $start_dt } }
        }
    } else {
        $data
    }

    let after_end = if $end != null {
        let end_dt = ($end | into datetime)
        match $group {
            "session" => { $after_start | where {|r| $r.date <= $end_dt } }
            "day" => { $after_start | where {|r| $r.date <= $end_dt } }
            "week" => { $after_start | where {|r| $r.week_start <= $end_dt } }
            "month" => { $after_start | where {|r| $r.month <= $end_dt } }
        }
    } else {
        $after_start
    }

    # For session-level data, compute hours from duration
    let after_min = if $min_hours != null {
        if $group == "session" {
            $after_end | where {|r| ($r.duration | format-hours) >= $min_hours }
        } else {
            $after_end | where {|r| $r.hours >= $min_hours }
        }
    } else {
        $after_end
    }

    let filtered = if $max_hours != null {
        if $group == "session" {
            $after_min | where {|r| ($r.duration | format-hours) <= $max_hours }
        } else {
            $after_min | where {|r| $r.hours <= $max_hours }
        }
    } else {
        $after_min
    }

    # Auto-flatten for formats that don't support nested data
    let needs_flat = $flat or ($format in ["csv" "tsv" "md"])

    # Flatten if requested or required by format
    let output_data = if $needs_flat {
        match $group {
            "session" => {
                $filtered | select date day_of_week start_time end_time duration commands directories primary_cwd
                | each { |r| {
                    date: ($r.date | format-date)
                    day_of_week: $r.day_of_week
                    start_time: $r.start_time
                    end_time: $r.end_time
                    hours: ($r.duration | format-hours)
                    commands: $r.commands
                    directories: $r.directories
                    primary_cwd: $r.primary_cwd
                }}
            }
            "day" => {
                $filtered | each { |r| {
                    date: ($r.date | format-date)
                    day_of_week: $r.day_of_week
                    hours: $r.hours
                    session_count: $r.session_count
                    commands: $r.commands
                }}
            }
            "week" => {
                $filtered | each { |r| {
                    week_start: ($r.week_start | format-date)
                    week_end: ($r.week_end | format-date)
                    hours: $r.hours
                    days_active: $r.days_active
                    session_count: $r.session_count
                    commands: $r.commands
                }}
            }
            "month" => {
                $filtered | each { |r| {
                    month: ($r.month | month-string)
                    hours: $r.hours
                    weeks_active: $r.weeks_active
                    days_active: $r.days_active
                    session_count: $r.session_count
                    commands: $r.commands
                }}
            }
        }
    } else {
        $filtered
    }

    # Format output
    match $format {
        "table" => { $output_data }
        "csv" => { $output_data | to csv }
        "tsv" => { $output_data | to tsv }
        "json" => { $output_data | to json }
        "nuon" => { $output_data | to nuon }
        "md" => { $output_data | to md }
    }
}

# Daily time tracking report
#
# Aggregates sessions by day with cumulative totals.
# Each day has exactly one row regardless of session count.
#
# # Examples
#
# ```nushell
# sessions daily                    # Flat table for display
# sessions daily --nested           # Nested data for drill-down
# sessions daily | where hours > 5
# sessions daily | last 7 | to md
# ```
export def "sessions daily" [
    --patterns (-p): list<string>
    --grace (-g): duration = 60min
    --nested (-n)                     # Return nested data for drill-down
]: nothing -> table {
    let data = (report-daily --patterns $patterns --grace-period $grace)

    if $nested {
        $data
    } else {
        $data | each { |r| {
            date: ($r.date | format-date)
            day_of_week: $r.day_of_week
            hours: $r.hours
            session_count: $r.session_count
            commands: $r.commands
        }}
    }
}

# Weekly time tracking report
#
# Aggregates sessions by week (Monday-Sunday).
#
# # Examples
#
# ```nushell
# sessions weekly                   # Flat table for display
# sessions weekly --nested          # Nested data for drill-down
# sessions weekly | where hours > 20
# sessions weekly --nested | last | get days | explore
# ```
export def "sessions weekly" [
    --patterns (-p): list<string>
    --grace (-g): duration = 60min
    --nested (-n)                     # Return nested data for drill-down
]: nothing -> table {
    let data = (report-weekly --patterns $patterns --grace-period $grace)

    if $nested {
        $data
    } else {
        $data | each { |r| {
            week_start: ($r.week_start | format-date)
            week_end: ($r.week_end | format-date)
            hours: $r.hours
            days_active: $r.days_active
            session_count: $r.session_count
            commands: $r.commands
        }}
    }
}

# Monthly time tracking report
#
# Aggregates sessions by month.
#
# # Examples
#
# ```nushell
# sessions monthly                  # Flat table for display
# sessions monthly --nested         # Nested data for drill-down
# sessions monthly --nested | last | get weeks | explore
# ```
export def "sessions monthly" [
    --patterns (-p): list<string>
    --grace (-g): duration = 60min
    --nested (-n)                     # Return nested data for drill-down
]: nothing -> table {
    let data = (report-monthly --patterns $patterns --grace-period $grace)

    if $nested {
        $data
    } else {
        $data | each { |r| {
            month: ($r.month | month-string)
            hours: $r.hours
            weeks_active: $r.weeks_active
            days_active: $r.days_active
            session_count: $r.session_count
            commands: $r.commands
        }}
    }
}

# Overall summary statistics
#
# Returns aggregate statistics across all sessions.
#
# # Examples
#
# ```nushell
# sessions summary
# sessions summary | to nuon
# sessions summary | get total_hours
# ```
export def "sessions summary" [
    --patterns (-p): list<string>
    --grace (-g): duration = 60min
]: nothing -> record {
    report-summary --patterns $patterns --grace-period $grace
}

# Breakdown by day of week
#
# Shows activity distribution across weekdays.
#
# # Examples
#
# ```nushell
# sessions by-dow | to md
# ```
export def "sessions by-dow" [
    --patterns (-p): list<string>
    --grace (-g): duration = 60min
]: nothing -> table<day: string, sessions: int, hours: float> {
    report-by-dow --patterns $patterns --grace-period $grace
}

# Breakdown by time of day
#
# Shows activity distribution across time periods.
#
# # Examples
#
# ```nushell
# sessions by-time | to md
# ```
export def "sessions by-time" [
    --patterns (-p): list<string>
    --grace (-g): duration = 60min
]: nothing -> table<period: string, sessions: int, hours: float> {
    report-by-time --patterns $patterns --grace-period $grace
}

# Export all reports to files
#
# Saves daily, weekly, monthly reports and summary to directory.
#
# # Examples
#
# ```nushell
# sessions export ~/reports
# sessions export . --format nuon
# ```
export def "sessions export" [
    output_dir: path = "."             # Directory to save reports
    --patterns (-p): list<string>
    --grace (-g): duration = 60min
    --format (-f): string = "csv"      # Output format: csv, tsv, nuon, json
]: nothing -> nothing {
    report-export $output_dir --patterns $patterns --grace-period $grace --format $format
}

# Initialize sessions configuration
#
# Creates config directory and sample config file.
#
# # Examples
#
# ```nushell
# sessions init                      # Create default config
# sessions init --profile work       # Create work profile
# ```
export def "sessions init" [
    --profile: string                 # Create named profile instead of default
]: nothing -> nothing {
    let dir = (config-dir)

    # Create config directory
    if not ($dir | path exists) {
        mkdir $dir
        print $"Created config directory: ($dir)"
    }

    let base = if $profile != null { $"config-($profile)" } else { "config" }
    let config_file = $"($dir)/($base).nu"

    if ($config_file | path exists) {
        print $"Config file already exists: ($config_file)"
        print "Edit it manually or delete it first."
        return
    }

    # Get current directory name as default pattern
    let cwd_name = ($env.PWD | path basename)

    let sample_config = $"# Sessions configuration
# Patterns to match against directory paths in shell history
{
    patterns: [
        \"($cwd_name)\"
        # Add more patterns here:
        # \"myproject\"
        # \"192.168.1.100\"
    ]
    grace_period: 60min
}
"

    $sample_config | save $config_file
    print $"Created config file: ($config_file)"
    print ""
    print "Edit the patterns list to match your project directories."
    print "You can use partial matches - 'myproject' matches '/path/to/myproject/src'"
}

# Show current configuration
#
# Displays resolved patterns and settings.
export def "sessions config" [
    --profile: string                 # Show named profile config
]: nothing -> record {
    let patterns = (resolve-patterns [] [] $profile)
    let grace = (resolve-grace-period $profile)
    let dir = (config-dir)

    {
        config_dir: $dir
        profile: (if $profile != null { $profile } else { "default" })
        patterns: $patterns
        grace_period: $grace
        config_exists: ($"($dir)/config.nu" | path exists)
    }
}

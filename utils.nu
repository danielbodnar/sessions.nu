# Utility functions for sessions module

# Default grace period between sessions
export const DEFAULT_GRACE_PERIOD = 60min

# Get config directory path
export def config-dir []: nothing -> path {
    let xdg = ($env.XDG_CONFIG_HOME? | default $"($env.HOME)/.config")
    $"($xdg)/sessions"
}

# Load patterns from config file
#
# Searches for config files in order:
# 1. $XDG_CONFIG_HOME/sessions/config.nu
# 2. $XDG_CONFIG_HOME/sessions/config.toml
# 3. $XDG_CONFIG_HOME/sessions/config.json
#
# Config file format (nu):
#   { patterns: ["project1" "project2"], grace_period: 60min }
#
# Config file format (toml):
#   patterns = ["project1", "project2"]
#   grace_period = "60min"
#
# Config file format (json):
#   {"patterns": ["project1", "project2"], "grace_period": "60min"}
export def load-config [
    profile?: string  # Optional profile name (loads config-{profile}.nu etc)
]: nothing -> record {
    let dir = (config-dir)
    let base = if $profile != null { $"config-($profile)" } else { "config" }

    let nu_file = $"($dir)/($base).nu"
    let toml_file = $"($dir)/($base).toml"
    let json_file = $"($dir)/($base).json"

    if ($nu_file | path exists) {
        # Nu files contain a record literal - evaluate it
        open $nu_file | from nuon
    } else if ($toml_file | path exists) {
        open $toml_file | from toml
    } else if ($json_file | path exists) {
        open $json_file | from json
    } else {
        # Return empty config - will use defaults
        {}
    }
}

# Get patterns from config, stdin, or default to cwd
#
# Priority:
# 1. Explicit --patterns flag (if provided)
# 2. Piped input (list of patterns)
# 3. Config file patterns
# 4. Current working directory name
export def resolve-patterns [
    explicit_patterns: list<string> = []  # Patterns from --patterns flag
    piped_patterns: list<string> = []     # Patterns from stdin
    profile?: string                      # Config profile name
]: nothing -> list<string> {
    # 1. Explicit --patterns flag takes priority
    if ($explicit_patterns | length) > 0 {
        return $explicit_patterns
    }

    # 2. Piped input
    if ($piped_patterns | length) > 0 {
        return $piped_patterns
    }

    # 3. Config file
    let config = (load-config $profile)
    let config_patterns = ($config.patterns? | default [])
    if ($config_patterns | length) > 0 {
        return $config_patterns
    }

    # 4. Default to current working directory name
    let cwd_name = ($env.PWD | path basename)
    [$cwd_name]
}

# Get grace period from config or default
export def resolve-grace-period [
    profile?: string           # Config profile name
    --explicit: duration       # Explicit grace period from --grace flag
]: nothing -> duration {
    if $explicit != null {
        return $explicit
    }

    let config = (load-config $profile)
    let config_grace = $config.grace_period?

    if $config_grace != null {
        if ($config_grace | describe) == "duration" {
            $config_grace
        } else {
            # Parse string like "60min" or "1hr"
            $config_grace | into duration
        }
    } else {
        $DEFAULT_GRACE_PERIOD
    }
}

# Build SQL WHERE clause for directory patterns
#
# # Examples
#
# ```nushell
# build-where-clause ["maybach" "systemavo"]
# # => "cwd LIKE '%maybach%' OR cwd LIKE '%systemavo%'"
# ```
export def build-where-clause [
    patterns: list<string>  # List of patterns to match in cwd
]: nothing -> string {
    $patterns
    | each { |p| $"cwd LIKE '%($p)%'" }
    | str join " OR "
}

# Calculate week boundaries from a date
#
# Returns the Monday (start) and Sunday (end) of the week containing the given date.
#
# # Examples
#
# ```nushell
# "2025-12-10" | into datetime | week-boundaries
# # => {start: 2025-12-08, end: 2025-12-14}
# ```
export def week-boundaries []: datetime -> record<start: datetime, end: datetime> {
    let dt = $in
    let dow = ($dt | format date "%u" | into int)  # 1=Monday, 7=Sunday
    let start = ($dt - (($dow - 1) * 1day))
    let end = ($start + 6day)
    { start: $start, end: $end }
}

# Format duration as human-readable hours
#
# # Examples
#
# ```nushell
# 2hr 30min | format-hours
# # => 2.5
# ```
export def format-hours []: duration -> float {
    ($in / 1hr) | math round --precision 2
}

# Format datetime as date string (for display/grouping keys)
#
# # Examples
#
# ```nushell
# date now | format-date
# # => "2025-12-10"
# ```
export def format-date []: datetime -> string {
    $in | format date "%Y-%m-%d"
}

# Convert datetime to date-only datetime (midnight)
#
# # Examples
#
# ```nushell
# date now | to-date
# # => 2025-12-10T00:00:00
# ```
export def to-date []: datetime -> datetime {
    $in | format date "%Y-%m-%d" | into datetime
}

# Convert week start string back to datetime
#
# # Examples
#
# ```nushell
# "2025-12-10" | date-from-string
# # => 2025-12-10T00:00:00
# ```
export def date-from-string []: string -> datetime {
    $in | into datetime
}

# Get first day of month as datetime
#
# # Examples
#
# ```nushell
# date now | month-start
# # => 2025-12-01T00:00:00
# ```
export def month-start []: datetime -> datetime {
    $in | format date "%Y-%m-01" | into datetime
}

# Format datetime as time string
#
# # Examples
#
# ```nushell
# date now | format-time
# # => "14:30"
# ```
export def format-time []: datetime -> string {
    $in | format date "%H:%M"
}

# Get day of week name
#
# # Examples
#
# ```nushell
# date now | day-name
# # => "Wednesday"
# ```
export def day-name []: datetime -> string {
    $in | format date "%A"
}

# Get ISO week string
#
# # Examples
#
# ```nushell
# date now | iso-week
# # => "2025-W50"
# ```
export def iso-week []: datetime -> string {
    $in | format date "%Y-W%W"
}

# Get month string
#
# # Examples
#
# ```nushell
# date now | month-string
# # => "2025-12"
# ```
export def month-string []: datetime -> string {
    $in | format date "%Y-%m"
}

# Truncate path for display
#
# # Examples
#
# ```nushell
# "/very/long/path/to/somewhere" | truncate-path 20
# # => ".../path/to/somewhere"
# ```
export def truncate-path [
    max_len: int = 50  # Maximum length
]: string -> string {
    let path = $in
    if ($path | str length) > $max_len {
        let start = (($path | str length) - $max_len + 3)
        $"...($path | str substring $start..)"
    } else {
        $path
    }
}

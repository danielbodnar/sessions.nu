# Browser history functions for sessions module
#
# Parses browser history from Firefox and Chrome-based browsers to track
# time spent on specific domains. Supports:
# - Google Chrome Canary
# - Google Chrome Unstable
# - Firefox Developer Edition
# - Standard Chrome/Firefox/Chromium

use utils.nu *

# Chrome epoch offset: Chrome uses microseconds since 1601-01-01
# Unix epoch (1970-01-01) in Chrome time = 11644473600 seconds
const CHROME_EPOCH_OFFSET = 11644473600000000  # microseconds

# Known browser paths (priority order based on user preference)
export const BROWSER_CONFIGS = [
    {
        name: "chrome-canary"
        type: "chrome"
        paths: [
            "~/.config/google-chrome-canary/Default/History"
            "~/.config/google-chrome-canary/Profile 1/History"
            "~/.config/google-chrome-canary/Profile 2/History"
        ]
    }
    {
        name: "chrome-unstable"
        type: "chrome"
        paths: [
            "~/.config/google-chrome-unstable/Default/History"
            "~/.config/google-chrome-unstable/Profile 1/History"
        ]
    }
    {
        name: "firefox-dev"
        type: "firefox"
        paths: [
            "~/.mozilla/firefox/*.dev-edition-default/places.sqlite"
            "~/.mozilla/firefox/*.dev-edition-default-backup/places.sqlite"
        ]
    }
    {
        name: "chrome"
        type: "chrome"
        paths: [
            "~/.config/google-chrome/Default/History"
            "~/.config/google-chrome/Profile 1/History"
        ]
    }
    {
        name: "chromium"
        type: "chrome"
        paths: [
            "~/.config/chromium/Default/History"
        ]
    }
    {
        name: "firefox"
        type: "firefox"
        paths: [
            "~/.mozilla/firefox/*.default-release/places.sqlite"
            "~/.mozilla/firefox/*.default/places.sqlite"
        ]
    }
]

# Discover browser history files using plocate or glob
#
# # Examples
#
# ```nushell
# discover-browser-paths
# # => [{browser: "chrome-canary", type: "chrome", path: "/home/user/.config/google-chrome-canary/Default/History"}, ...]
# ```
export def discover-browser-paths [
    --browsers: list<string> = []  # Limit to specific browsers
]: nothing -> table<browser: string, type: string, path: string> {
    let search_configs = if ($browsers | is-empty) {
        $BROWSER_CONFIGS
    } else {
        $BROWSER_CONFIGS | where { |c| $c.name in $browsers }
    }

    mut found = []

    for config in $search_configs {
        for path_pattern in $config.paths {
            # Expand ~ to home directory
            let expanded = ($path_pattern | str replace "~" $env.HOME)

            # Check if it's a glob pattern
            if ($expanded | str contains "*") {
                # Use glob to find matching files
                let matches = (glob $expanded --no-dir | default [])
                for match in $matches {
                    if ($match | path exists) {
                        $found = ($found | append {
                            browser: $config.name
                            type: $config.type
                            path: ($match | into string)
                        })
                    }
                }
            } else {
                # Direct path check
                if ($expanded | path exists) {
                    $found = ($found | append {
                        browser: $config.name
                        type: $config.type
                        path: $expanded
                    })
                }
            }
        }
    }

    # Remove duplicates and return
    $found | uniq
}

# Convert Chrome timestamp to Unix datetime
#
# Chrome uses microseconds since 1601-01-01
# Formula: (chrome_time - 11644473600000000) / 1000000 = unix_timestamp
#
# # Examples
#
# ```nushell
# 13412711255360797 | chrome-to-datetime
# # => 2025-06-15T12:00:00
# ```
export def chrome-to-datetime []: int -> datetime {
    let chrome_time = $in
    let unix_microseconds = $chrome_time - $CHROME_EPOCH_OFFSET
    # Convert microseconds to nanoseconds for duration, then to datetime
    ($unix_microseconds * 1µs) + (0 | into datetime)
}

# Convert Firefox timestamp to Unix datetime
#
# Firefox uses microseconds since Unix epoch
#
# # Examples
#
# ```nushell
# 1763588531293000 | firefox-to-datetime
# # => 2025-11-19T12:00:00
# ```
export def firefox-to-datetime []: int -> datetime {
    let firefox_time = $in
    # Convert microseconds to nanoseconds for duration, then to datetime
    ($firefox_time * 1µs) + (0 | into datetime)
}

# Build SQL WHERE clause for URL/domain patterns
#
# # Examples
#
# ```nushell
# build-url-where-clause ["maybachsystems.com" "gitlab.com/davidbodnar"]
# # => "u.url LIKE '%maybachsystems.com%' OR u.url LIKE '%gitlab.com/davidbodnar%'"
# ```
export def build-url-where-clause [
    domains: list<string>  # Domain patterns to match
]: nothing -> string {
    $domains
    | each { |d| $"u.url LIKE '%($d)%'" }
    | str join " OR "
}

# Copy Chrome database to temp file for reading
#
# Chrome locks its database while running, so we copy it first.
# Returns the temp file path.
export def copy-chrome-db [
    path: path
]: nothing -> path {
    let temp_file = $"/tmp/sessions_chrome_($path | path basename | str replace '.db' '')_($nu.pid).db"
    cp $path $temp_file
    $temp_file
}

# Query Chrome history for matching domains
#
# # Examples
#
# ```nushell
# get-chrome-entries "/path/to/History" --domains ["maybachsystems.com"]
# ```
export def get-chrome-entries [
    db_path: path
    --domains (-d): list<string>
]: nothing -> table {
    if ($domains | is-empty) {
        error make { msg: "No domains specified for browser history query" }
    }

    let where_clause = (build-url-where-clause $domains)

    # Copy database to avoid lock issues
    let temp_db = (copy-chrome-db $db_path)

    let raw = try {
        open $temp_db
        | query db $"
            SELECT
                v.visit_time,
                v.visit_duration,
                u.url,
                u.title
            FROM visits v
            JOIN urls u ON v.url = u.id
            WHERE \(($where_clause)\)
            AND v.visit_time > 0
            ORDER BY v.visit_time
        "
    } catch { |e|
        rm -f $temp_db
        error make { msg: $"Failed to query Chrome database: ($e.msg)" }
    }

    # Clean up temp file
    rm -f $temp_db

    if ($raw | is-empty) {
        return []
    }

    $raw | each { |row|
        let dt = ($row.visit_time | chrome-to-datetime)
        let dur = if $row.visit_duration > 0 {
            $row.visit_duration * 1µs
        } else {
            0sec
        }
        {
            timestamp: $dt
            duration: $dur
            url: $row.url
            title: ($row.title | default "")
            domain: ($row.url | url parse | get host | default "unknown")
            date: ($dt | format-date)
            week: ($dt | iso-week)
            month: ($dt | month-string)
            day_of_week: ($dt | day-name)
            time: ($dt | format-time)
            source: "chrome"
        }
    }
}

# Build SQL WHERE clause for Firefox URL/domain patterns
#
# Uses 'p.' prefix for moz_places table
export def build-firefox-url-where-clause [
    domains: list<string>  # Domain patterns to match
]: nothing -> string {
    $domains
    | each { |d| $"p.url LIKE '%($d)%'" }
    | str join " OR "
}

# Query Firefox history for matching domains
#
# # Examples
#
# ```nushell
# get-firefox-entries "/path/to/places.sqlite" --domains ["maybachsystems.com"]
# ```
export def get-firefox-entries [
    db_path: path
    --domains (-d): list<string>
]: nothing -> table {
    if ($domains | is-empty) {
        error make { msg: "No domains specified for browser history query" }
    }

    let where_clause = (build-firefox-url-where-clause $domains)

    let raw = try {
        open $db_path
        | query db $"
            SELECT
                v.visit_date,
                p.url,
                p.title
            FROM moz_historyvisits v
            JOIN moz_places p ON v.place_id = p.id
            WHERE \(($where_clause)\)
            AND v.visit_date > 0
            ORDER BY v.visit_date
        "
    } catch { |e|
        error make { msg: $"Failed to query Firefox database: ($e.msg)" }
    }

    if ($raw | is-empty) {
        return []
    }

    $raw | each { |row|
        let dt = ($row.visit_date | firefox-to-datetime)
        {
            timestamp: $dt
            duration: 0sec  # Firefox doesn't track visit duration
            url: $row.url
            title: ($row.title | default "")
            domain: ($row.url | url parse | get host | default "unknown")
            date: ($dt | format-date)
            week: ($dt | iso-week)
            month: ($dt | month-string)
            day_of_week: ($dt | day-name)
            time: ($dt | format-time)
            source: "firefox"
        }
    }
}

# Get all browser history entries from all discovered browsers
#
# # Examples
#
# ```nushell
# get-all-browser-entries --domains ["maybachsystems.com" "gitlab.com"]
# get-all-browser-entries --domains ["cloudflare.com"] --browsers ["chrome-canary"]
# ```
export def get-all-browser-entries [
    --domains (-d): list<string>
    --browsers (-b): list<string> = []  # Limit to specific browsers
]: nothing -> table {
    let browser_paths = (discover-browser-paths --browsers $browsers)

    if ($browser_paths | is-empty) {
        error make {
            msg: "No browser history files found"
            help: "Checked paths for Chrome Canary, Chrome Unstable, Firefox Dev Edition, and others"
        }
    }

    mut all_entries = []

    for bp in $browser_paths {
        let entries = match $bp.type {
            "chrome" => {
                try {
                    get-chrome-entries $bp.path --domains $domains
                    | each { |e| { ...$e, browser: $bp.browser } }
                } catch { [] }
            }
            "firefox" => {
                try {
                    get-firefox-entries $bp.path --domains $domains
                    | each { |e| { ...$e, browser: $bp.browser } }
                } catch { [] }
            }
        }
        $all_entries = ($all_entries | append $entries)
    }

    if ($all_entries | is-empty) {
        return []
    }

    # Sort by timestamp and deduplicate similar visits
    $all_entries | sort-by timestamp | uniq-by timestamp url
}

# Build browser sessions from visit entries
#
# Groups consecutive page visits into browsing sessions based on time gaps.
# Similar to shell session building but for browser history.
#
# # Examples
#
# ```nushell
# get-all-browser-entries --domains ["maybachsystems.com"] | build-browser-sessions
# ```
export def build-browser-sessions [
    --grace-period (-g): duration = 30min  # Shorter grace for browser sessions
]: table -> table {
    let entries = $in
    let grace_ns = ($grace_period | into int)

    if ($entries | is-empty) {
        return []
    }

    mut sessions = []
    mut sess_start: datetime = ($entries | first | get timestamp)
    mut sess_last: datetime = $sess_start
    mut sess_visits = []
    mut sess_urls = []
    mut sess_domains = []

    for entry in $entries {
        let ts = $entry.timestamp
        let gap = (($ts | into int) - ($sess_last | into int))

        if $gap <= $grace_ns {
            $sess_last = $ts
            $sess_visits = ($sess_visits | append $entry)
            $sess_urls = ($sess_urls | append $entry.url)
            $sess_domains = ($sess_domains | append $entry.domain)
        } else {
            # Finalize previous session
            if ($sess_visits | length) > 0 {
                let dur = (($sess_last | into int) - ($sess_start | into int) + ($grace_period | into int) | into duration --unit ns)
                let primary = ($sess_domains | uniq --count | sort-by count --reverse | first | get value)
                let week_bounds = ($sess_start | week-boundaries)
                let browsers_used = ($sess_visits | get browser | uniq | str join ", ")

                $sessions = ($sessions | append {
                    start: $sess_start
                    end: $sess_last
                    duration: $dur
                    page_views: ($sess_visits | length)
                    unique_urls: ($sess_urls | uniq | length)
                    unique_domains: ($sess_domains | uniq | length)
                    primary_domain: $primary
                    browsers: $browsers_used
                    date: ($sess_start | to-date)
                    week_start: ($week_bounds.start | to-date)
                    week_end: ($week_bounds.end | to-date)
                    month: ($sess_start | month-start)
                    day_of_week: ($sess_start | day-name)
                    start_time: ($sess_start | format-time)
                    end_time: ($sess_last | format-time)
                    source: "browser"
                })
            }

            # Start new session
            $sess_start = $ts
            $sess_last = $ts
            $sess_visits = [$entry]
            $sess_urls = [$entry.url]
            $sess_domains = [$entry.domain]
        }
    }

    # Last session
    if ($sess_visits | length) > 0 {
        let dur = (($sess_last | into int) - ($sess_start | into int) + ($grace_period | into int) | into duration --unit ns)
        let primary = ($sess_domains | uniq --count | sort-by count --reverse | first | get value)
        let week_bounds = ($sess_start | week-boundaries)
        let browsers_used = ($sess_visits | get browser | uniq | str join ", ")

        $sessions = ($sessions | append {
            start: $sess_start
            end: $sess_last
            duration: $dur
            page_views: ($sess_visits | length)
            unique_urls: ($sess_urls | uniq | length)
            unique_domains: ($sess_domains | uniq | length)
            primary_domain: $primary
            browsers: $browsers_used
            date: ($sess_start | to-date)
            week_start: ($week_bounds.start | to-date)
            week_end: ($week_bounds.end | to-date)
            month: ($sess_start | month-start)
            day_of_week: ($sess_start | day-name)
            start_time: ($sess_start | format-time)
            end_time: ($sess_last | format-time)
            source: "browser"
        })
    }

    $sessions
}

# Get browser sessions (main entry point)
#
# # Examples
#
# ```nushell
# core-browser-sessions --domains ["maybachsystems.com" "gitlab.com"]
# core-browser-sessions --domains ["cloudflare.com"] --browsers ["chrome-canary"]
# ```
export def core-browser-sessions [
    --domains (-d): list<string>
    --browsers (-b): list<string> = []
    --grace-period (-g): duration = 30min
]: nothing -> table {
    try {
        get-all-browser-entries --domains $domains --browsers $browsers
        | build-browser-sessions --grace-period $grace_period
    } catch { |e|
        error make {
            msg: "Failed to retrieve browser sessions"
            help: $e.msg
        }
    }
}

# Browser daily report
export def browser-report-daily [
    --domains (-d): list<string>
    --browsers (-b): list<string> = []
    --grace-period (-g): duration = 30min
]: nothing -> table {
    let s = (core-browser-sessions --domains $domains --browsers $browsers --grace-period $grace_period)

    if ($s | is-empty) {
        return []
    }

    $s
    | each { |r| { ...$r, date_key: ($r.date | format-date) } }
    | group-by date_key
    | transpose date_key day_sessions
    | each { |d|
        let total_dur = ($d.day_sessions | get duration | math sum)
        let first_sess = ($d.day_sessions | first)
        {
            date: $first_sess.date
            day_of_week: $first_sess.day_of_week
            hours: ($total_dur | format-hours)
            duration: $total_dur
            session_count: ($d.day_sessions | length)
            page_views: ($d.day_sessions | get page_views | math sum)
            sessions: ($d.day_sessions | reject date_key)
        }
    }
    | sort-by date
}

# Browser weekly report
export def browser-report-weekly [
    --domains (-d): list<string>
    --browsers (-b): list<string> = []
    --grace-period (-g): duration = 30min
]: nothing -> table {
    let daily = (browser-report-daily --domains $domains --browsers $browsers --grace-period $grace_period)

    if ($daily | is-empty) {
        return []
    }

    let with_week = ($daily | each { |day|
        let week_bounds = ($day.date | week-boundaries)
        {
            ...$day
            week_start: ($week_bounds.start | to-date)
            week_end: ($week_bounds.end | to-date)
            week_key: ($week_bounds.start | format-date)
        }
    })

    $with_week
    | group-by week_key
    | transpose week_key week_days
    | each { |w|
        let total_dur = ($w.week_days | get duration | math sum)
        let all_sessions = ($w.week_days | get sessions | flatten)
        let first_day = ($w.week_days | first)
        {
            week_start: $first_day.week_start
            week_end: $first_day.week_end
            hours: ($total_dur | format-hours)
            duration: $total_dur
            days_active: ($w.week_days | length)
            session_count: ($all_sessions | length)
            page_views: ($w.week_days | get page_views | math sum)
            days: ($w.week_days | reject week_start week_end week_key)
        }
    }
    | sort-by week_start
}

# Browser monthly report
export def browser-report-monthly [
    --domains (-d): list<string>
    --browsers (-b): list<string> = []
    --grace-period (-g): duration = 30min
]: nothing -> table {
    let weekly = (browser-report-weekly --domains $domains --browsers $browsers --grace-period $grace_period)

    if ($weekly | is-empty) {
        return []
    }

    let with_month = ($weekly | each { |week|
        let month_dt = ($week.week_start | month-start)
        let month_key = ($week.week_start | month-string)
        { ...$week, month: $month_dt, month_key: $month_key }
    })

    $with_month
    | group-by month_key
    | transpose month_key month_weeks
    | each { |m|
        let total_dur = ($m.month_weeks | get duration | math sum)
        let all_days = ($m.month_weeks | get days | flatten)
        let all_sessions = ($all_days | get sessions | flatten)
        let first_week = ($m.month_weeks | first)
        {
            month: $first_week.month
            hours: ($total_dur | format-hours)
            duration: $total_dur
            weeks_active: ($m.month_weeks | length)
            days_active: ($all_days | length)
            session_count: ($all_sessions | length)
            page_views: ($m.month_weeks | get page_views | math sum)
            weeks: ($m.month_weeks | reject month month_key)
        }
    }
    | sort-by month
}

# Reporting functions for sessions module

use utils.nu *
use core.nu [core-sessions]

# Daily time tracking with nested sessions
#
# Returns days with all sessions nested inside for drilling down.
#
# # Examples
#
# ```nushell
# sessions daily | explore
# sessions daily | where ($it.hours > 5) | get sessions | flatten
# sessions daily | last | get sessions
# ```
export def report-daily [
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
]: nothing -> table {
    let s = (core-sessions --patterns $patterns --grace-period $grace_period)

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
            commands: ($d.day_sessions | get commands | math sum)
            sessions: ($d.day_sessions | reject date_key)
        }
    }
    | sort-by date
}

# Weekly time tracking with nested days and sessions
#
# Returns weeks containing days containing sessions for full drill-down.
#
# # Examples
#
# ```nushell
# sessions weekly | explore
# sessions weekly | last | get days | get sessions | flatten
# sessions weekly | where ($it.hours > 20) | get days
# ```
export def report-weekly [
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
]: nothing -> table {
    let daily = (report-daily --patterns $patterns --grace-period $grace_period)

    if ($daily | is-empty) {
        return []
    }

    # Add week info to each day (datetime values)
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
            commands: ($w.week_days | get commands | math sum)
            days: ($w.week_days | reject week_start week_end week_key)
        }
    }
    | sort-by week_start
}

# Monthly time tracking with nested weeks, days, and sessions
#
# Returns months containing weeks containing days containing sessions.
#
# # Examples
#
# ```nushell
# sessions monthly | explore
# sessions monthly | last | get weeks | get days | flatten | get sessions | flatten
# ```
export def report-monthly [
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
]: nothing -> table {
    let weekly = (report-weekly --patterns $patterns --grace-period $grace_period)

    if ($weekly | is-empty) {
        return []
    }

    # Add month to each week (based on week_start) - datetime value
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
            commands: ($m.month_weeks | get commands | math sum)
            weeks: ($m.month_weeks | reject month month_key)
        }
    }
    | sort-by month
}

# Overall summary with all nested data
#
# Returns full summary with access to all underlying data.
#
# # Examples
#
# ```nushell
# sessions summary | get months | explore
# sessions summary | get all_sessions | where ($it.duration > 3hr)
# ```
export def report-summary [
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
]: nothing -> record {
    let s = (core-sessions --patterns $patterns --grace-period $grace_period)
    let monthly = (report-monthly --patterns $patterns --grace-period $grace_period)

    if ($s | is-empty) {
        return {
            total_hours: 0.0
            total_duration: 0ns
            total_sessions: 0
            total_commands: 0
            months_active: 0
            weeks_active: 0
            days_active: 0
            avg_hours_per_day: 0.0
            avg_session_hours: 0.0
            avg_commands_per_session: 0
            first_date: null
            last_date: null
            months: []
            all_sessions: []
        }
    }

    let total_dur = ($s | get duration | math sum)
    let total_hours = ($total_dur | format-hours)
    let total_sessions = ($s | length)
    let total_commands = ($s | get commands | math sum)
    let all_days = ($monthly | get weeks | flatten | get days | flatten)
    let total_days = ($all_days | length)
    let total_weeks = ($monthly | get weeks | flatten | length)

    {
        total_hours: $total_hours
        total_duration: $total_dur
        total_sessions: $total_sessions
        total_commands: $total_commands
        months_active: ($monthly | length)
        weeks_active: $total_weeks
        days_active: $total_days
        avg_hours_per_day: (if $total_days > 0 { $total_hours / $total_days | math round --precision 2 } else { 0.0 })
        avg_session_hours: (if $total_sessions > 0 { $total_hours / $total_sessions | math round --precision 2 } else { 0.0 })
        avg_commands_per_session: (if $total_sessions > 0 { $total_commands / $total_sessions | math round --precision 0 | into int } else { 0 })
        first_date: ($s | first | get date)
        last_date: ($s | last | get date)
        months: $monthly
        all_sessions: $s
    }
}

# By day of week with nested sessions
#
# Groups all sessions by day of week for pattern analysis.
#
# # Examples
#
# ```nushell
# sessions by-dow | explore
# sessions by-dow | where day == "Wednesday" | get sessions | flatten
# ```
export def report-by-dow [
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
]: nothing -> table {
    let s = (core-sessions --patterns $patterns --grace-period $grace_period)

    if ($s | is-empty) {
        return []
    }

    $s
    | group-by day_of_week
    | transpose day dow_sessions
    | each { |r|
        let total_dur = ($r.dow_sessions | get duration | math sum)
        {
            day: $r.day
            hours: ($total_dur | format-hours)
            duration: $total_dur
            session_count: ($r.dow_sessions | length)
            commands: ($r.dow_sessions | get commands | math sum)
            sessions: $r.dow_sessions
        }
    }
    | sort-by hours --reverse
}

# By time of day with nested sessions
#
# Groups sessions by time period for work pattern analysis.
#
# # Examples
#
# ```nushell
# sessions by-time | explore
# sessions by-time | where period == "18-24 Evening" | get sessions | flatten
# ```
export def report-by-time [
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
]: nothing -> table {
    let s = (core-sessions --patterns $patterns --grace-period $grace_period)

    if ($s | is-empty) {
        return []
    }

    $s
    | each { |sess|
        let hour = ($sess.start_time | split row ":" | first | into int)
        let period = if $hour < 6 {
            "00-06 Night"
        } else if $hour < 12 {
            "06-12 Morning"
        } else if $hour < 18 {
            "12-18 Afternoon"
        } else {
            "18-24 Evening"
        }
        { ...$sess, period: $period }
    }
    | group-by period
    | transpose period period_sessions
    | each { |r|
        let total_dur = ($r.period_sessions | get duration | math sum)
        {
            period: $r.period
            hours: ($total_dur | format-hours)
            duration: $total_dur
            session_count: ($r.period_sessions | length)
            commands: ($r.period_sessions | get commands | math sum)
            sessions: ($r.period_sessions | reject period)
        }
    }
    | sort-by period
}

# Export all reports to files
#
# Saves reports in flat format suitable for spreadsheets/external tools.
# For nested exploration, use the commands directly in nushell.
export def report-export [
    output_dir: path = "."
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
    --format (-f): string = "csv"
]: nothing -> nothing {
    let valid_formats = ["csv" "tsv" "nuon" "json"]
    if not ($format in $valid_formats) {
        error make {
            msg: $"Invalid format: ($format)"
            help: $"Valid formats: ($valid_formats | str join ', ')"
        }
    }

    let s = (core-sessions --patterns $patterns --grace-period $grace_period)
    let d = (report-daily --patterns $patterns --grace-period $grace_period)
    let w = (report-weekly --patterns $patterns --grace-period $grace_period)
    let m = (report-monthly --patterns $patterns --grace-period $grace_period)
    let sum = (report-summary --patterns $patterns --grace-period $grace_period)

    mkdir $output_dir

    # Flatten for export (nested data doesn't export well to CSV)
    # Convert datetime to string for CSV compatibility
    let sessions_flat = ($s
        | select date day_of_week start_time end_time duration commands directories primary_cwd
        | each { |r| {
            date: ($r.date | format-date)
            day_of_week: $r.day_of_week
            start_time: $r.start_time
            end_time: $r.end_time
            hours: ($r.duration | format-hours)
            commands: $r.commands
            directories: $r.directories
            primary_cwd: $r.primary_cwd
        } }
    )

    let daily_flat = ($d | each { |r| {
        date: ($r.date | format-date)
        day_of_week: $r.day_of_week
        hours: $r.hours
        session_count: $r.session_count
        commands: $r.commands
    } })

    let weekly_flat = ($w | each { |r| {
        week_start: ($r.week_start | format-date)
        week_end: ($r.week_end | format-date)
        hours: $r.hours
        days_active: $r.days_active
        session_count: $r.session_count
        commands: $r.commands
    } })

    let monthly_flat = ($m | each { |r| {
        month: ($r.month | month-string)
        hours: $r.hours
        weeks_active: $r.weeks_active
        days_active: $r.days_active
        session_count: $r.session_count
        commands: $r.commands
    } })

    let summary_flat = {
        total_hours: $sum.total_hours
        total_sessions: $sum.total_sessions
        total_commands: $sum.total_commands
        days_active: $sum.days_active
        weeks_active: $sum.weeks_active
        months_active: $sum.months_active
        first_date: $sum.first_date
        last_date: $sum.last_date
    }

    let save_data = { |data, name|
        let file = ($output_dir | path join $"($name).($format)")
        match $format {
            "csv" => { $data | to csv | save -f $file }
            "tsv" => { $data | to tsv | save -f $file }
            "nuon" => { $data | to nuon | save -f $file }
            "json" => { $data | to json | save -f $file }
        }
    }

    do $save_data $sessions_flat "sessions"
    do $save_data $daily_flat "daily"
    do $save_data $weekly_flat "weekly"
    do $save_data $monthly_flat "monthly"
    do $save_data $summary_flat "summary"

    # Also save full nested data as nuon for nushell users
    if $format != "nuon" {
        $sum | to nuon | save -f ($output_dir | path join "full-data.nuon")
    }

    print $"✓ Reports exported to ($output_dir)/"
    print $"  - sessions.($format) \(flat\)"
    print $"  - daily.($format) \(flat\)"
    print $"  - weekly.($format) \(flat\)"
    print $"  - monthly.($format) \(flat\)"
    print $"  - summary.($format) \(flat\)"
    if $format != "nuon" {
        print $"  - full-data.nuon \(nested, for nushell\)"
    }
}

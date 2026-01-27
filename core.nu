# Core data functions for sessions module

use utils.nu *

# Get raw command entries from atuin history
#
# Queries the atuin SQLite database for commands matching the specified
# directory patterns. Returns entries with proper datetime types.
#
# # Examples
#
# ```nushell
# get-entries --patterns ["myproject"]
# ```
export def get-entries [
    --patterns (-p): list<string>  # Directory patterns to match (required)
]: nothing -> table {
    if ($patterns | is-empty) {
        error make {
            msg: "No patterns specified"
            help: "Provide patterns via --patterns flag, stdin, or config file"
        }
    }

    let where_clause = (build-where-clause $patterns)

    let raw = (
        open ~/.local/share/atuin/history.db
        | query db $"
            SELECT timestamp, duration, command, cwd
            FROM history
            WHERE \(($where_clause)\)
            AND deleted_at IS NULL
            AND timestamp > 0
            ORDER BY timestamp
        "
    )

    if ($raw | is-empty) {
        error make {
            msg: "No matching entries found"
            label: {
                text: "Check patterns match directories in your history"
                span: (metadata $patterns).span
            }
            help: $"Patterns searched: ($patterns | str join ', ')"
        }
    }

    $raw | each { |row|
        let dt = ($row.timestamp | into datetime)
        let dur = ($row.duration | into int | into duration --unit ns)
        {
            timestamp: $dt
            duration: $dur
            command: $row.command
            cwd: $row.cwd
            date: ($dt | format-date)
            week: ($dt | iso-week)
            month: ($dt | month-string)
            day_of_week: ($dt | day-name)
            time: ($dt | format-time)
        }
    }
}

# Build work sessions from command entries
#
# Groups commands into sessions based on time gaps.
#
# # Examples
#
# ```nushell
# get-entries | build-sessions
# get-entries | build-sessions --grace-period 45min
# ```
export def build-sessions [
    --grace-period (-g): duration = 60min
]: table -> table {
    let entries = $in
    let grace_ns = ($grace_period | into int)

    if ($entries | is-empty) {
        return []
    }

    mut sessions = []
    mut sess_start: datetime = ($entries | first | get timestamp)
    mut sess_last: datetime = $sess_start
    mut sess_cmds = []
    mut sess_cwds = []

    for entry in $entries {
        let ts = $entry.timestamp
        let gap = (($ts | into int) - ($sess_last | into int))

        if $gap <= $grace_ns {
            $sess_last = $ts
            $sess_cmds = ($sess_cmds | append $entry.command)
            $sess_cwds = ($sess_cwds | append $entry.cwd)
        } else {
            let dur = (($sess_last | into int) - ($sess_start | into int) + $grace_ns | into duration --unit ns)
            let primary = ($sess_cwds | uniq --count | sort-by count --reverse | first | get value)
            let week_bounds = ($sess_start | week-boundaries)

            $sessions = ($sessions | append {
                start: $sess_start
                end: $sess_last
                duration: $dur
                commands: ($sess_cmds | length)
                directories: ($sess_cwds | uniq | length)
                primary_cwd: $primary
                date: ($sess_start | to-date)
                week_start: ($week_bounds.start | to-date)
                week_end: ($week_bounds.end | to-date)
                month: ($sess_start | month-start)
                day_of_week: ($sess_start | day-name)
                start_time: ($sess_start | format-time)
                end_time: ($sess_last | format-time)
            })

            $sess_start = $ts
            $sess_last = $ts
            $sess_cmds = [$entry.command]
            $sess_cwds = [$entry.cwd]
        }
    }

    # Last session
    if ($sess_cmds | length) > 0 {
        let dur = (($sess_last | into int) - ($sess_start | into int) + $grace_ns | into duration --unit ns)
        let primary = ($sess_cwds | uniq --count | sort-by count --reverse | first | get value)
        let week_bounds = ($sess_start | week-boundaries)

        $sessions = ($sessions | append {
            start: $sess_start
            end: $sess_last
            duration: $dur
            commands: ($sess_cmds | length)
            directories: ($sess_cwds | uniq | length)
            primary_cwd: $primary
            date: ($sess_start | to-date)
            week_start: ($week_bounds.start | to-date)
            week_end: ($week_bounds.end | to-date)
            month: ($sess_start | month-start)
            day_of_week: ($sess_start | day-name)
            start_time: ($sess_start | format-time)
            end_time: ($sess_last | format-time)
        })
    }

    $sessions
}

# Get all work sessions (internal implementation)
#
# Called by the public `sessions` command.
export def core-sessions [
    --patterns (-p): list<string>
    --grace-period (-g): duration = 60min
]: nothing -> table {
    try {
        get-entries --patterns $patterns | build-sessions --grace-period $grace_period
    } catch { |e|
        error make {
            msg: "Failed to retrieve sessions"
            label: {
                text: $e.msg
                span: (metadata $patterns).span
            }
        }
    }
}

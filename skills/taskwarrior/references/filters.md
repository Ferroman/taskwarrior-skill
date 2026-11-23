# Taskwarrior filter & expression reference

Filters select which tasks a command operates on. They appear *before* the
subcommand: `task <filter> <command>`. The same grammar is used for reports,
modifications, and counts.

## Table of contents
- [Attribute equality](#attribute-equality)
- [Attribute modifiers](#attribute-modifiers)
- [Tags and virtual tags](#tags-and-virtual-tags)
- [Dates and durations](#dates-and-durations)
- [Boolean logic and grouping](#boolean-logic-and-grouping)
- [IDs, UUIDs, and ranges](#ids-uuids-and-ranges)
- [Full-text search](#full-text-search)
- [Common recipes](#common-recipes)

## Attribute equality

`name:value` matches tasks where the attribute equals (or, for strings, starts
with / contains depending on the attribute) the value.

```bash
project:home          # project is "home" or a subproject "home.x"
priority:H            # H, M, L  (empty means "no priority")
status:pending        # pending|completed|deleted|waiting|recurring
description:milk      # description contains "milk"
```

Empty test: a trailing colon with no value means "is empty".

```bash
project:              # tasks with no project
due:                  # tasks with no due date
```

## Attribute modifiers

Append `.<modifier>` to an attribute for richer comparisons. These are the most
useful:

| Modifier | Meaning | Example |
|----------|---------|---------|
| `.is` / `.not` | exact equal / not equal | `project.is:home` |
| `.has` / `.hasnt` | substring present / absent | `description.has:invoice` |
| `.startswith` / `.endswith` | prefix / suffix | `project.startswith:work` |
| `.before` / `.after` | date comparison | `due.before:eom` |
| `.over` / `.under` | numeric/priority comparison | `priority.over:M`, `urgency.over:10` |
| `.any` / `.none` | attribute set / unset | `due.any:`, `due.none:` |
| `.word` / `.noword` | whole-word match | `description.word:bug` |

```bash
task due.after:today due.before:eom list      # due this month
task priority.over:L list                      # priority M or H
task urgency.over:15 export                     # high-urgency tasks
```

## Tags and virtual tags

Stored tags: `+name` (has tag), `-name` (lacks tag).

```bash
task +work +urgent list      # has both
task +work -blocked list     # has work, not blocked
```

**Virtual tags** are computed on the fly (never stored, can't be added with
`modify`). The important ones:

| Tag | Meaning |
|-----|---------|
| `+PENDING` `+COMPLETED` `+DELETED` `+WAITING` | status |
| `+OVERDUE` | due date is in the past |
| `+DUE` | due within `rc.due` days (default 7) |
| `+TODAY` `+DUETODAY` | due today |
| `+ACTIVE` | currently started (time tracking on) |
| `+BLOCKED` `+UNBLOCKED` | has / hasn't unmet dependencies |
| `+BLOCKING` | something else depends on it |
| `+TAGGED` | has at least one tag |
| `+ANNOTATED` | has annotations |
| `+SCHEDULED` `+UNTIL` `+WAITING` | corresponding date attrs set |

```bash
task +OVERDUE export | jq length
task +ACTIVE list                 # what am I working on right now
task +BLOCKED list                # stuck tasks
```

## Dates and durations

Date attributes: `due`, `scheduled`, `wait`, `until`, `entry`, `end`,
`start`, `modified`.

**Named dates:** `now`, `today`, `yesterday`, `tomorrow`, `sod`/`eod` (start/end
of day), `sow`/`eow` (week), `som`/`eom` (month), `soy`/`eoy` (year),
weekday names (`monday`…`sunday` → next occurrence), `later`/`someday`
(far future).

**ISO:** `2026-07-01`, `2026-07-01T14:30`.

**Arithmetic** with durations: `today+3d`, `eow-1d`, `now+2h`, `due+1wk`.

**Duration units:** `s` `min` `h` `d` `wk`/`week` `mo`/`month` `y`/`year`
(also `2days`, `3weeks`, `1hour` spellings).

```bash
task due.before:today+7d list     # next week
task 'wait:now+1mo' add ...         # snooze
task entry.after:today-1wk list    # created in the last 7 days
```

## Boolean logic and grouping

This is the area where it's easiest to silently get **zero results**. Taskwarrior
parses the filter from the *separate command-line argument tokens*, so how you
quote matters enormously.

### Rule 1 — one term per argument; never quote the whole filter

Collapsing a multi-term filter into a single quoted string makes Taskwarrior fail
to parse the operators and match **nothing** (no error, just an empty result):

```bash
# WRONG — returns 0, silently
task 'status:pending and project:home' export        # -> []
scripts/tw-export.sh '(project:work or project:home) and +urgent'   # -> []

# RIGHT — each term and operator is its own token
task status:pending and project:home export
scripts/tw-export.sh '(' project:work or project:home ')' +urgent
```

Quote only an *individual* term that contains shell-special characters (spaces,
`*`, `<`, `>`). Pass `(`, `)`, `and`, `or` as their own bare tokens.

### Rule 2 — prefer juxtaposition (implicit AND)

A space between terms already means AND, and it's the most reliable form. Reach
for explicit `and`/`or` only when you genuinely need OR.

```bash
task status:pending +work -blocked due.before:eom export   # all ANDed
```

### Rule 3 — avoid the `not` operator; use `-tag` / `.not:` / `.none:`

The `not` operator is unreliable across builds (it can return wrong counts).
Express negation with the dependable modifier forms instead:

| Instead of | Use |
|------------|-----|
| `not +work` | `-work` |
| `not project:home` | `project.not:home` |
| `not priority:H` | `priority.not:H` |
| "has no due date" | `due.none:` |
| "has a due date" | `due.any:` |

### Rule 4 — parenthesize OR groups (precedence binds AND tighter)

Without parens, `status:pending project:home or project:war` parses as
`(status:pending AND project:home) OR project:war` — pulling in every `project:war`
task regardless of status. Wrap the alternation:

```bash
task status:pending '(' project:home or project:war ')' export   # status AND (home OR war)
```

### Comparison operators

`<`, `<=`, `=`, `!=`, `>`, `>=`, `~` (contains), `!~` (not contains) work as
separate tokens, but the attribute-modifier forms (`urgency.over:`,
`priority.not:`, `description.has:`) are usually cleaner and avoid shell-quoting
the `<`/`>`:

```bash
task status:pending urgency.over:10 priority.not:L export   # preferred
task status:pending urgency '>' 10 export                    # operator form (quote the >)
```

## IDs, UUIDs, and ranges

```bash
task 42 info                 # single id
task 42,57,99 list           # id list
task 10-20 list              # id range
task a1b2c3d4 modify ...     # uuid prefix (>=8 chars recommended)
```

Remember ids renumber as tasks complete — use uuids for anything that spans
multiple commands.

## Full-text search

```bash
task /pattern/ list          # regex/substring over description+annotations
task rc.search.case.sensitive=no /Invoice/ export
```

## Common recipes

These use the `scripts/tw-export.sh` helper (valid-JSON export, context
neutralized) — see SKILL.md rule 3.

Note the token separation (Rule 1 above): operators and parens are their own
arguments, never folded into one quoted string.

```bash
# Everything actionable right now, urgency-sorted, parseable
scripts/tw-export.sh status:pending -BLOCKED '(' wait.none: or wait.before:now ')' \
  | jq -r 'sort_by(-.urgency)[] | "\(.urgency|floor)\t\(.description)"'

# Stale tasks: pending, no due, untouched for 30+ days
scripts/tw-export.sh status:pending due.none: modified.before:today-30d

# This week's completions (for a standup/report)
scripts/tw-export.sh status:completed end.after:sow \
  | jq -r '.[] | "- \(.description)"'

# Tasks with a specific UDA value (an example `effort` UDA; see config-and-udas.md)
scripts/tw-export.sh effort:D | jq -r '.[].description'
```

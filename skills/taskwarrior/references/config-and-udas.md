# Taskwarrior configuration, contexts, recurrence & UDAs

Anything in this file edits or reads `.taskrc` / TaskChampion state that affects
*every future command*. Inspect before you change: `task show <pattern>` to view
current values, `task _get rc.<key>` to read one value as plain text (ideal for
scripting), and only then `task config <key> <value>` to write.

## Reading config safely

```bash
task show                       # full effective config (long)
task show context               # only keys matching "context"
task show uda                   # all UDA definitions
task _get rc.data.location      # one value, no decoration -> ~/.task
task _get rc.due                # the +DUE window in days
```

`task _get` is the agent-friendly accessor — no table, no prompt, exit code
reflects success. Use it whenever you need a config value as a string.

## Writing config

```bash
task config <key> <value>           # prompts unless rc.confirmation=off
task rc.confirmation=off config rc.due 14
task config <key>                   # (no value) removes the key, also prompts
```

Because a bad edit is global, confirm the key name with `task show <pattern>`
first rather than guessing. Comments and unknown keys are tolerated but typos
silently do nothing useful.

## Contexts

A context is a named, saved filter applied automatically to commands. Users who
rely on contexts notice when one changes under them, so be deliberate:

```bash
task context show               # which context is active and its definition
task context list               # all defined contexts
task context work               # activate "work" (CHANGES GLOBAL STATE)
task context none               # deactivate (CHANGES GLOBAL STATE)
```

A context has separate `read` and `write` filters:
- The **read** filter scopes report commands (`list`/`next`/`count`/custom
  reports). Note `task export` does **not** apply it (seen on 3.4 and 3.5) — export
  always dumps everything.
- The **write** filter means `task add` inside a context auto-applies attributes
  (e.g. a context with write filter `+work` tags every new task `+work`).

**Agent guidance:** to get an unfiltered report or avoid auto-tagging on add, pass
`rc.context=none` on that single command instead of toggling the global context.
Toggling (`task context work` / `none`) is a stateful change the user will
notice later — only do it when they explicitly ask to switch contexts.

```bash
# Define a context (read filter, then optionally a write filter).
# NOTE: a stored filter IS a single quoted string here — Taskwarrior re-lexes it
# internally. This is the OPPOSITE of command-line filters, where a multi-term
# expression must be separate argument tokens (see filters.md, "Boolean logic").
task context define home 'project:home or project:family'
task context define home --write '+home'
```

## Recurring tasks

```bash
task add "Pay rent" due:som recur:monthly until:2027-01-01
task add "Standup" due:tomorrow recur:weekdays
```

`recur:` accepts `daily`, `weekly`, `monthly`, `quarterly`, `yearly`,
`weekdays`, or a duration like `3d` / `2wk`. A `due:` is required. The visible
task is a child instance; the hidden parent (`status:recurring`) spawns new ones.
Delete the parent to stop the series:

```bash
task rc.context=none status:recurring export | jq -r '.[] | "\(.uuid) \(.description)"'
task rc.confirmation=off <parent-uuid> delete
```

## Custom reports

Reports are config keys `report.<name>.*`. To inspect or clone one:

```bash
task show report.next               # see how the built-in "next" is built
task config report.today.columns id,project,due,description
task config report.today.labels ID,Proj,Due,Desc
task config report.today.filter 'status:pending and +TODAY'
task config report.today.sort due+
task today                          # run it
```

## User-Defined Attributes (UDAs)

UDAs are custom fields stored on tasks. Define with four-ish keys:

```bash
task config uda.<name>.type    string|numeric|date|duration
task config uda.<name>.label   "Human Label"
task config uda.<name>.values  "comma,separated,allowed,values"   # optional enum
task config uda.<name>.default "value"                             # optional
```

Once defined, a UDA behaves like any attribute in filters and modifications
(`effort` and `est` here are example UDAs):

```bash
task add "Deep work" effort:D est:4.0
scripts/tw-export.sh effort:D | jq -r '.[].description'
task a1b2c3d4 modify est:8.0
```

### Gotcha: numeric UDAs holding duration values break JSON export

A UDA declared `numeric` can still end up holding duration strings (`2d`, `15m`,
`1h`), typically an estimate field. `task export` then emits a **bare,
invalid-JSON** token — `{"est":2d}` — and `jq` fails with "Invalid numeric
literal". `scripts/tw-export.sh` quotes every such token after export
(`{"est":"2d"}`), whichever UDA it is in, without changing anything on disk, so
prefer it for all reads.

The alternative, for a single known UDA, is to override its type for one
command: `task rc.uda.est.type=duration export`. To find which UDA is the
culprit:

```bash
task rc.context=none export | grep -oE '"[a-z]+":[0-9][0-9.]*[a-zµ]+' | sort | uniq -c
```

### Discovering the user's UDAs

Every installation has its own. List them before you filter or write on one:

```bash
task _udas                                   # names, one per line
for u in $(task _udas); do printf '%s\t%s\n' "$u" "$(task _get rc.uda.$u.type)"; done
task show uda.<name>                         # label, values, default
```

Some UDAs belong to a sync tool (bugwarrior, a Jira or Linear bridge, …) and
usually share a prefix such as `jira*`, `github*` or `linear*`. Read them for
context (a ticket URL or status), but don't hand-edit them: the next sync
overwrites the change, and pushing changes back belongs to that tool. If the
user's instructions describe their UDAs, trust those over guessing from names.

## Hooks

Hooks are executables in `$rc.data.location/hooks/` (or `~/.task/hooks/`) named
`on-add`, `on-modify`, `on-launch`, `on-exit`. They receive task JSON on stdin
and must echo it back (possibly modified). Inspect existing hooks before adding
one, since a failing `on-add`/`on-modify` hook blocks the operation:

```bash
ls -la "$(task _get rc.data.location)/hooks" 2>/dev/null
```

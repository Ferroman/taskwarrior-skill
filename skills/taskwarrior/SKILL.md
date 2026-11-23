---
name: taskwarrior
description: >-
  Use whenever the user wants to interact with their Taskwarrior task list via
  the `task` CLI — reading, querying, summarizing, adding, modifying, completing,
  starting/stopping, or annotating tasks, building filter expressions, working
  with projects/tags/priorities/due dates, or configuring contexts, recurrence,
  reports, and UDAs. Trigger on phrases like "what's on my task list", "add a
  task", "mark X done", "what's overdue", "show my work tasks", "tasks due this
  week", "annotate", "taskwarrior", "task warrior", or any mention of `task add`
  / `task modify` / TaskChampion. Prefer this skill over raw `task` commands,
  because Taskwarrior has sharp edges (active contexts silently filter results,
  interactive prompts block automation, short ids renumber, and export can emit
  invalid JSON) that this skill handles correctly. Also use this skill when the
  agent keeps the plan for its own multi-step work in Taskwarrior instead of an
  ephemeral todo list, a markdown checklist or an issue tracker: writing the
  steps as tasks, recording context in annotations, and resuming a plan that a
  long or dropped session left behind — see the "Self-tracking" section.
---

# Taskwarrior

Drive Taskwarrior 3.x (TaskChampion backend) through the `task` CLI to read and
modify the user's tasks reliably and non-interactively.

## The four rules that prevent silent mistakes

Taskwarrior is built for a human at a terminal. As an agent you hit traps that a
human wouldn't. Internalize these before running anything:

1. **An active context silently scopes report and write commands.** If the user
   has a context active (check with `task context show`), it applies a hidden
   filter. The behavior differs by command, and the differences are easy to get
   wrong:
   - **Report commands honor it** — `task list`, `task next`, `task count`, and
     custom reports only show tasks matching the context's *read* filter. So
     `task count` can report 193 when the user actually has 245 pending. When you
     need a true, unfiltered answer, pass `rc.context=none`.
   - **`task export` ignores it** — export dumps all tasks regardless of context.
     (The bundled helper still passes `rc.context=none` defensively; it's a no-op
     for export but makes intent explicit.)
   - **`task add` applies the context's *write* filter** — inside a context whose
     write filter is `+work`, every new task is silently tagged `+work`. Check
     `task context show` before adding if the user expects a clean task.

   Neutralize per-command with `rc.context=none`. Leave the user's active context
   untouched — don't run `task context none`, which changes their global state.

2. **Interactive prompts hang automation.** Bulk modifications (a filter that
   matches >1 task), deletions, and some config changes prompt for `(yes/no)`.
   A non-interactive shell either hangs or auto-answers "no". Disable prompting
   per-command with `rc.confirmation=off` (and `rc.bulk=0` to suppress the
   "modify N tasks" gate). Only do this once you've confirmed your filter
   matches what you intend — see "Modifying tasks" below.

3. **Short ids are not stable.** The numbers in `task list` renumber whenever
   tasks complete or get deleted, including between two of your own commands, so
   `task 502 done` can hit an unrelated task. Use a numeric id only right after
   you read it in the same step; for anything you act on later, use the uuid
   (the first 8 characters are enough).

4. **Table output is lossy, and raw `task export` can emit invalid JSON.**
   Reports truncate text and omit fields, so parse JSON for anything
   programmatic. But `task export` itself has a trap: a UDA declared `numeric`
   that holds duration values (an estimate field with `2d` or `15m`) is emitted
   as a bare token `{"est":2d}` — invalid JSON that makes `jq` fail. **Always
   read through the bundled helper**, which neutralizes the context and quotes
   those tokens, whichever UDA they are in:

   ```bash
   scripts/tw-export.sh <filter> | jq '<query>'
   ```

   Use it instead of calling `task export` directly. Reserve human reports
   (`task list`, `task next`) for showing the user formatted output. (Root cause
   is documented in the script's header and in `references/config-and-udas.md`.)

## Reading tasks

Read through the helper (`scripts/tw-export.sh`) + `jq`. It wraps
`task ... export` with `rc.context=none` and the JSON fix from rule 4, so its
output is always a valid JSON array. Paths below are relative to this skill
directory.

**Examples**

```bash
# Every pending task, id + description + project, as a table for the user
scripts/tw-export.sh status:pending \
  | jq -r '.[] | "\(.id)\t\(.project // "-")\t\(.description)"'

# Overdue tasks (virtual tag +OVERDUE)
scripts/tw-export.sh +OVERDUE | jq -r '.[].description'

# Count pending tasks per project
scripts/tw-export.sh status:pending \
  | jq -r 'group_by(.project)[] | "\(length)\t\(.[0].project // "none")"'

# Tasks due in the next 7 days
scripts/tw-export.sh 'due.before:today+7d' status:pending | jq length
```

Two things about the JSON trip up analysis scripts:

- An unfiltered export includes `deleted` and `completed` tasks. Filter by
  `status:` unless you really want history.
- Dates are compact UTC (`20260701T143000Z`), not ISO 8601, so jq's
  `fromdateiso8601` rejects them; use `strptime("%Y%m%dT%H%M%SZ")`. Optional
  fields such as `due` and `wait` are absent, not `null`, when unset.

When the user just wants to *see* their list, it's fine to show a native report
(respecting their context, since that's usually what they mean):

```bash
task next            # urgency-sorted upcoming work, honors active context
task overdue         # built-in overdue report
task project:home list
```

Decide by intent: "show me my tasks" → native report; "how many / which tasks
match X so I can act on them" → `export` + `jq`.

## Adding tasks

```bash
task add <description> [attributes...]
```

Attributes are `name:value` pairs and `+tag`. Put the description first or it
gets parsed as attributes. Quote the whole description if it contains colons or
shell metacharacters.

```bash
task add "Review PR #42" project:work +urgent due:tomorrow priority:H
task add "Call dentist" due:friday scheduled:thursday
task add "Buy milk" +errand
```

`task add` prints the new id. To capture the uuid for later reference:

```bash
uuid=$(task add "New task" project:home rc.verbose=new-uuid | grep -oE '[0-9a-f-]{36}')
```

Date values accept ISO (`2026-07-01`), synonyms (`today`, `tomorrow`, `eom`,
`monday`, `friday`), and arithmetic (`today+3d`, `eow-1d`). See
`references/filters.md` for the full duration/date vocabulary.

## Modifying tasks

The pattern is `task <filter> <subcommand>`. **The filter selects, the
subcommand acts.** Getting the filter wrong is how you accidentally edit the
wrong tasks, so prefer a uuid, and verify scope first.

```bash
# Safe workflow: confirm what the filter matches BEFORE mutating
scripts/tw-export.sh <filter> | jq -r '.[] | "\(.uuid[0:8]) \(.description)"'
# ...looks right? then act:
task rc.confirmation=off rc.bulk=0 <filter> modify <changes>
```

Common mutations (shown with a uuid prefix; see rule 3):

```bash
task a1b2c3d4 done                              # complete
task a1b2c3d4 start                             # begin time tracking
task a1b2c3d4 stop
task a1b2c3d4 modify priority:H due:friday      # change attributes
task a1b2c3d4 modify project:work +review       # add tag
task a1b2c3d4 modify -review                    # remove tag
task a1b2c3d4 modify /old text/new text/        # substitute in description
task a1b2c3d4 annotate "called, left voicemail" # attach a dated note
task a1b2c3d4 denotate "called, left voicemail"
task rc.confirmation=off a1b2c3d4 delete        # delete (prompts otherwise)
```

## Filters, projects, tags, priorities

A quick reference for the most common filters; the full grammar (attribute
modifiers like `.before`/`.is`/`.has`, virtual tags, boolean logic, parentheses)
lives in `references/filters.md` — **read it before writing any filter that uses
`or` or negation**, because Taskwarrior has two traps that silently return zero
results (see below).

```bash
project:work            # exact project (also matches work.subproject)
+work -blocked          # has +work tag, lacks +blocked
priority:H              # high priority (H/M/L)
priority.not:H          # NOT high (prefer this over the `not` operator)
status:pending          # pending | completed | deleted | waiting | recurring
due.before:eom          # attribute modifier
due.none:  due.any:     # "has no due date" / "has a due date"
+OVERDUE +DUE +ACTIVE   # virtual tags (computed, not stored)
```

**Two filter traps (seen on 3.4 and 3.5):**

- **Don't wrap a multi-term filter in one quoted string** — Taskwarrior won't
  parse the operators and matches nothing. Pass each term, operator, and paren as
  its own argument: `task status:pending '(' project:a or project:b ')' export`,
  not `task 'status:pending and (project:a or project:b)' export`.
- **Avoid the `not` operator** (unreliable across builds); negate with `-tag`,
  `attr.not:value`, or `attr.none:` instead.

## Self-tracking: Taskwarrior as the agent's plan

When the user asks for it (for example in their `CLAUDE.md` or `AGENTS.md`),
keep the plan for your multi-step work in Taskwarrior, not in an ephemeral todo
list, a markdown checklist or an issue tracker. Each step is a task, the order
is task dependencies, and what you learn on the way is annotations on the task
it belongs to. The plan then outlives the session: when a long session runs out
of context or a session dies, the next one reads the plan back and carries on
from the step that was in progress. The user follows the same plan with their
normal `task` tooling.

The conventions below keep your tasks cleanly separated from the user's real
ones.

**Namespacing (non-negotiable — this is what keeps your tasks out of their way):**

- Tag every task `+agent`, and put it under `project:agent.<repo>`, where
  `<repo>` is the current working directory's base name without leading dots
  (e.g. `agent.myapp`). If the user's instructions name a different tag and
  project prefix (say `+claude` and `project:claude.<repo>`), use theirs.
- The separate project prefix means none of the user's contexts (`+work`,
  `project:home`, …) surface your tasks in their daily views, but they can see
  them anytime with `task project:agent list` or `task +agent list`.
- Always add/modify with `rc.context=none` so the user's active context can't
  inject its write-filter tags into your task or hide it from you.

**Lifecycle:**

```bash
# 1. Before you start, write the plan: one task per step. Capture each uuid
#    (ids renumber), and make a step depend on the step it needs first.
s1=$(task rc.context=none rc.verbose=new-uuid \
  add "Add retry to the sync client" project:agent.myapp +agent | grep -oE '[0-9a-f-]{36}')
s2=$(task rc.context=none rc.verbose=new-uuid \
  add "Test retry against a flaky server" project:agent.myapp +agent depends:${s1:0:8} \
  | grep -oE '[0-9a-f-]{36}')

# 2. Mark the step you're actively working on — this lets the user run
#    `task +ACTIVE` to see exactly what you're doing right now.
task rc.context=none rc.confirmation=off <uuid8> start

# 3. Annotate as you go: decisions, files touched, commands that worked,
#    blockers. The annotation is what the next session reads to continue.
task rc.context=none rc.confirmation=off <uuid8> annotate "retry 3x with backoff; change is in src/sync.py"
task rc.context=none rc.confirmation=off <uuid8> annotate "blocked on missing API token"

# 4. Complete it when the step is genuinely done (tests pass / verified).
task rc.context=none rc.confirmation=off <uuid8> stop
task rc.context=none rc.confirmation=off <uuid8> done
```

If the user gives you a plan (a list, a spec, a ticket), turn it into tasks the
same way and work from the tasks, not from the original text. Add a step you
discover on the way as a new task, rather than holding it in your head.

**Resuming (start of a session, or after context was compacted):**

Before you write a new plan, check whether one is already there:

```bash
# The step that was in progress, with its notes
scripts/tw-export.sh project:agent.myapp +ACTIVE \
  | jq -r '.[] | "\(.uuid[0:8]) \(.description)", (.annotations[]?.description | "  - " + .)'

# The whole open plan, in the order it was written
scripts/tw-export.sh project:agent.myapp status:pending \
  | jq -r 'sort_by(.entry)[] | "\(.uuid[0:8]) \(.description)\(if .depends then " (has dependencies)" else "" end)"'

# Steps that can start now (pending, not blocked by an open dependency)
scripts/tw-export.sh project:agent.myapp +READY | jq -r '.[] | "\(.uuid[0:8]) \(.description)"'
```

Read the annotations of the active step before you continue it, and check the
work it describes (the files, the branch) instead of trusting the note alone: a
session can die after the work and before the annotation. If the open plan
belongs to a different piece of work from what the user now asks for, ask
before you continue it or add to it.

**Judgment, not bookkeeping for its own sake:**

- Only track *substantive multi-step work* — the same threshold you'd use for an
  internal todo list. Don't create a task for a one-line answer or a single edit;
  that just litters the user's completed history.
- One task per meaningful step, not per shell command.
- Mark `done` only when the step is actually finished and verified, not when you
  start it. A truthful task list is the whole point.
- To review or clean up your own tasks later:
  `task rc.context=none project:agent.myapp list`, and
  `task rc.context=none rc.confirmation=off project:agent.myapp +COMPLETED delete`
  to prune.

## Configuration, contexts, recurrence, UDAs

For anything touching `.taskrc` — defining contexts, recurring tasks, custom
reports, colors, or User-Defined Attributes — read
`references/config-and-udas.md`. It covers `task config`, `task show`, reading
single values with `task _get rc.<key>`, and how to discover the user's own
UDAs (including ones a sync tool owns). Don't guess at config keys — confirm
with `task show <pattern>` first, because a wrong `.taskrc` edit affects every
future command.

## Quick reference card

```bash
task context show                                   # is a context filtering me?
scripts/tw-export.sh <filter> | jq ...              # read everything, valid JSON
task add "desc" project:P +tag due:DATE priority:H  # create
task rc.confirmation=off rc.bulk=0 <f> modify ...   # bulk-safe mutate
task <uuid8> done | start | stop | annotate "note"  # lifecycle
task _get rc.<key>                                  # read one config value
```

# taskwarrior

A [Claude Code](https://claude.com/claude-code) skill for working with
[Taskwarrior](https://taskwarrior.org/) 3.x through the `task` CLI.

The goal is to give an agent a plan that outlives the session. The agent keeps
the steps of its work as tasks in Taskwarrior, with the context of each step in
the task's annotations. When a long session runs out of context or a session
dies, the next session reads the plan back and continues from the step that was
in progress.

## The problem

An agent working on something that takes more than one session needs its plan
somewhere. The usual places each fail in a different way:

- **The session's own todo list** exists only inside that session. You cannot
  see it from a terminal, and when the session ends or its context is
  compacted, the next session starts from nothing.
- **A markdown plan file** survives, but every status change is an edit of the
  file. Nothing answers "which step was in progress?" or "what can start now?"
  without the agent reading and parsing the whole file again, and the notes for
  every step pile up in the same document.
- **GitHub issues or Jira** survive and can be queried, but every update is an
  authenticated network call through an API or a CLI. The agent's working steps
  also land in a tracker the rest of the team reads.

## Why Taskwarrior

Taskwarrior is local, and each update is one fast command. It already has what
a plan needs:

| A plan needs | Taskwarrior has |
|---|---|
| Steps | One task per step, under a project of its own |
| Order | `depends:`, and the `+READY` virtual tag for the steps that can start now |
| The step in progress | `task start`, and the `+ACTIVE` virtual tag |
| Context for a step | Annotations: decisions, files touched, commands that worked, blockers |
| A record of what is finished | `done`, only when the step is verified |
| A view for you | Your normal `task` reports and tools |

## How the agent uses it

The skill's "Self-tracking" section tells the agent to:

- **Plan.** Write one task per step before starting, with a dependency where a
  step needs another one first. A plan you give it (a list, a spec, a ticket)
  becomes tasks in the same way, and the agent works from the tasks.
- **Work.** Start the step it is on, annotate what it learns, and mark the step
  done only when the work is verified. A step it discovers on the way becomes a
  new task.
- **Resume.** At the start of a session, read the active step with its
  annotations, the open plan and the `+READY` steps, and check the work the
  notes describe before it continues.

The tasks carry their own tag and project (`+agent`, `project:agent.<repo>`),
so they do not appear in your own reports and contexts. You can name a
different tag in your `CLAUDE.md`.

## What makes it reliable

Taskwarrior is built for a person at a terminal. A person sees the "Context
'work' set" note under a report, answers the `(yes/no)` prompt, and reads the id
off the screen just before using it. An agent does none of that, so plain
`task` commands give it wrong results without an error. A wrong read looks
plausible: on Taskwarrior 3.5.0, the same filter counted 17 tasks when each
term was a separate argument and 0 when the whole filter was one quoted string.
A wrong write lands in your real task list.

| Trap | What goes wrong | What the skill does |
|---|---|---|
| Active context | `task count` says 193 when 245 tasks are pending; `task add` quietly tags the new task with the context's write filter. | Passes `rc.context=none` per command and never changes the user's context. |
| Prompts | Bulk edits and deletes wait for `(yes/no)`, so a non-interactive shell hangs or answers "no". | Verifies what a filter matches first, then runs with `rc.confirmation=off rc.bulk=0`. |
| Short ids | Ids renumber between two commands, so `task 502 done` can complete a different task. | Acts on uuid prefixes. |
| Export JSON | A numeric UDA that holds `2d` is exported as `{"est":2d}`, and `jq` fails. | Reads through `scripts/tw-export.sh`, which quotes those values. |
| Filter quoting | `task 'status:pending and (project:a or project:b)'` matches nothing. | Passes each term, operator and paren as its own argument. |

The same rules make the skill useful for your own task list too: reading,
adding and changing tasks, filters, dates, contexts, recurrence, custom
reports, UDAs and hooks.

## Install

As a plugin, from this repository:

```
/plugin install taskwarrior --marketplace Ferroman/taskwarrior-skill
```

On Claude Code older than 2.1.275, add the marketplace first:

```
/plugin marketplace add Ferroman/taskwarrior-skill
/plugin install taskwarrior
```

Or copy the skill directly:

```bash
git clone https://github.com/Ferroman/taskwarrior-skill
cp -r taskwarrior-skill/skills/taskwarrior ~/.claude/skills/
```

The skill loads whenever you ask about your tasks; you do not need to name it.
It needs `task` 3.x, `jq` and `sed`.

To have the agent keep its plan in Taskwarrior, ask for it in your
`CLAUDE.md`, for example:

```markdown
Keep the plan for multi-step work in Taskwarrior: follow the taskwarrior
skill's "Self-tracking" section, tag tasks +claude and file them under
project:claude.<repo>. At the start of a session, check for an open plan there
before you write a new one.
```

If you describe your own UDAs there too (say, which ones a sync tool owns), the
skill uses that instead of guessing from the names.

## The export helper

```bash
skills/taskwarrior/scripts/tw-export.sh status:pending +OVERDUE | jq length
```

It runs `task rc.context=none ... export` and quotes any value that begins with
a digit and goes on with letters (`2d`, `15min`, `1.5h`), in any field. Numbers,
strings and the task database are left as they are. The exit status is that of
`task`.

## Layout

```
skills/taskwarrior/
├── SKILL.md                     the rules, reading, adding, modifying, the agent's plan
├── references/
│   ├── filters.md               filter grammar, dates, boolean logic and its traps
│   └── config-and-udas.md       config, contexts, recurrence, reports, UDAs, hooks
└── scripts/tw-export.sh         export that always produces valid JSON
tests/tw-export.test.sh          tests for the helper, against a fake `task`
```

## Tests

```bash
bash tests/tw-export.test.sh
```

## Status

Version 0.1.0, used daily against Taskwarrior 3.5 with several thousand tasks.

## Licence

MIT.

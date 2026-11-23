# taskwarrior

A [Claude Code](https://claude.com/claude-code) skill for working with
[Taskwarrior](https://taskwarrior.org/) 3.x through the `task` CLI.

Taskwarrior is built for a person at a terminal. An agent driving it gets wrong
answers without any error:

| Trap | What goes wrong | What the skill does |
|---|---|---|
| Active context | `task count` says 193 when 245 tasks are pending; `task add` quietly tags the new task with the context's write filter. | Passes `rc.context=none` per command and never changes the user's context. |
| Prompts | Bulk edits and deletes wait for `(yes/no)`, so a non-interactive shell hangs or answers "no". | Verifies what a filter matches first, then runs with `rc.confirmation=off rc.bulk=0`. |
| Short ids | Ids renumber between two commands, so `task 502 done` can complete a different task. | Acts on uuid prefixes. |
| Export JSON | A numeric UDA that holds `2d` is exported as `{"est":2d}`, and `jq` fails. | Reads through `scripts/tw-export.sh`, which quotes those values. |
| Filter quoting | `task 'status:pending and (project:a or project:b)'` matches nothing. | Passes each term, operator and paren as its own argument. |

It also covers filters, dates, contexts, recurrence, custom reports, UDAs and
hooks, and gives the agent a **self-tracking** mode: it records its own
multi-step work as tasks under a separate tag and project (`+agent`,
`project:agent.<repo>`), so you can follow it with `task +ACTIVE` without the
tasks showing up in your own reports.

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

To turn on self-tracking, ask for it in your `CLAUDE.md`, for example:

```markdown
Track multi-step session work in Taskwarrior: follow the taskwarrior skill's
"Self-tracking" section, tag tasks +claude and file them under
project:claude.<repo>.
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
├── SKILL.md                     the rules, reading, adding, modifying, self-tracking
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

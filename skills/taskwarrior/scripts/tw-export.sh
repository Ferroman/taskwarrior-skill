#!/usr/bin/env bash
# tw-export.sh: a Taskwarrior export that always produces VALID JSON.
#
# Why this exists:
#   A UDA declared `numeric` that holds duration values (an estimate field with
#   values such as "2d", "15m" or "1h") is written by `task export` as a BARE
#   token: {"est":2d}. That is invalid JSON, so jq stops with "Invalid numeric
#   literal". Overriding one known UDA's type (rc.uda.<name>.type=duration)
#   fixes only that UDA, so this script instead quotes every bare token that
#   starts with a digit and continues with a letter, whatever the field is
#   called: {"est":2d} -> {"est":"2d"}. Real numbers, strings and the task
#   database are left alone.
#
#   rc.context=none is passed as well. On 3.4 and 3.5 `task export` ignores the
#   active context anyway (report commands do not), so this is a defensive
#   no-op that documents intent and guards other versions.
#
# Usage:
#   tw-export.sh [filter/args...]        # -> JSON array on stdout
#   tw-export.sh status:pending +OVERDUE
#   tw-export.sh project:work | jq -r '.[].description'
#
# Pass each filter term as its own argument (operators and parens too); never
# fold a multi-term filter into one quoted string. See references/filters.md.
#
# The exit status is that of `task` (pipefail), so a bad filter still fails.

set -uo pipefail

task rc.context=none rc.verbose=nothing "$@" export |
  sed -E 's/("[A-Za-z0-9_]+":)(-?[0-9][0-9.]*[A-Za-zµ][A-Za-z0-9µ]*)([,}])/\1"\2"\3/g'

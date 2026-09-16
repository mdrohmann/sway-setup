# The scripts

Ten POSIX shell scripts, about 1,300 lines, in [`bin/`](../bin). They are all
`#!/bin/sh` — no bash, no Python, no runtime. Each one is commented at length
in the source; this page is the map, not the territory. If a script interests
you, read it: the comments explain *why*, which is the part that does not fit
in a table.

Two conventions run through all of them:

- **State lives in `$XDG_RUNTIME_DIR`**, written atomically via a temp file and
  `mv -f`. It is a tmpfs, so it is fast and it clears on logout, which is the
  correct lifetime for "is a pomodoro running".
- **Waybar modules are a subcommand**, not a separate script. `pomodoro waybar`
  prints one line of JSON; `pomodoro toggle` is what the keybinding runs. The
  bar polls the same file that the keyboard drives, so they cannot disagree.

---

## `pomodoro` — a tomato that ripens

`$mod+t` toggles, `$mod+Shift+t` resets. Waybar polls `pomodoro waybar` once a
second, and clicking the tomato works too (left toggle, middle stop, right
reset).

The display is the interesting part. Rather than a countdown you have to read,
the emoji ripens through its stages — 🌱 seedling, 🌿 herb, 🍅 tomato — and
within each stage fades in via 30 CSS opacity classes, `pomo-m0` through
`pomo-m29`, defined in [`waybar/style.css`](../config/waybar/style.css). You
learn to read your remaining time peripherally, without parsing digits. On
expiry it blinks at 1 Hz, forever, by alternating two classes on wall-clock
parity.

Session length is `MINUTES` in [`pomodoro.conf`](../config/pomodoro.conf),
sourced as shell. Because waybar re-runs the script every second, editing that
file takes effect on the next tick — nothing to restart. A pomodoro already
running keeps its elapsed time and simply gets a new finish line.

The opacity ramp is calibrated against waybar's exact `#323232` background and
the measured contrast of those specific glyphs. Changing the bar colour without
recalculating the ramp will make the early stages invisible.

## `claude-sessions` — jump to the right terminal

`$mod+g` opens a rofi picker of every running Claude Code session, showing
whether each is working or waiting on you, and how much of its context window
is gone. Picking one focuses the terminal hosting it.

Finding that terminal is the whole trick, and there is no API for it. The
script walks `/proc` ancestry — `PPid` from `/proc/<pid>/status`, plus
`starttime` from `/proc/<pid>/stat` to defend against PID reuse — until it
reaches a process sway knows about in `swaymsg -t get_tree`. If the session is
inside tmux, ancestry dead-ends at the server, so it takes a second path
through `tmux list-clients`, mapping `client_tty` back to a process by its
`/proc/*/fd/0`.

It also drives a waybar module and fires a notification on the edge from
"working" to "ready", which is the moment you actually want to know about.
Per-PID state in `$XDG_RUNTIME_DIR/claude-sessions.seen` makes that an edge and
not a nag.

Session data comes from `~/.claude/sessions/<pid>.json` and the transcript
`.jsonl`, read backwards with `tac | grep -m1 '"usage"'` so context accounting
costs one line and not a whole file.

## `webapp` — web apps that behave like applications

`$mod+c` for Slack, `$mod+m` for Gmail (and `calendar` is configured, unbound).
Each is a Chrome `--app` window pinned to a named workspace, toggling to it and
back.

Everything hard about this is window identity. Chrome derives an app id of the
shape `chrome-<host>__<path>-<profile>`, so the script matches on a **prefix
regex of `app_id` only** — `^chrome-app\.slack\.com__`. Never on title: a
title-matching `for_window` rule re-fires every time a new Slack message
changes the title, and yanks the window back to its workspace while you are
reading something else.

`for_window` only fires when a window is mapped, so placement cannot be left to
sway alone — `place_group()` re-asserts it on every invocation. Unread counts
are scraped out of the window title (Slack's `"! … N new items"`, Gmail's
`"Inbox (1,234)"`), cached in `$XDG_RUNTIME_DIR`, and used to drive sway's
`urgent` flag so the workspace button lights up in the bar. Waybar output is
built with `jq -cn` rather than `printf`, because mail subjects contain quotes
and will break naive JSON.

`slack` is an eleven-line wrapper — `exec "${0%/*}/webapp" slack "$@"` — kept
only so sway and waybar need not know the two are the same program. It resolves
`webapp` as a sibling, so **the two must stay in the same directory**.

## `named-term` — terminals you can find again

`$mod+Return`. Opens foot with its title locked to `<adjective> <animal> - <cwd>`
— `brave otter - ~/ion/core` — chosen from 20 adjectives and 30 animals, with
collision retry.

The point is `$mod+o` (`rofi -show window`). A window list of nine terminals all
called "foot" is useless; a list of "brave otter", "quiet heron" and "clever
fox" is one you learn in a day. Names are stable for the life of the window,
which is what makes them memorable.

It also inherits the focused terminal's working directory, by reading
`/proc/<child>/cwd` of the shell inside it — so a new terminal opens where you
already were. `$mod+Shift+Return` is the escape hatch to a plain `foot`.

## `lock-session` — nineteen lines that took an afternoon

Wraps `hyprlock`. Called by `$mod+Ctrl+l`, and by `swayidle` at the 300s
timeout and on `before-sleep`.

```sh
pidof hyprlock >/dev/null && exit 0
hyprlock
swaymsg "output * power on" >/dev/null
```

Both extra lines are bug fixes. The `swaymsg` exists because this ThinkPad's
Goodix fingerprint sensor talks to fprintd over USB rather than appearing on
sway's seat as an input device — so unlocking by fingerprint generates *zero*
libinput activity, swayidle never considers itself resumed, never runs its
`resume` hook, and the screen stays black after a perfectly successful unlock.

The `pidof` guard covers the double-lock race: the idle timeout fires, then
suspend follows, and a second instance would fight the first over the
`ext-session-lock` protocol.

See also the `before-sleep` line in [`sway/config`](../config/sway/config):
`'~/.local/bin/lock-session & sleep 1'`. Hyprlock has no `-f` daemonize flag,
so under `swayidle -w` it would hold a systemd sleep inhibitor open for as long
as the screen stayed locked — which is to say, suspend would never happen.
Backgrounding it and giving it a second to grab the session lock is what fixes
that.

## `volume` and `brightness` — matching OSDs

Bound to the `XF86Audio*` and `XF86MonBrightness*` keys, all `--locked` so they
work on the lock screen. `Shift` plus the same key gives 1% steps instead of
the default, for when you are trying to land on exactly right.

Both draw the same dunst OSD — a progress bar via `-h int:value:N` with a stack
tag, so repeated presses replace the notification instead of stacking fifteen
of them. `volume` goes through `wpctl` (PipeWire), caps boost at 1.5, and picks
its icon from the `audio-volume-*` set. `brightness` uses `brightnessctl` with
a 5% floor derived from the raw maximum, because 0% is not a brightness anyone
wants to arrive at by holding a key.

## `clip-sync` — one clipboard

Started from sway as `clip-sync both`. Keeps X11-style PRIMARY (select to copy,
middle-click to paste) and CLIPBOARD (explicit Ctrl-C) in sync in both
directions, so it stops mattering which one you used.

Two watchers would echo each other forever, so both write the last value to a
shared file in `$XDG_RUNTIME_DIR` and skip anything that matches. Text only, by
design, and `--type text/plain` avoids wl-copy forking perl to sniff mime types
on every copy.

## `window-identity` — for writing the rules above

`$mod+Shift+i` puts the focused window's `app_id`, `class` and `title` in a
notification. Nine lines, and the only way to write a `for_window` rule without
guessing. It lives right next to those rules in the sway config for that
reason.

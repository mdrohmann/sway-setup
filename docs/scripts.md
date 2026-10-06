# The scripts

The ten scripts that make up the desktop, about 1,300 lines, in
[`bin/`](../bin). They are all `#!/bin/sh` — no bash, no Python, no runtime.
Each one is commented at length in the source; this page is the map, not the
territory. If a script interests you, read it: the comments explain *why*,
which is the part that does not fit in a table.

(`bin/` also holds [`blur-shot`](../bin/blur-shot), which is not part of the
desktop — nothing binds or execs it. It is the tool that made the README's
screenshots, and the README describes it.)

Two conventions run through all of them:

- **State lives in `$XDG_RUNTIME_DIR`**, written atomically via a temp file and
  `mv -f`. It is a tmpfs, so it is fast and it clears on logout, which is the
  correct lifetime for "is a pomodoro running".
- **Waybar modules are a subcommand**, not a separate script. `pomodoro waybar`
  prints one line of JSON; `pomodoro toggle` is what the keybinding runs. The
  bar polls the same file that the keyboard drives, so they cannot disagree.

---

## `pomodoro` — a tomato that ripens

`$mod+t` toggles, `$mod+Shift+t` alternates the two timers — a fresh pomodoro,
then the 5-minute break, then a pomodoro again. From idle it always starts a
pomodoro, so the break is only ever entered deliberately, and a pomodoro that
has finished ripening is followed by the break without naming it. Waybar polls
`pomodoro waybar` once a second, and clicking the tomato works too (left toggle,
middle stop, right starts a fresh pomodoro).

The display is the interesting part. Rather than a countdown you have to read,
the emoji ripens through its stages — 🌱 seedling, 🌿 herb, 🍅 tomato — and
within each stage fades in via 30 CSS opacity classes, `pomo-m0` through
`pomo-m29`, defined in [`waybar/style.css`](../config/waybar/style.css). You
learn to read your remaining time peripherally, without parsing digits. On
expiry it blinks forever by alternating two classes on wall-clock parity,
divided by `BLINK` so the flash can be slowed without changing the poll rate.

The break reads in the opposite direction: one glyph, ☕, starting at full
opacity and draining as it is spent, over ten `pomo-brk0`..`pomo-brk9` steps,
under a blue line (`pomo-break`) that shortens as the break is spent, so length
carries the time remaining and the fade only says "this is a break". Growing
means work; emptying means rest.

That line is a hard-stop gradient painted into a 2px strip, not a border: a
border spans the whole widget and its width is thickness, not length.

Both lengths (`MINUTES`, `BREAK_MINUTES`) and the blink rate (`BLINK`) live in
[`pomodoro.conf`](../config/pomodoro.conf), sourced as shell. Because waybar re-runs the script every second, editing that
file takes effect on the next tick — nothing to restart. A pomodoro already
running keeps its elapsed time and simply gets a new finish line.

The `pomo-m*` opacity ramp is calibrated against waybar's exact `#323232`
background and the measured contrast of those specific glyphs. Changing the bar
colour without recalculating the ramp will make the early stages invisible.

The break's ten steps need no such cross-glyph calibration — a single glyph has
no stage boundary to go backwards over — and are spaced so the cup's measured
contrast falls in equal increments rather than its opacity, which would look
static for most of the break and then collapse at the end.

## `claude-sessions` — jump to the right terminal

`$mod+g` opens a rofi picker of every running Claude Code session, showing
whether each is working or waiting on you, and how much of its context window
is gone. Picking one focuses the terminal hosting it.

Finding that terminal is the whole trick, and there is no API for it. The
script walks `/proc` ancestry — `PPid` from `/proc/<pid>/status`, plus
`starttime` from `/proc/<pid>/stat` to defend against PID reuse — until it
reaches a process sway knows about in `swaymsg -t get_tree`.

A multiplexer breaks that, because ancestry dead-ends at a detached server, and
both of them are handled by finding the window the **client** is in instead.
For tmux that means `tmux list-clients`, mapping `client_tty` back to a process
by its `/proc/*/fd/0`. For herdr it means the socket API: `herdr pane list` plus
one `herdr pane process-info` per pane gives pid → pane, and the client is
whichever `herdr` process (not the server) resolves to a window. Focusing then
takes two steps — sway focuses that terminal, then `herdr workspace/tab/agent
focus` walks herdr to the pane. A herdr row is labelled with its **workspace
label**, not the window title: every pane shares one window, so the title would
label every herdr row identically.

The four statuses Claude Code writes are `waiting` (blocked on you — the
`waitingFor` field says on what), `idle` (ready), `busy` (mid-turn) and `shell`
(idle, but the terminal is showing a shell). Only `waiting` sorts to the top;
treating an unrecognised status as urgent instead is what once parked a
backgrounded `shell` session at the top of the menu claiming to want input.

It also drives a waybar module and fires a notification on the edge from
"working" to "ready", which is the moment you actually want to know about.
Per-PID state in `$XDG_RUNTIME_DIR/claude-sessions.seen` makes that an edge and
not a nag.

Session data comes from `~/.claude/sessions/<pid>.json` and the transcript
`.jsonl`. The transcript is searched backwards through an `mmap`, so reading the
context in use (the last `"usage"` record) and the conversation's title (the last
`ai-title` or `custom-title`) costs however far back the answer is, not the size
of the file. That title is what a row is called whenever the session's own name
is only the derived `<dir>-<hash>` placeholder.

It is Python rather than `sh`, unlike everything else in `bin/`. The shell
version spent most of its time starting processes — dozens of `awk`, `jq` and
`sed` calls per row — and its worst bug was a cache filled inside `$(...)` and
thrown away with the subshell, which fetched the sway tree 69 times for one
menu. The port lists a dozen sessions in about 0.15s, down from 3.4s.

## `night-light` — gammastep, where you can see it

`$mod+Shift+b` toggles gammastep and `custom/night-light` shows whether it is
armed. The readout exists for the daytime case: gammastep holds 6500K all day,
which is precisely what the screen looks like with gammastep switched off, so
until sunset there is nothing to tell the two apart.

The state is gammastep's own rather than a note of what we last told it. Its
hooks (`~/.config/gammastep/hooks`, linked in with the rest of the config) fire
on one event, `period-changed`, and that event covers more than its name
suggests: disabling gammastep reports a change *to* the period `none`, and
re-enabling reports a change away from it. So the hook writes the period to
`$XDG_RUNTIME_DIR` and `none` means off — and because the daemon is the one
reporting, the tray icon's Enabled box and `$mod+Shift+b` both show up, which a
state file written by whichever one sent the signal would not manage.

Nothing fires when gammastep *exits*, so the file can outlive the process. That
is the one thing the module checks for itself, and the reason it polls at all:
`signal: 8` from the hook makes a toggle instant, and the 30s interval is there
only to notice a death that announced nothing.

Two glyphs rather than two shades: `fa-moon-o` when a night-light is on duty,
`fa-sun-o` when it is off. Opacity then says how far into the evening it is,
which is information the screen is already giving you.

## `foot-theme` — light and dark, on one key

`$mod+Ctrl+b` flips every running foot between Solarized Dark and Light, and
`$mod+Shift+b` toggles the night-light next to it. The two sit together because
they get mistaken for each other: gammastep warms the whole display, and against
a dark terminal that reads as the terminal having changed rather than the screen.
Neither is the fix if the warm cast arrives at the wrong *time* — that is `lat`
and `lon` in `~/.config/gammastep/config.ini`.

The night-light needs no script: gammastep toggles its own state on `SIGUSR1`.

foot needs one only because it will not answer a question. It loads both
`[colors]` and `[colors2]` at startup and swaps on a signal — `USR1` for dark,
`USR2` for light — but offers no way to ask which one a terminal is showing, so
there is nothing to toggle against. The state file in `$XDG_RUNTIME_DIR` is that
answer and nothing more. One file covers every terminal because the signal is
broadcast; a foot opened afterwards still starts dark, so it disagrees with the
others until the next toggle brings them back in line.

## `keys` — the bindings, as a menu

`$mod+slash` lists every binding in the sway config with what it does, and runs
the one you pick. It is a cheat sheet you can act on, which is most of why it is
worth having over a printed one.

sway has no IPC for this — `swaymsg -t get_binding_modes` names the modes and
nothing inside them — so the config is the source, parsed the way sway reads it:
the same files in the same order, `set $var` expanded (recursively, because
`$reload` is built out of two commands), `\`-continuations joined, and `mode`
blocks tracked so a binding that only works inside one says so.

Descriptions come from the comments that are already there, rather than a second
list that would drift out of date. The first sentence of the comment block above
a binding is the description; everything after it is the reasoning, which belongs
in the file and not in a menu row. A `#:` line overrides that where the derived
text is wrong or where one comment covers a group that needs telling apart — the
four `dunstctl` keys being the case that asks for it. Both are sticky until the
next paragraph, so one annotation covers a run of bindings.

Picking a row runs it through `swaymsg`, which parses the same command text sway
parses from the config — so a row does exactly what the key does, including the
ones that only make sense against whatever had focus a moment ago.

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

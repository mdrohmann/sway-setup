# sway-setup

My Sway desktop on Ubuntu: a tiling compositor, a status bar, and ten small
shell scripts that do the parts a window manager does not.

There is no framework here and nothing to configure but text files. The sway
config is one 498-line file, and roughly half of it is comments explaining why
each choice is what it is — including the three or four places where the
obvious approach is quietly wrong. The scripts are POSIX `sh`, about 1,300
lines in total, no bash-isms and no runtime to install.

It runs on Ubuntu 26.04 on a ThinkPad T14. Most of it is portable; the handful
of things that are not are listed under [Things you will want to
change](#things-you-will-want-to-change).

![The waybar strip: workspace buttons, then the pomodoro, Claude sessions,
Slack, Gmail, CPU, memory, temperature, bluetooth, battery and
clock](docs/screenshots/waybar.png)

The bar, with the empty middle elided (the three dots). The sprout is the
pomodoro partway through a session — it ripens 🌱 → 🌿 → 🍅 as the time goes,
so you read it out of the corner of your eye instead of parsing a countdown.
`●4` is four Claude Code sessions, none of them waiting on me.

## The parts

| | Key | What it does |
|---|---|---|
| [`named-term`](bin/named-term) | `$mod+Return` | Terminals named `brave otter - ~/ion/core`, so `rofi -show window` is navigable. Opens in the focused terminal's directory. |
| [`claude-sessions`](bin/claude-sessions) | `$mod+g` | Lists running Claude Code sessions with status and context usage; jumps to the terminal hosting one, through tmux if needed. |
| [`webapp`](bin/webapp) / [`slack`](bin/slack) | `$mod+c`, `$mod+m` | Slack and Gmail as Chrome app windows pinned to named workspaces, with unread counts scraped from the window title. |
| [`pomodoro`](bin/pomodoro) | `$mod+t` | A tomato in the bar that ripens 🌱 → 🌿 → 🍅 as the session runs, then blinks. |
| [`lock-session`](bin/lock-session) | `$mod+Ctrl+l` | Wraps hyprlock. Nineteen lines, two of which are bug fixes — see below. |
| [`volume`](bin/volume) / [`brightness`](bin/brightness) | media keys | Matching dunst OSDs, `--locked` so they work on the lock screen, `Shift` for 1% steps. |
| [`clip-sync`](bin/clip-sync) | (runs at start) | Keeps PRIMARY and CLIPBOARD in sync, so it stops mattering which one you used. |
| [`window-identity`](bin/window-identity) | `$mod+Shift+i` | Shows the focused window's `app_id` and `class`, for writing `for_window` rules. |

[**docs/scripts.md**](docs/scripts.md) covers each one properly.

One extra, not part of the desktop — nothing binds it:
[`blur-shot`](bin/blur-shot) captures the screen with window contents blurred,
for publishing a screenshot without publishing what is on it. `grim` has no
filters, so the blur is a Pillow pass, and the rectangles come from sway's IPC
rather than being guessed. It made the image above (`blur-shot --bar`).

Be careful with `--titles`: sway draws title bars *above* the window rectangle,
so they survive the default blur — and `named-term` puts the working directory
in the title, so a terminal opened in `~/work/acme-merger` will publish that.

## The bits worth stealing

Even if you never run any of this, a few of these cost me an evening each and
are written down here so they cost you none.

**A fingerprint unlock can leave you at a black screen, and it is not your
locker's fault.** This ThinkPad's Goodix sensor talks to fprintd over USB
instead of appearing on sway's seat as an input device. So a successful
fingerprint unlock produces *zero* libinput events, `swayidle` never decides it
has resumed, its `resume` hook never runs, and the displays it powered off stay
off. [`lock-session`](bin/lock-session) fixes it by running `swaymsg "output *
power on"` itself after hyprlock exits.

**A blocking locker in `before-sleep` will stop your laptop suspending.**
Hyprlock has no daemonize flag, so under `swayidle -w` it holds a systemd sleep
inhibitor open for as long as the screen is locked — which is to say, forever.
The fix is `'~/.local/bin/lock-session & sleep 1'`: background it, give it a
second to grab the session lock, let the inhibitor drop.

**Run waybar as `swaybar_command`.** Put `swaybar_command waybar` inside sway's
`bar` block and sway owns waybar's lifecycle — it starts with the session and
restarts on reload, with no `pkill waybar && waybar &` in your config and no
orphans after a crash. The config keeps the replaced swaybar block as a comment
explaining why it went: swaybar has no DBusMenu, so tray icons like nm-applet
cannot be clicked.

**Match Chrome web-app windows on `app_id`, never on `title`.** A
title-matching `for_window` rule looks fine until a new Slack message changes
the title, the rule re-fires, and the window is yanked back to its workspace
while you were reading something else. Match a prefix of the `app_id`
(`^chrome-app\.slack\.com__`) — and note `for_window` only fires when a window
is *mapped*, so anything that must survive a manual move has to be re-asserted
by hand, which is what [`webapp`](bin/webapp) does on every keypress.

**`move to workspace mail, layout tabbed` — the order is load-bearing.**
Reversed, `layout tabbed` applies to whichever workspace the window happened to
map on, silently converting the one you were working in.

**`~` survives inside single quotes here, and that surprised me.** The swayidle
lines look like they need an absolute path, because `~` does not expand when
quoted. But there are two shells in the chain, not one: sway runs the `exec`
line through `sh -c`, which strips the quotes and hands the literal string to
swayidle, which runs it through `sh -c` in turn — and *that* shell sees an
unquoted tilde at word start and expands it. Which is why this repo has no
username hardcoded anywhere.

## Install

```sh
git clone https://github.com/mdrohmann/sway-setup ~/sway-setup
cd ~/sway-setup
./install.sh --dry-run    # read this first
./install.sh
```

Then log out and back in, or press `$mod+Shift+c` to reload sway.

`install.sh` **symlinks** — it does not copy. `~/.config/sway` becomes a link
into this repo, so editing `~/.config/sway/config` at midnight means `git diff`
shows it in the morning. That is the point; a config you have to remember to
copy back is a config that drifts.

Anything already in the way is **moved aside**, never deleted, as
`<name>.pre-sway-setup-<timestamp>`. Re-running after a `git pull` is safe and
does nothing. The script checks for missing dependencies at the end and prints
the `apt` line, but does not install anything — running someone else's
`sudo apt install` off a blog link is a bad habit and I would rather not teach
it.

## Things you will want to change

Nothing here is templated; it is a personal config, not a distribution. These
are the lines that are about *my* hardware and accounts rather than about sway:

| What | Where | Why |
|---|---|---|
| `hwmon-path-abs: …/coretemp.0/hwmon` | `config/waybar/config` | Intel only. AMD needs `k10temp`. |
| `battery` module, `BAT0`, `{health}`, `{cycles}` | `config/waybar/config` | Laptop only. Delete the module on a desktop. |
| `lat` / `lon` | `config/gammastep/config.ini` | A placeholder (Lisbon). Set your own. |
| `shell=/usr/bin/zsh` | `config/foot/foot.ini` | Path differs off Debian/Ubuntu. |
| `/u/0/` in the URLs, Chrome profile `Default` | `bin/webapp` | First Google account, only Chrome profile. Both move if you have more than one. |
| `CHIME=` | `bin/pomodoro` | Wants the GNOME sound theme installed. |
| Workspace names `slack` and `mail` | `config/sway/config`, `config/waybar/style.css` | These must match each other, or the bar's hide/show rules silently do nothing. |

## Before you lock anything

Hyprlock's `auth { pam { module = hyprlock } }` needs a PAM stack file. It is
root-owned and lives outside `$HOME`, so **no git repo can install it for you**,
and `install.sh` will not try. Without it hyprlock starts, accepts your
password, and rejects it — every time. That is a session you cannot unlock,
with a TTY as your only way back in.

A reference copy is at [`etc/pam.d/hyprlock`](etc/pam.d/hyprlock):

```sh
sudo cp etc/pam.d/hyprlock /etc/pam.d/hyprlock
```

```
# hyprlock talks to fprintd directly over D-Bus, so pam_fprintd must NOT be in
# this stack: it would block password entry for its whole timeout, serialising
# two things hyprlock deliberately runs in parallel. Password path only here.
auth     required   pam_unix.so     try_first_pass nullok
account  include    common-account
session  include    common-session
```

The fingerprint block in `hyprlock.conf` additionally wants `fprintd` and an
enrolled print (`fprintd-enroll`). It is optional — delete it if your machine
has no sensor.

## Machine-local overrides

`config/sway/config` ends with `include ~/.config/sway/config.d/*.conf`, and
that directory is gitignored. Outputs, scale, keyboard layout — anything about
*your* machine rather than about the setup — goes in a file there, and a second
machine can differ without either of them ever touching the tracked config.

## What is not here

**Any rofi or dunst config.** Both run on pure distro defaults. That is
deliberate, not an oversight — if you came looking for where the notification
styling lives, there isn't any.

**My htop config, git identity, or shell.** Out of scope. `htoprc` in
particular is excluded because htop rewrites the file itself whenever you
change a setting, which makes a symlinked copy a permanent source of dirty
`git status`.

## Known limitations

- **`slack` must be called by path**, as sway and waybar both do. It finds its
  real implementation with `exec "${0%/*}/webapp"`, and POSIX leaves `${0%/*}`
  *unchanged* when there is no slash — so invoking a bare `slack` from `PATH`
  would try to run `slack/webapp` and fail confusingly.
- **`claude-sessions` reads Claude Code's internal layout** under
  `~/.claude/sessions` and `~/.claude/projects`. That is undocumented and
  version-coupled; expect it to need a fix after an update, and to show nothing
  at all on a machine without Claude Code.
- **`foot.ini` pins `shell=/usr/bin/zsh`.** Without zsh installed, foot exits
  the moment it opens — which in a fresh session means no terminal and no way
  to fix the config that is causing it. `install.sh` warns about this loudly.
- **The pomodoro chime fails silently.** `paplay` output is discarded, so a
  missing `CHIME` file means no sound and no error. Install `gnome-audio`, or
  point it somewhere else.
- **Battery is laptop-only and the temperature sensor is Intel-only.** See the
  table above.

## License

MIT. Take whatever is useful.

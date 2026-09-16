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

## What is not here

**`/etc/pam.d/hyprlock`.** Hyprlock's `auth { pam { module = hyprlock } }` needs
a PAM stack file, which is root-owned and outside `$HOME`, so no git repo can
install it for you. Without it you will not be able to unlock. The fingerprint
block additionally wants `fprintd` and an enrolled print, and is entirely
optional — delete it if your machine has no sensor.

**Any rofi or dunst config.** Both run on pure distro defaults. That is
deliberate, not an oversight — if you came looking for where the notification
styling lives, there isn't any.

**My htop config, git identity, or shell.** Out of scope. `htoprc` in
particular is excluded because htop rewrites the file itself whenever you
change a setting, which makes a symlinked copy a permanent source of dirty
`git status`.

## License

MIT. Take whatever is useful.

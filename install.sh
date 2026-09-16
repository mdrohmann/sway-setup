#!/bin/sh
# Link this repo's configs and scripts into $HOME, then report what is missing.
#
# The repo is the source of truth: everything is symlinked, never copied, so
# editing ~/.config/sway/config edits the file in here and `git diff` sees it
# immediately. That is the whole point -- a config you tweak at 11pm and forget
# to copy back is a config that drifts.
#
# Nothing is ever deleted. Anything already in the way is moved aside with a
# timestamped suffix and the move is printed.
#
#   ./install.sh --dry-run    say what would happen, touch nothing
#   ./install.sh              do it
#
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MANIFEST="$REPO/manifest"
STAMP=$(date +%Y%m%d-%H%M%S)
DRY=no

for arg in "$@"; do
    case $arg in
        -n|--dry-run) DRY=yes ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "install.sh: unknown option '$arg' (try --help)" >&2
            exit 2
            ;;
    esac
done

[ -f "$MANIFEST" ] || { echo "install.sh: no manifest next to $0" >&2; exit 1; }

[ "$DRY" = yes ] && echo "DRY RUN -- nothing will be changed."
echo "Linking from $REPO into $HOME"
echo

run() {
    if [ "$DRY" = yes ]; then
        echo "      would: $*"
    else
        "$@"
    fi
}

linked=0 moved=0 already=0

# ---------------------------------------------------------------- link pass

while read -r src dst; do
    case $src in ''|\#*) continue ;; esac
    [ -n "${dst:-}" ] || continue

    source="$REPO/$src"
    target="$HOME/$dst"

    if [ ! -e "$source" ]; then
        echo "  !!  $dst -- missing in repo ($src), skipped"
        continue
    fi

    # Already pointing where we want it? Leave it alone and stay quiet-ish.
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        echo "  ok  $dst"
        already=$((already + 1))
        continue
    fi

    parent=$(dirname "$target")
    [ -d "$parent" ] || run mkdir -p "$parent"

    # Something else is there. Move it, never remove it -- this may be the
    # only copy of a config someone spent an evening on.
    if [ -e "$target" ] || [ -L "$target" ]; then
        backup="$target.pre-sway-setup-$STAMP"
        echo "  mv  $dst -> $(basename "$backup")"
        run mv -- "$target" "$backup"
        moved=$((moved + 1))
    fi

    echo "  ln  $dst"
    run ln -s -- "$source" "$target"
    linked=$((linked + 1))
done < "$MANIFEST"

# git preserves the exec bit, but a zip/tarball download does not.
if [ "$DRY" = no ]; then
    chmod +x "$REPO"/bin/* 2>/dev/null || true
fi

echo
echo "  $linked linked, $already already correct, $moved moved aside"
[ "$moved" -gt 0 ] && echo "  (moved files kept as *.pre-sway-setup-$STAMP -- delete them once happy)"

# ---------------------------------------------------------- dependency pass
#
# Checked, not installed. An install script from a stranger's blog post that
# runs `sudo apt install` is one nobody should run; printing the command costs
# you one paste and costs me your trust only if I am wrong about the list.

REQUIRED="sway swaymsg swayidle swaynag waybar foot rofi wmenu jq dunst \
notify-send dunstctl wl-copy wl-paste cliphist grimshot brightnessctl wpctl \
paplay setsid"
OPTIONAL="hyprlock gammastep google-chrome tmux nm-applet blueman-applet \
poweralertd htop alsamixer"

missing_req= missing_opt=
for c in $REQUIRED; do command -v "$c" >/dev/null 2>&1 || missing_req="$missing_req $c"; done
for c in $OPTIONAL; do command -v "$c" >/dev/null 2>&1 || missing_opt="$missing_opt $c"; done

echo
if [ -z "$missing_req" ] && [ -z "$missing_opt" ]; then
    echo "All dependencies present."
else
    [ -n "$missing_req" ] && echo "Missing (required):$missing_req"
    [ -n "$missing_opt" ] && echo "Missing (optional):$missing_opt"
    cat <<'EOF'

On Ubuntu/Debian most of that is:

  sudo apt install sway swayidle swaylock waybar foot rofi wmenu jq dunst \
      wl-clipboard cliphist sway-contrib brightnessctl wireplumber \
      pipewire-audio hyprlock gammastep gammastep-indicator tmux \
      network-manager-gnome blueman poweralertd policykit-1-gnome htop \
      alsa-utils fonts-dejavu-core fonts-font-awesome fonts-noto-color-emoji \
      fonts-jetbrains-mono

Google Chrome is not in the archive; the web-app scripts need it. And see
"What is not here" in the README for /etc/pam.d/hyprlock, which no git repo
can install for you.
EOF
fi

echo
echo "Log out and back in, or press \$mod+Shift+c to reload sway."

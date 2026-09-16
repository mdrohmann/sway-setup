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

PACKAGES="$REPO/packages"

missing_req= missing_opt= apt_req= apt_opt=

if [ ! -f "$PACKAGES" ]; then
    echo "  !! no packages file next to $0 -- skipping the dependency check" >&2
else
    # Three columns: kind, apt package, and what to look for. The check value
    # is last so a font name may contain spaces.
    while read -r kind pkg check; do
        case $kind in ''|\#*) continue ;; esac
        [ -n "${check:-}" ] || continue
        check=${check%%#*}                        # strip trailing comment
        check=$(printf '%s' "$check" | sed 's/[[:space:]]*$//')

        case $kind in
            font) fc-list 2>/dev/null | grep -qi -- "$check" && continue ;;
            *)    command -v "$check" >/dev/null 2>&1 && continue ;;
        esac

        # python3-pil is a module, not a command -- python3 existing proves
        # nothing about Pillow being importable.
        if [ "$pkg" = python3-pil ]; then
            python3 -c 'import PIL' >/dev/null 2>&1 && continue
        fi

        case $kind in
            req)  missing_req="$missing_req $check"; apt_req="$apt_req $pkg" ;;
            *)    missing_opt="$missing_opt $check"; apt_opt="$apt_opt $pkg" ;;
        esac
    done < "$PACKAGES"
fi

echo
if [ -z "$missing_req" ] && [ -z "$missing_opt" ]; then
    echo "All dependencies present."
else
    [ -n "$missing_req" ] && echo "Missing (required):$missing_req"
    [ -n "$missing_opt" ] && echo "Missing (optional):$missing_opt"
    # Deduplicate: one package can provide several of the things above.
    apt_all=$(printf '%s %s' "$apt_req" "$apt_opt" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')
    echo
    echo "On Ubuntu that is:"
    echo
    echo "  sudo apt install $apt_all"
    cat <<'EOF'

Google Chrome is not in the archive and the web-app scripts need it -- get the
.deb from google.com/chrome. See also "Before you lock anything" in the README
for /etc/pam.d/hyprlock, which no package and no git repo can install for you.
EOF
fi

# ------------------------------------------------------- things that bite
#
# Two failure modes here are not "a module looks wrong", they are "you cannot
# get back into your session". Both are checked read-only; neither is fixed
# for you, because both need root or a decision.

if [ ! -f /etc/pam.d/hyprlock ]; then
    cat <<EOF

  !!  /etc/pam.d/hyprlock is missing.

      hyprlock will start, accept your password, and reject it -- every time.
      That is a locked session you cannot unlock, with a TTY as your only way
      back. Install it BEFORE you lock anything:

        sudo cp $REPO/etc/pam.d/hyprlock /etc/pam.d/hyprlock
EOF
fi

# foot.ini pins shell=/usr/bin/zsh. On a machine without zsh, foot exits the
# instant it opens -- which in a fresh session means no terminal at all, and
# no way to edit the config that is causing it.
if ! [ -x /usr/bin/zsh ]; then
    cat <<EOF

  !!  /usr/bin/zsh does not exist, and config/foot/foot.ini pins it.

      foot will exit immediately on launch, leaving you with no terminal.
      Either 'sudo apt install zsh', or delete the 'shell=' line in
      $REPO/config/foot/foot.ini before you reload.
EOF
fi

echo
echo "Log out and back in, or press \$mod+Shift+c to reload sway."

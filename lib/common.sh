# Shared helpers for install and module setup scripts.
#
# Two ways a file reaches the system, and the difference is deliberate:
#
#   home/    -> SYMLINKED into $HOME. Editing the live file edits the repo, so
#               there is no sync step and no one-way overwrite to get wrong.
#
#   system/  -> COPIED to / as root. Never symlinked: this repo is user-writable,
#               and a symlink would let anything that can write $HOME choose what
#               root reads as policy — or, for /usr/local/bin, what root executes
#               under sudo. System files change rarely; a copy costs nothing.
#
# Backups follow Omarchy's own convention (see omarchy-refresh-config):
# <file>.bak.<epoch>, removed again when the content turned out to be identical,
# so repeated runs do not litter the disk.

set -uo pipefail

if [[ -t 1 ]]; then
  C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_B=$'\e[34m' C_D=$'\e[2m' C_N=$'\e[0m'
else
  C_G= C_Y= C_R= C_B= C_D= C_N=
fi

DRY=${DRY:-0}
SKIP_PACKAGES=${SKIP_PACKAGES:-0}
CHANGED=0
FAILED=0

ok()      { printf '%s  ok     %s %s\n' "$C_D" "$C_N" "$1"; }
# Counts rather than flags. Modules are sourced into one process, so a module
# asking "did my own section change anything?" by comparing $CHANGED before and
# after can only tell with a count — a flag another module already set to 1
# stays 1, and the comparison silently reports no change.
changed() { printf '%s  changed%s %s\n' "$C_G" "$C_N" "$1"; CHANGED=$((CHANGED + 1)); }
skip()    { printf '%s  skip   %s %s\n' "$C_D" "$C_N" "$1"; }
warn()    { printf '%s  warn   %s %s\n' "$C_Y" "$C_N" "$1"; }
fail()    { printf '%s  FAIL   %s %s\n' "$C_R" "$C_N" "$1"; FAILED=1; }
section() { printf '\n%s%s%s\n' "$C_B" "$1" "$C_N"; }
note()    { printf '%s         %s%s\n' "$C_D" "$1" "$C_N"; }

dry() { ((DRY)); }

# back_up FILE — Omarchy's convention. Echoes the backup path, or nothing.
back_up() {
  local f=$1 b n=0
  [[ -e $f || -L $f ]] || return 0
  b="$f.bak.$(date +%s)"
  # Backing one file up twice inside the same second must not reuse the name:
  # the first backup holds the original, the second would hold our own edit,
  # and clobbering it loses the only copy of what was there before the run.
  while [[ -e $b ]]; do b="$f.bak.$(date +%s).$((++n))"; done
  if dry; then note "would back up $f -> $b"; echo "$b"; return 0; fi
  cp -a -- "$f" "$b" && echo "$b"
}

# drop_backup_if_same BACKUP CURRENT — keep the disk tidy when nothing changed.
drop_backup_if_same() {
  local b=$1 c=$2
  [[ -n $b && -e $b ]] || return 0
  if cmp -s -- "$b" "$c"; then rm -f -- "$b"; else note "backup: $b"; fi
}

# link_home SRC DEST — symlink DEST -> SRC, backing up whatever was there.
link_home() {
  local src=$1 dest=$2 bak
  if [[ -L $dest && $(readlink -f -- "$dest") == "$(readlink -f -- "$src")" ]]; then
    ok "$dest"
    return
  fi
  if dry; then
    [[ -e $dest ]] && note "would back up $dest"
    changed "$dest -> $src"
    return
  fi
  mkdir -p -- "$(dirname -- "$dest")"
  if [[ -e $dest && ! -L $dest ]]; then
    bak=$(back_up "$dest")
    # An identical file needs no backup kept; the symlink supersedes it anyway.
    [[ -n $bak ]] && cmp -s -- "$bak" "$src" && rm -f -- "$bak"
    [[ -n $bak && -e $bak ]] && note "backup: $bak"
  fi
  rm -f -- "$dest"
  ln -s -- "$src" "$dest" && changed "$dest -> $src" || fail "could not link $dest"
}

# copy_system SRC DEST MODE — root-owned copy, only when the content differs.
# Compared unprivileged: everything installed here ends up world-readable, and
# --dry-run deliberately holds no sudo session.
copy_system() {
  local src=$1 dest=$2 mode=$3 bak
  if [[ -r $dest ]] && cmp -s -- "$src" "$dest"; then
    ok "$dest"
    return
  fi
  if dry; then
    [[ -e $dest ]] && note "would back up $dest"
    changed "$dest"
    return
  fi
  # Report rather than prompt: a password cannot be typed from every context
  # this might run in, and a half-applied system is worse than a clear message.
  if ((${HAVE_SUDO:-0} == 0)); then
    warn "$dest needs root — re-run from a terminal"
    return
  fi
  if [[ -e $dest ]]; then
    bak="$dest.bak.$(date +%s)"
    sudo cp -a -- "$dest" "$bak" && note "backup: $bak"
  fi
  sudo install -Dm "$mode" -o root -g root -- "$src" "$dest" &&
    changed "$dest" || fail "could not install $dest"
}

# root_available [WHAT] — true when a sudo session exists. Reports and returns
# false otherwise, so a module can skip rather than prompt. Any direct `sudo`
# in a module must go through this: copy_system already does, and a prompt from
# a hook or a non-interactive run is a hang rather than an error.
root_available() {
  ((${HAVE_SUDO:-0})) && return 0
  warn "${1:-this step} needs root — re-run from a terminal"
  return 1
}

# link_tree SRCDIR — symlink every file under SRCDIR into $HOME at the same path.
link_tree() {
  local root=$1 f rel
  [[ -d $root ]] || return 0
  while IFS= read -r -d '' f; do
    rel=${f#"$root"/}
    link_home "$f" "$HOME/$rel"
  done < <(find "$root" -type f -print0)
}

# copy_tree SRCDIR — copy every file under SRCDIR to / at the same path.
# Anything under a bin/ directory gets 755, everything else 644.
copy_tree() {
  local root=$1 f rel mode
  [[ -d $root ]] || return 0
  while IFS= read -r -d '' f; do
    rel=${f#"$root"}
    case $rel in */bin/*) mode=755 ;; *) mode=644 ;; esac
    copy_system "$f" "$rel" "$mode"
  done < <(find "$root" -type f -print0)
}

# need_packages [--aur] [--optional] PKG... — install whichever are missing.
#
# `omarchy pkg add` / `omarchy pkg aur add` manage their own privilege
# escalation, so they are never wrapped in sudo. They do need a terminal to ask
# for a password, which means package installation only works from an
# interactive shell — a run from a script or a hook reports instead.
need_packages() {
  local aur=0 optional=0 cmd label
  while [[ ${1:-} == --* ]]; do
    case $1 in
      --aur) aur=1 ;;
      --optional) optional=1 ;;
    esac
    shift
  done
  (($#)) || return 0

  local missing=() p
  for p in "$@"; do
    pacman -Q "$p" &>/dev/null || missing+=("$p")
  done

  ((aur)) && { cmd="omarchy pkg aur add"; label="AUR"; } || { cmd="omarchy pkg add"; label="repo"; }

  if ((${#missing[@]} == 0)); then
    ok "packages ($label): $*"
    return 0
  fi
  if ((SKIP_PACKAGES)); then
    warn "missing ($label): ${missing[*]}"
    note "install with: $cmd ${missing[*]}"
    return 1
  fi
  if dry; then
    changed "would install ($label): ${missing[*]}"
    return 0
  fi
  # No terminal means no password prompt; say so rather than failing obscurely.
  if [[ ! -t 0 ]]; then
    warn "cannot install ${missing[*]} without a terminal"
    note "run from a terminal, or: $cmd ${missing[*]}"
    return 1
  fi
  note "installing ($label): ${missing[*]}"
  if $cmd "${missing[@]}"; then
    changed "packages ($label): ${missing[*]}"
    return 0
  fi
  if ((optional)); then
    warn "optional packages not installed: ${missing[*]}"
    return 1
  fi
  fail "could not install: ${missing[*]}"
  return 1
}

# install_packages_file FILE — apply a module's declarative package list.
#
#   foo          from the official repos
#   aur:foo      from the AUR
#   ?foo         optional: a failure warns instead of failing the run
#   ?aur:foo     both
#
# Blank lines and everything after a `#` are ignored.
install_packages_file() {
  local file=$1
  [[ -r $file ]] || return 0
  local -a repo=() aur=() repo_opt=() aur_opt=()
  local line entry optional

  while IFS= read -r line || [[ -n $line ]]; do
    entry=${line%%#*}
    entry=${entry//[[:space:]]/}
    [[ -n $entry ]] || continue
    optional=0
    [[ $entry == '?'* ]] && { optional=1; entry=${entry#\?}; }
    if [[ $entry == aur:* ]]; then
      entry=${entry#aur:}
      ((optional)) && aur_opt+=("$entry") || aur+=("$entry")
    else
      ((optional)) && repo_opt+=("$entry") || repo+=("$entry")
    fi
  done <"$file"

  ((${#repo[@]}))     && need_packages "${repo[@]}"
  ((${#aur[@]}))      && need_packages --aur "${aur[@]}"
  ((${#repo_opt[@]})) && { need_packages --optional "${repo_opt[@]}" || true; }
  ((${#aur_opt[@]}))  && { need_packages --aur --optional "${aur_opt[@]}" || true; }
  return 0
}

# append_once FILE MARKER BLOCK — idempotent append for files we do not own.
append_once() {
  local f=$1 marker=$2 block=$3
  if [[ ! -f $f ]]; then
    warn "$f does not exist — skipping"
    return 1
  fi
  if grep -qF -- "$marker" "$f"; then
    ok "$f already wired up"
    return 0
  fi
  if dry; then changed "would append to $f"; return 0; fi
  printf '%s\n' "$block" >>"$f" && changed "$f (appended)"
}

# insert_once FILE MARKER ANCHOR BLOCK — idempotent insert BEFORE the first
# line containing ANCHOR.
#
# Needed because ~/.bashrc returns early for non-interactive shells:
#
#     [[ $- != *i* ]] && return
#
# Anything appended below that line is invisible to scripts, editor tasks and
# hooks. Environment that must apply everywhere has to go above it, so this
# inserts rather than appends. Refuses, with instructions, if the anchor is
# missing — guessing a position in someone's shell config is worse than asking.
# ANCHOR is a FIXED STRING, matched with index() — never a regex. A regex here
# has to survive both grep and awk, whose escaping rules differ: `\[\[ \$- !=
# \*i\* \]\]` is a valid ERE but an invalid awk regex, and awk dies on it. It
# died *after* the redirect had already truncated the target, destroying the
# file. Hence also: build into a temp, sanity-check, and only then move it.
insert_once() {
  local f=$1 marker=$2 anchor=$3 block=$4 bak tmp out
  if [[ ! -f $f ]]; then
    warn "$f does not exist — skipping"
    return 1
  fi
  if grep -qF -- "$marker" "$f"; then
    ok "$f already sources it above the guard"
    return 0
  fi
  if ! grep -qF -- "$anchor" "$f"; then
    warn "$f has no interactive guard to insert above"
    note "add this near the top of $f yourself:"
    printf '%s\n' "$block" | sed 's/^/           /'
    return 1
  fi
  if dry; then
    changed "would insert into $f, above the interactive guard"
    return 0
  fi

  bak="$f.bak.$(date +%s)"
  cp -a -- "$f" "$bak" || { fail "could not back up $f"; return 1; }
  tmp=$(mktemp); out=$(mktemp)
  printf '%s\n' "$block" >"$tmp"
  if ! awk -v blk="$tmp" -v anc="$anchor" '
        !ins && index($0, anc) { while ((getline l < blk) > 0) print l; close(blk); ins = 1 }
        { print }
        END { exit(ins ? 0 : 1) }
      ' "$f" >"$out"; then
    rm -f -- "$tmp" "$out"
    fail "could not insert into $f (unchanged; backup at $bak)"
    return 1
  fi
  # Never move a result that lost content: a failed filter must not eat the file.
  if [[ ! -s $out ]] || (($(wc -l <"$out") < $(wc -l <"$f"))); then
    rm -f -- "$tmp" "$out"
    fail "refusing to write a shorter $f (unchanged; backup at $bak)"
    return 1
  fi
  mv -- "$out" "$f"
  rm -f -- "$tmp"
  drop_backup_if_same "$bak" "$f"
  changed "$f (inserted above the interactive guard)"
}

# State that belongs to the machine, not the repo: which container engine is
# selected, and anything else a toggle script flips.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-overlay"

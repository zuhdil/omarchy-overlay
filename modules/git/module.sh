# desc: git log aliases, enforced commit/tag signing, GitHub SSH and GPG keys
#
# Omarchy seeds ~/.config/git/config, so this sets individual keys with
# `git config --global` rather than shipping a file. Replacing it would drop
# Omarchy's defaults and be undone by `omarchy refresh config git/config`.

link_tree "$MODULE_DIR/home"

# git_set KEY VALUE — idempotent, honours --dry-run.
git_set() {
  local key=$1 val=$2 cur
  cur=$(git config --global --get "$key" 2>/dev/null) || cur=
  if [[ $cur == "$val" ]]; then
    ok "git $key"
  elif dry; then
    changed "would set git $key${cur:+ (was: $cur)}"
  elif git config --global "$key" "$val"; then
    changed "git $key"
  else
    fail "could not set git $key"
  fi
}

# --- log aliases --------------------------------------------------------------

# `lg` is a pure format string. `%d` is empty without refs, so `%h - %d %s`
# leaves the two spaces seen before a decorated subject.
git_set alias.lg "log --graph --abbrev-commit --decorate --format=format:'%C(red)%h%C(reset) - %C(auto)%d%C(reset) %s %C(green)(%ar)%C(reset) %C(blue)<%an>%C(reset)'"

# `lgs` resolves to the git-log-signed subcommand symlinked into ~/.local/bin.
# git cannot colour or map `%G?` in a format string, so that lives in a script.
git_set alias.lgs "log-signed"

# External subcommands are not paged by default, so `lgs` would scroll past
# where `git log` would stop. Keyed on the resolved command, which covers the
# alias too.
git_set pager.log-signed true

# --- global ignores -----------------------------------------------------------

# Git reads $XDG_CONFIG_HOME/git/ignore by default, so no core.excludesFile is
# needed. `.tmp-commit-msg` is the scratch file used to write commit messages;
# it was committed eight times here because `git add -A` ran while it still
# existed, so ignoring it globally is cheaper than remembering not to stage it.
ignore=${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore
ignore_line='.tmp-commit-msg'

if [[ -f $ignore ]] && grep -qFx -- "$ignore_line" "$ignore"; then
  ok "$ignore already ignores $ignore_line"
elif dry; then
  if [[ -f $ignore ]]; then
    changed "would add $ignore_line to $ignore"
  else
    changed "would create $ignore with $ignore_line"
  fi
elif mkdir -p -- "$(dirname -- "$ignore")" &&
  printf '%s\n' "$ignore_line" >>"$ignore"; then
  changed "$ignore ignores $ignore_line"
else
  fail "could not write $ignore"
fi

# --- signing ------------------------------------------------------------------

git_set commit.gpgsign true
git_set tag.gpgsign true

# Signing needs a terminal to prompt on where pinentry has no GUI to use. That
# is `GPG_TTY`, set by the shell module's rc.sh — interactive-only, since
# `$(tty)` means nothing without a terminal.

# ask_identity KEY LABEL [REGEX] — prompt for a git identity field and set it.
# Only called with a terminal present.
ask_identity() {
  local key=$1 label=$2 pattern=${3:-} val i
  for i in 1 2 3; do
    read -r -p "         $label: " val || return 1
    val=${val#"${val%%[![:space:]]*}"}
    val=${val%"${val##*[![:space:]]}"}
    if [[ -z $val ]]; then
      warn "$label cannot be empty"
    elif [[ -n $pattern && ! $val =~ $pattern ]]; then
      warn "that does not look like an email address"
    elif git config --global "$key" "$val"; then
      changed "git $key = $val"
      return 0
    else
      fail "could not set git $key"
      return 1
    fi
  done
  warn "giving up on $label after three attempts"
  return 1
}

# git_identity KEY LABEL [REGEX] — read a field into GIT_IDENTITY, asking for
# it when unset. The result comes back in a variable rather than on stdout:
# this function also reports, and a `note` on stdout would otherwise be captured
# as the value.
#
# `--global` reads exactly one file, and ~/.gitconfig shadows
# $XDG_CONFIG_HOME/git/config when both exist, so an identity Omarchy seeded
# into the XDG file would read as unset. Fall back to full resolution — what git
# itself uses when committing — before concluding anything is missing.
#
# Asking rather than skipping: the email selects the signing key and names every
# commit, so without it this module can neither sign nor identify what it
# configures.
GIT_IDENTITY=""
git_identity() {
  local key=$1 label=$2 pattern=${3:-} val
  GIT_IDENTITY=""

  val=$(git config --global --get "$key" 2>/dev/null) || val=
  if [[ -z $val ]]; then
    val=$(git config --get "$key" 2>/dev/null) || val=
    [[ -n $val ]] && note "$key came from outside the global file ($val)"
  fi
  if [[ -n $val ]]; then
    GIT_IDENTITY=$val
    return 0
  fi

  if dry; then
    changed "would prompt for git $key"
    return 1
  fi
  if [[ ! -t 0 ]]; then
    warn "git $key is unset, and there is no terminal to ask on"
    note "set it with: git config --global $key <value>"
    return 1
  fi
  ask_identity "$key" "$label" "$pattern" || return 1
  GIT_IDENTITY=$(git config --global --get "$key")
}

git_identity user.email "your email" '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
email=$GIT_IDENTITY
git_identity user.name "your name"
name=$GIT_IDENTITY

if [[ -z $email ]]; then
  warn "no user.email — skipping signing key setup"
elif ! command -v gpg >/dev/null; then
  skip "gpg not installed"
else
  # Machine-specific, so derived from the local keyring rather than committed:
  # another machine has another key. Skips keys that cannot sign — no `S` among
  # the capabilities, which is the aggregate over subkeys — and keys that are
  # expired, revoked, disabled or invalid. An old key left in the keyring would
  # otherwise be picked first, and every commit would fail to sign.
  fpr=$(gpg --list-secret-keys --with-colons "$email" 2>/dev/null | awk -F: '
    /^sec:/ { usable = ($2 !~ /^[erdi]$/) && ($12 ~ /S/); next }
    /^fpr:/ && usable { print $10; exit }
  ')
  # Generate one rather than explaining how to. Signing is enabled just above,
  # so a machine without a key cannot commit at all — printing instructions
  # leaves the module having broken git rather than configured it. pinentry
  # prompts for the passphrase, so this needs a terminal; a key is an identity
  # and should not be created silently or without one.
  if [[ -z $fpr ]] && dry; then
    changed "would generate an ed25519 signing key for $email"
  elif [[ -z $fpr ]] && [[ ! -t 0 ]]; then
    warn "no usable GPG signing key for $email, and no terminal to create one"
    note "run: gpg --quick-generate-key \"$email\" ed25519 sign 2y"
    note "signing is enabled, so commits will fail until a key exists"
  elif [[ -z $fpr ]]; then
    name=$(git config --get user.name 2>/dev/null) || name=
    note "no GPG signing key for $email — generating one (pinentry will ask for a passphrase)"
    if gpg --quick-generate-key "${name:+$name }<$email>" ed25519 sign 2y; then
      fpr=$(gpg --list-secret-keys --with-colons "$email" 2>/dev/null | awk -F: '
        /^sec:/ { usable = ($2 !~ /^[erdi]$/) && ($12 ~ /S/); next }
        /^fpr:/ && usable { print $10; exit }
      ')
      [[ -n $fpr ]] && changed "generated GPG key ${fpr: -16}" ||
        fail "key generated but no usable signing key found afterwards"
    else
      fail "gpg key generation failed"
    fi
  fi
  [[ -n ${fpr:-} ]] && git_set user.signingkey "$fpr"
fi

# --- GitHub keys --------------------------------------------------------------

# Find what there is to upload before touching authentication. Logging in to
# push nothing would interrupt a run for no reason.
ssh_pub=""
for f in "$HOME"/.ssh/id_ed25519.pub "$HOME"/.ssh/id_rsa.pub "$HOME"/.ssh/*.pub; do
  [[ -r $f ]] && { ssh_pub=$f; break; }
done

# Same reasoning as the GPG key: generate rather than instruct. ssh-keygen
# prompts for a passphrase, so this needs a terminal too.
if [[ -z $ssh_pub ]] && dry; then
  changed "would generate ~/.ssh/id_ed25519"
elif [[ -z $ssh_pub ]] && [[ -t 0 ]] && command -v ssh-keygen >/dev/null; then
  note "no SSH key — generating ~/.ssh/id_ed25519"
  mkdir -p -m 700 "$HOME/.ssh"
  if ssh-keygen -t ed25519 -C "${email:-$USER@$(uname -n)}" -f "$HOME/.ssh/id_ed25519"; then
    ssh_pub=$HOME/.ssh/id_ed25519.pub
    changed "generated $ssh_pub"
  else
    fail "ssh-keygen failed"
  fi
elif [[ -z $ssh_pub ]] && ! command -v ssh-keygen >/dev/null; then
  warn "no SSH key and ssh-keygen is not installed"
elif [[ -z $ssh_pub ]]; then
  warn "no SSH key, and no terminal to create one"
  note "run: ssh-keygen -t ed25519 -C \"${email:-your@email}\""
fi

# Uploading needs these; a token predating this module may carry neither.
gh_scopes=(admin:public_key admin:gpg_key)

# gh_ready — true when gh can upload keys. Logs in or widens scopes when it
# cannot, rather than printing a command and skipping: on a fresh machine this
# step is never authenticated, so reporting alone would make it useless exactly
# where it is needed. Both actions open a browser, so both need a terminal.
gh_ready() {
  local missing=() sc args=()

  if ! gh auth status >/dev/null 2>&1; then
    if dry; then
      changed "would run gh auth login (opens a browser)"
      return 1
    elif [[ ! -t 0 ]]; then
      warn "gh is not authenticated, and there is no terminal to log in from"
      note "run: gh auth login -s ${gh_scopes[*]}"
      return 1
    fi
    note "gh is not authenticated — opening a browser to log in"
    for sc in "${gh_scopes[@]}"; do args+=(-s "$sc"); done
    if ! gh auth login "${args[@]}"; then
      warn "gh auth login did not complete — GitHub keys not checked"
      return 1
    fi
    changed "authenticated with gh"
  fi

  # Authenticated, but possibly without the scopes the uploads need.
  sc=$(gh auth status 2>&1 | sed -n "s/.*Token scopes: //p" | tr -d "'")
  [[ $sc == *admin:public_key* ]] || missing+=(admin:public_key)
  [[ $sc == *gpg_key* ]] || missing+=(admin:gpg_key)
  ((${#missing[@]})) || return 0

  if dry; then
    changed "would request gh scopes: ${missing[*]}"
    return 1
  elif [[ ! -t 0 ]]; then
    warn "gh token lacks: ${missing[*]}"
    note "run: gh auth refresh -s $(IFS=,; echo "${missing[*]}")"
    return 1
  fi
  note "widening gh scopes: ${missing[*]}"
  args=()
  for sc in "${missing[@]}"; do args+=(-s "$sc"); done
  gh auth refresh "${args[@]}" && changed "gh scopes widened" && return 0
  warn "could not widen gh scopes — GitHub keys not checked"
  return 1
}

if ! command -v gh >/dev/null; then
  skip "gh not installed — GitHub keys not checked"
elif [[ -z $ssh_pub && -z ${fpr:-} ]]; then
  skip "no SSH or GPG key on this machine to upload"
elif ! gh_ready; then
  : # gh_ready already reported why
else
  # SSH. Compared on the key material, not the title: the same key uploaded
  # under a different name is still the same key.
  if [[ -z $ssh_pub ]]; then
    skip "no SSH public key in ~/.ssh"
    note "create one with: ssh-keygen -t ed25519 -C \"$email\""
  else
    material=$(awk '{print $2}' "$ssh_pub")
    if gh ssh-key list 2>/dev/null | grep -qF -- "$material"; then
      ok "SSH key already on GitHub ($(basename "$ssh_pub"))"
    elif dry; then
      changed "would upload $ssh_pub to GitHub"
    elif gh ssh-key add "$ssh_pub" --title "${HOSTNAME:-$(uname -n)}" >/dev/null 2>&1; then
      changed "uploaded $ssh_pub to GitHub"
    else
      fail "could not upload $ssh_pub"
    fi
  fi

  # GPG. `gh gpg-key list` reports the long key ID, which is the last 16
  # characters of the fingerprint.
  if [[ -n ${fpr:-} ]]; then
    if gh gpg-key list 2>/dev/null | grep -qF -- "${fpr: -16}"; then
      ok "GPG key already on GitHub (${fpr: -16})"
    elif dry; then
      changed "would upload GPG key ${fpr: -16} to GitHub"
    elif gpg --armor --export "$fpr" | gh gpg-key add - >/dev/null 2>&1; then
      changed "uploaded GPG key ${fpr: -16} to GitHub"
    else
      fail "could not upload GPG key ${fpr: -16}"
    fi
  fi
fi

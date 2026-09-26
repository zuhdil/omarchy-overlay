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

# --- signing ------------------------------------------------------------------

git_set commit.gpgsign true
git_set tag.gpgsign true

# The signing key is machine-specific: another machine has another key, so it is
# derived from the local keyring rather than committed. Matched on the configured
# email, skipping keys that cannot sign (no `S` among the capabilities, which
# covers the aggregate over subkeys) and keys that are expired, revoked,
# disabled or invalid — an old key left in the keyring would otherwise be
# picked first and every commit would fail.
email=$(git config --global --get user.email 2>/dev/null) || email=
if [[ -z $email ]]; then
  warn "git user.email is unset — cannot pick a signing key"
  note "set it with: git config --global user.email <you@example.com>"
elif ! command -v gpg >/dev/null; then
  skip "gpg not installed"
else
  fpr=$(gpg --list-secret-keys --with-colons "$email" 2>/dev/null | awk -F: '
    /^sec:/ { usable = ($2 !~ /^[erdi]$/) && ($12 ~ /S/); next }
    /^fpr:/ && usable { print $10; exit }
  ')
  if [[ -z $fpr ]]; then
    warn "no usable GPG signing key for $email"
    note "create one with: gpg --full-generate-key  (ed25519 is a good default)"
    note "signing is enabled, so commits will fail until a key exists"
  else
    git_set user.signingkey "$fpr"
  fi
fi

# --- GitHub keys --------------------------------------------------------------

if ! command -v gh >/dev/null; then
  skip "gh not installed — GitHub keys not checked"
elif ! gh auth status >/dev/null 2>&1; then
  warn "gh is not authenticated — GitHub keys not checked"
  note "run: gh auth login"
else
  # SSH. Compared on the key material, not the title: the same key uploaded
  # under a different name is still the same key.
  ssh_pub=""
  for f in "$HOME"/.ssh/id_ed25519.pub "$HOME"/.ssh/id_rsa.pub "$HOME"/.ssh/*.pub; do
    [[ -r $f ]] && { ssh_pub=$f; break; }
  done
  if [[ -z $ssh_pub ]]; then
    warn "no SSH public key in ~/.ssh"
    note "create one with: ssh-keygen -t ed25519 -C \"$email\""
  else
    material=$(awk '{print $2}' "$ssh_pub")
    if gh ssh-key list 2>/dev/null | grep -qF -- "$material"; then
      ok "SSH key already on GitHub ($(basename "$ssh_pub"))"
    elif dry; then
      changed "would upload $ssh_pub to GitHub"
    elif gh ssh-key add "$ssh_pub" --title "$(hostname)" >/dev/null 2>&1; then
      changed "uploaded $ssh_pub to GitHub"
    else
      warn "could not upload $ssh_pub"
      note "gh may need the scope: gh auth refresh -h github.com -s admin:public_key"
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
      warn "could not upload GPG key ${fpr: -16}"
      note "gh may need the scope: gh auth refresh -h github.com -s write:gpg_key"
    fi
  fi
fi

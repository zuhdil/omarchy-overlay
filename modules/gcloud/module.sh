# desc: gcloud CLI with a `work` and a personal (`default`) configuration, switched by gcwork/gcpersonal

link_tree "$MODULE_DIR/home"
copy_tree "$MODULE_DIR/system"

if ! command -v gcloud >/dev/null; then
  skip "gcloud not installed — configurations not checked"
  return 0
fi

# The pacman hook compiles the completion table on every upgrade; this covers
# an install that predates the hook.
table=/opt/google-cloud-cli/data/cli/gcloud_completions.py
pyc=$(/usr/bin/python -c 'import importlib.util, sys; print(importlib.util.cache_from_source(sys.argv[1]))' "$table")
if [[ $pyc -nt $table ]]; then
  ok "gcloud completion table compiled"
elif dry; then
  changed "would compile gcloud completion table"
elif root_available "compiling the gcloud completion table"; then
  sudo /usr/bin/python -m compileall -q "${table%/*}" &&
    changed "gcloud completion table compiled" ||
    fail "could not compile $table"
fi

# --no-activate, so a re-run never switches the account in use.
if gcloud config configurations describe work &>/dev/null; then
  ok "gcloud configuration: work"
elif dry; then
  changed "would create gcloud configuration: work"
elif gcloud config configurations create work --no-activate &>/dev/null; then
  changed "gcloud configuration: work"
else
  fail "could not create gcloud configuration: work"
fi

# Logging in needs a terminal for the pasted code and the project prompts, so
# without one it is left to the user. init activates the configuration it set
# up, even with --configuration, so the one in use is put back afterwards.
active=$(gcloud config configurations list --filter=is_active=true --format='value(name)' 2>/dev/null)
for conf in default work; do
  gcloud config configurations describe "$conf" &>/dev/null || continue
  account=$(gcloud config get account --configuration="$conf" 2>/dev/null)
  init=(gcloud init --no-launch-browser --skip-diagnostics --configuration="$conf")
  if [[ -n $account ]]; then
    ok "gcloud $conf: $account"
  elif dry || [[ ! -t 0 ]]; then
    note "gcloud $conf has no account; log in with: ${init[*]}"
  else
    # --configuration does not skip init's menu; [1] is that configuration.
    note "logging in gcloud $conf: pick [1], then sign in with the $conf account"
    if "${init[@]}" && account=$(gcloud config get account --configuration="$conf" 2>/dev/null) && [[ -n $account ]]; then
      changed "gcloud $conf: $account"
    else
      warn "gcloud $conf still has no account"
    fi
  fi
done
now=$(gcloud config configurations list --filter=is_active=true --format='value(name)' 2>/dev/null)
if [[ -n $active && $now != "$active" ]]; then
  gcloud config configurations activate "$active" &>/dev/null &&
    note "gcloud configuration $active is active again" ||
    warn "could not re-activate gcloud configuration $active (now: $now)"
fi

# desc: hibernate that actually resumes, plus lid/idle/battery triggers
#
# Background, and why each change exists: docs/hibernation.md
#
# Nothing machine-specific is copied from the repo. The swapfile's resume_offset
# and the NVIDIA decision are derived here, because another machine's offset —
# or the hybrid rule applied to an NVIDIA-only box — yields a system that boots
# fine and silently never resumes.

# --- machine-specific prerequisites -------------------------------------------

# omarchy-hibernation-setup creates the swap subvolume, the swapfile sized to
# RAM, the fstab entry and the resume=/resume_offset= kernel parameters. All
# per-machine, so let it generate them rather than shipping ours.
if [[ ! -f /etc/mkinitcpio.conf.d/omarchy_resume.conf ]]; then
  warn "hibernation storage is not set up on this machine"
  note "run: omarchy hibernation setup"
  note "then re-run this installer — it creates the swapfile and resume= params,"
  note "which are machine-specific and must never come from the repo."
  return 0 2>/dev/null || exit 0
fi
# That file only proves `omarchy hibernation setup` ran at some point. The
# storage it describes can be removed or recreated afterwards, so report what is
# actually true rather than claiming more than was checked. Neither is fatal —
# the rest of the module still applies — and hibernation-check does the deeper
# verification, including whether the offset still matches the swapfile.
if awk '!/Filename|zram/ { found = 1 } END { exit !found }' /proc/swaps; then
  ok "disk swap is active"
else
  warn "no non-zram swap is active — nothing can hold a hibernation image"
  note "re-run: omarchy hibernation setup"
fi

if grep -q 'resume=' /proc/cmdline; then
  ok "resume= is on the kernel cmdline"
else
  warn "resume= is missing from the running kernel cmdline"
  note "expected after 'omarchy hibernation setup' and a reboot"
fi

# --- resume hook ordering -----------------------------------------------------

# Only a change to what goes INTO the initramfs justifies rebuilding it.
# Symlinking a hypridle config must not cost a two-minute UKI rebuild.
INITRAMFS_DIRTY=0
MODULE_BEFORE=$CHANGED
_before=$CHANGED

# Upstream's managed drop-in (PR #8888) supersedes our fix; leave it alone.
if grep -qFx '# omarchy:resume-hook' /etc/mkinitcpio.conf.d/omarchy_resume.conf 2>/dev/null; then
  skip "omarchy_resume.conf is upstream's managed version"
else
  copy_system "$MODULE_DIR/conditional/omarchy_resume.conf" \
    /etc/mkinitcpio.conf.d/omarchy_resume.conf 644
fi
((CHANGED != _before)) && INITRAMFS_DIRTY=1
_before=$CHANGED

# --- NVIDIA in the initramfs --------------------------------------------------

# Only a defect on hybrid machines. Where NVIDIA owns every display controller
# it IS the early KMS and must stay — omarchy_hooks.conf drops the kms hook to
# suit. omarchy-hw-hybrid-gpu is Omarchy's own predicate, so this agrees with it.
nv_conf=/etc/mkinitcpio.conf.d/nvidia.conf
if [[ ! -f $nv_conf ]]; then
  skip "no nvidia.conf on this machine"
elif ! command -v omarchy-hw-hybrid-gpu >/dev/null; then
  warn "cannot determine the GPU layout; leaving $nv_conf alone"
elif ! omarchy-hw-hybrid-gpu; then
  skip "not a hybrid GPU system — an early NVIDIA load is correct here"
elif ! grep -qE '^[[:space:]]*MODULES\+?=.*nvidia' "$nv_conf"; then
  ok "$nv_conf (no active NVIDIA MODULES line)"
elif dry; then
  changed "$nv_conf (would comment out the NVIDIA MODULES line)"
elif ! root_available "$nv_conf"; then
  : # already reported
else
  bak="$nv_conf.bak.$(date +%s)"
  sudo cp -a "$nv_conf" "$bak" && note "backup: $bak"
  # Edited in place, not replaced: another machine's nvidia.conf may differ.
  sudo sed -i -E \
    's|^([[:space:]]*MODULES\+?=.*nvidia.*)$|# Commented out: early NVIDIA load breaks resume on hybrid systems.\n# \1|' \
    "$nv_conf" && changed "$nv_conf (NVIDIA commented out)" || fail "could not edit $nv_conf"
fi
((CHANGED != _before)) && INITRAMFS_DIRTY=1

# --- sleep policy and the checker ---------------------------------------------

copy_tree "$MODULE_DIR/system"
link_tree "$MODULE_DIR/home"

# --- critical battery ---------------------------------------------------------

# UPower.conf is package-owned: edit the keys so a future .pacnew still carries
# everything else. Never replace the whole file.
up=/etc/UPower/UPower.conf
if [[ ! -f $up ]]; then
  skip "upower not installed"
else
  for kv in CriticalPowerAction=Hibernate PercentageCritical=10.0 PercentageAction=5.0; do
    k=${kv%%=*} v=${kv#*=}
    cur=$(grep -E "^$k=" "$up" | cut -d= -f2)
    if [[ $cur == "$v" ]]; then
      ok "$k=$v"
    elif [[ -z $cur ]]; then
      warn "$k is not present in $up — not adding it blindly"
    elif dry; then
      changed "would set $k: $cur -> $v"
    elif ! root_available "$up ($k)"; then
      : # already reported
    else
      sudo sed -i "s|^$k=.*|$k=$v|" "$up" && changed "$k: $cur -> $v"
    fi
  done
fi

# --- NVIDIA sleep services ----------------------------------------------------

if systemctl list-unit-files nvidia-suspend-then-hibernate.service --no-legend 2>/dev/null | grep -q .; then
  for u in nvidia-suspend nvidia-hibernate nvidia-resume nvidia-suspend-then-hibernate; do
    if [[ $(systemctl is-enabled "$u.service" 2>/dev/null) == enabled ]]; then
      ok "$u.service"
    elif dry; then
      changed "would enable $u.service"
    elif ! root_available "$u.service"; then
      : # already reported
    else
      sudo systemctl enable "$u.service" >/dev/null 2>&1 &&
        changed "$u.service enabled" || warn "could not enable $u.service"
    fi
  done
else
  skip "no NVIDIA sleep units (driver not installed)"
fi

# --- idle trigger -------------------------------------------------------------

# autostart.lua is Omarchy-managed: `omarchy refresh hyprland` rewrites it, so
# append rather than symlinking the whole file.
append_once "$HOME/.config/hypr/autostart.lua" 'hypridle' '
-- Hibernate after the timeout in ~/.config/hypr/hypridle.conf. Omarchy'"'"'s shell
-- idle service only covers the screensaver and lock; hypridle adds the longer
-- hibernate timeout. Guarded so the config stays valid without hypridle.
if o.cmd_present("hypridle") then
  o.launch_on_start("hypridle")
end'

# --- apply --------------------------------------------------------------------

if ((INITRAMFS_DIRTY)) && dry; then
  # A two-minute UKI rebuild and a reboot are the most consequential thing this
  # module does. --dry-run promises the full picture, so say so here too.
  changed "would rebuild the initramfs (~2 min), then a reboot is needed"
elif ((INITRAMFS_DIRTY)); then
  if ! root_available "the initramfs rebuild"; then
    :  # already reported; the config is staged but not yet built
  elif command -v limine-mkinitcpio >/dev/null; then
    note "rebuilding the initramfs..."
    sudo bash -c 'echo "usr/lib/modules/$(uname -r)/modules.builtin" |
      /usr/share/libalpm/scripts/limine-mkinitcpio-install' >/dev/null 2>&1 &&
      changed "initramfs rebuilt" || fail "initramfs rebuild failed — run it by hand"
  else
    warn "not a limine-mkinitcpio system; rebuild the initramfs yourself"
  fi
  note "reboot before testing hibernate: resume runs from the booting kernel's initramfs"
fi

# Policy files are picked up by a reload, which is cheap and unrelated to the
# initramfs. Only when this module actually changed something: restarting upower
# drops the power daemon for a moment, and a run that reports all-ok has no
# reason to do that.
if ((CHANGED != MODULE_BEFORE)) && ((HAVE_SUDO)) && ! dry; then
  sudo systemctl reload systemd-logind 2>/dev/null
  sudo systemctl restart upower 2>/dev/null
fi

note "verify with: sudo hibernation-check"

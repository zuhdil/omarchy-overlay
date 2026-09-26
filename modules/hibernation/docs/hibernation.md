# Hibernation setup — Omarchy T480

System: ThinkPad T480, Intel UHD 620 + NVIDIA MX150, LUKS + btrfs, Limine UKI.
Omarchy 4.0.3-1, kernel 7.2.3-arch1-3. Done 2026-09-13/14.

Hibernate wrote its image fine but never resumed. Two defects caused it; steps
1–3 fix them, steps 4–8 add automatic hibernation.

**The `hibernation` module applies all of this.** `./install hibernation` from
the repo root does steps 1–8 and installs the checker and the post-update hook.
The steps below are kept as the reasoning behind each change — read them to
understand or repair, not to apply by hand.

---

## 1. Remove NVIDIA from the initramfs

Early-loaded NVIDIA returns `-5` from `nv_pmops_freeze` during resume (it needs
`/var/tmp` for `NVreg_PreserveVideoMemoryAllocations`, absent that early), so the
kernel aborts at ~90% image load. The Intel iGPU drives the display and the `kms`
hook covers early KMS, so the dGPU is not needed in the initramfs.

`/etc/mkinitcpio.conf.d/nvidia.conf` holds exactly one active line. Comment it
out so the file contributes nothing:

```sh
# Original line (restore only if the display breaks at the LUKS prompt):
# MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
```

The file is then entirely comments — `MODULES` is empty after sourcing it. The
copy on this machine keeps a longer comment above recording the failure and the
reasoning; only the commented-out `MODULES+=` line matters functionally.

NVIDIA now loads via udev after root is mounted. `nvidia_drm modeset=1` comes
from `/etc/modprobe.d/nvidia.conf`, so Wayland is unaffected.

## 2. Fix the resume hook position

`omarchy-hibernation-setup` writes `HOOKS+=(resume)`, which appends *after*
`filesystems`/`fsck` — root is mounted rw before the image is restored, risking
btrfs corruption. `resume` must sit between `encrypt` and `filesystems`.

Keep the literal `HOOKS+=(resume)` line: `omarchy-hibernation-setup` and
`omarchy-hibernation-remove` both detect hibernation by grepping
`^HOOKS+=(resume)$`, and upstream's migration uses it to replace this file.

`/etc/mkinitcpio.conf.d/omarchy_resume.conf`:

```sh
HOOKS+=(resume)

_omarchy_resume_hooks=()
_omarchy_resume_added=0
for _omarchy_resume_hook in "${HOOKS[@]}"; do
  [[ $_omarchy_resume_hook == "resume" ]] && continue
  if [[ $_omarchy_resume_hook == "filesystems" && $_omarchy_resume_added -eq 0 ]]; then
    _omarchy_resume_hooks+=(resume)
    _omarchy_resume_added=1
  fi
  _omarchy_resume_hooks+=("$_omarchy_resume_hook")
done
((_omarchy_resume_added)) || _omarchy_resume_hooks+=(resume)
HOOKS=("${_omarchy_resume_hooks[@]}")
unset _omarchy_resume_hooks _omarchy_resume_added _omarchy_resume_hook
```

## 3. Rebuild the UKI

`mkinitcpio -P` does nothing here — `/etc/mkinitcpio.d/` is empty. The UKI is
built by `limine-mkinitcpio-install`, which pacman normally runs from a hook and
which reads its kernel targets from **stdin**. It must run as root.

Put the pipeline *inside* the elevated shell:

```sh
sudo bash -c 'echo "usr/lib/modules/$(uname -r)/modules.builtin" \
  | /usr/share/libalpm/scripts/limine-mkinitcpio-install'
```

Do **not** pipe into `sudo` directly (`echo … | sudo script`). The pipe takes
sudo's stdin, so with no controlling TTY it fails with *"a terminal is required
to read the password"* — which is what happens from a script, a non-interactive
shell, or an agent session. It only works when run by hand in a terminal window.

Equivalent, if you prefer letting pacman drive the same hooks:

```sh
sudo pacman -S linux
```

The rebuild prints its hooks as it runs them; expect
`… [encrypt] [resume] [filesystems] …` and the UKI to shrink (330 MB → 160 MB).

Verify before rebooting.

**Resolved hook order** — that build output scrolls past, and the image itself
records only the raw config lines (`lsinitcpio -c`), never the resolved array. So
check the configs. No sudo needed, the drop-ins are world-readable:

```sh
bash -c 'HOOKS=(); . /etc/mkinitcpio.conf
  for f in /etc/mkinitcpio.conf.d/*.conf; do . "$f"; done
  printf "%s\n" "${HOOKS[*]}"'
```

Expect `… block encrypt resume filesystems fsck btrfs-overlayfs`.

**What landed in the image** — one elevated shell, since `/boot` is root-only:

More than one UKI can live in `/boot/EFI/Linux/`. This machine has two because
two kernels are installed — `linux` builds `omarchy_linux.efi` and
`linux-omarchy` builds `omarchy_linux-omarchy.efi`. Neither is leftover: the
Arch one is the fallback to boot if a `linux-omarchy` upgrade ever does not, and
both pick up the resume fix, since they share `/etc/mkinitcpio.conf.d/`.

Only the UKI whose `.uname` section matches `uname -r` is the image in use, so
select it rather than taking the first the glob returns:

```sh
sudo bash -c '
  for u in /boot/EFI/Linux/*.efi; do
    objcopy --dump-section .uname=/tmp/un "$u" /tmp/discard 2>/dev/null
    [[ $(tr -d "\0" </tmp/un) == $(uname -r) ]] && UKI=$u
  done
  echo "checking $UKI"
  objcopy --dump-section .initrd=/tmp/i.img "$UKI" /tmp/discard
  lsinitcpio /tmp/i.img | grep -E "hooks/(encrypt|resume)$"
  lsinitcpio /tmp/i.img | grep -E "\.ko(\.zst)?$" | grep -iE "nvidia|nouveau|i915"
  rm -f /tmp/i.img /tmp/discard /tmp/un'
```

The output file must be created by **root**, inside the elevated shell as above.
Handing root a path you created yourself (`img=$(mktemp); sudo objcopy … "$img"`)
fails with *"Permission denied"*: `/tmp` is world-writable and sticky, and
`fs.protected_regular=1` forbids writing to a file the opener does not own in
such a directory — root included.

Expect `hooks/encrypt` and `hooks/resume`, and GPU modules limited to
`i915.ko.zst`, `nouveau.ko.zst` (blacklisted by `nvidia-580xx-utils.conf`, which
`modconf` bundles, so it never binds) and `hid-nvidia-shield.ko.zst` (a
game-controller HID driver). No `nvidia.ko` means the fix took.

`filesystems` has no runtime hook file — it is build-only, so it never appears in
that listing. Its position is what the first check above confirms.

Once both checks pass, **reboot**. Resume runs from the *booting* kernel's
initramfs, so the new image has to be the one in use before hibernate is worth
testing.

## 4. Lid close → suspend-then-hibernate

`/etc/systemd/logind.conf.d/50-hibernate.conf`:

```ini
[Login]
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend-then-hibernate
```

## 5. Hibernate delay

`/etc/systemd/sleep.conf.d/50-hibernate-delay.conf`:

```ini
[Sleep]
HibernateDelaySec=30min
```

## 6. NVIDIA suspend-then-hibernate hook

All four NVIDIA sleep units matter: the suspend/hibernate/resume trio saves and
restores video memory, and the fourth covers the combined transition.

```sh
sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service \
  nvidia-resume.service nvidia-suspend-then-hibernate.service
sudo systemctl reload systemd-logind
```

A `nvidia-580xx-utils` upgrade can reapply its preset and disable them again,
which is why the checker tests all four.

## 7. Critical battery → hibernate

`/etc/UPower/UPower.conf`:

```ini
PercentageLow=20.0
PercentageCritical=10.0
PercentageAction=5.0
CriticalPowerAction=Hibernate
```

```sh
sudo systemctl restart upower
```

## 8. Idle → hibernate

Omarchy's shell idle service only supports `screensaver` and `lock`. `hypridle`
supplies the hibernate timeout; both use the Wayland idle-notify protocol and
coexist.

```sh
omarchy pkg add hypridle
```

`~/.config/hypr/hypridle.conf`:

```
general {
    ignore_dbus_inhibit = false
    lock_cmd =
}

listener {
    timeout = 1800
    on-timeout = systemctl hibernate
}
```

Append to `~/.config/hypr/autostart.lua`:

```lua
if o.cmd_present("hypridle") then
  o.launch_on_start("hypridle")
end
```

Validate with `hyprctl reload && hyprctl configerrors`.

---

## Verifying a resume

Compare `/proc/sys/kernel/random/boot_id` before and after: unchanged means a
true resume, changed means it rebooted instead. A marker file in `/tmp` is a
second signal — tmpfs survives hibernation and is wiped by a reboot.

### Cycles on record

From `journalctl`, all four hibernation events on this machine:

| When | Kind | Hibernated | Result |
| --- | --- | --- | --- |
| 09-13 13:31 | manual, **before the fix** | — | **failed** — `nv_pmops_freeze -5` at 90% image load, cold-booted |
| 09-13 14:14 | manual, after steps 1–3 | 1m42s | resumed |
| 09-13 15:18 | lid close → suspend-then-hibernate | 2m03s S3, then 10h26m S4 | resumed |
| 09-14 03:15 | manual, after an `omarchy update` | 31m35s | resumed |

The first row is the baseline the fix is measured against: same hardware, same
kernel, NVIDIA still in the initramfs. Every cycle after steps 1–3 resumed with
`boot_id` unchanged and `btrfs device stats` clean.

The lid-close row exercised the whole chain — `Lid closed` → `PM: suspend entry
(deep)` → RTC self-wake from S3 → `hibernation entry` → S4 → `hibernation exit`.
It also confirmed this firmware resumes from S4 on lid-open alone, no power
button needed.

## Maintenance — what `omarchy update` can override

`omarchy update` runs: snapshot → pacman upgrade → `omarchy-migrate` →
post-update hook → AUR/mise/orphans. It does **not** re-run the hardware install
scripts, so config only changes via a **migration** or a **package upgrade**.

| File | Risk | Why |
| --- | --- | --- |
| `mkinitcpio.conf.d/nvidia.conf` | Medium | Not touched by update, but any future migration can rewrite it — PR #8263 / #10065 will ship exactly that |
| `mkinitcpio.conf.d/omarchy_resume.conf` | Will be replaced, intentionally | PR #8888's migration detects the `HOOKS+=(resume)` line and installs the managed version |
| `/etc/UPower/UPower.conf` | Low | Package-owned: an upgrade leaves a `.pacnew` rather than overwriting |
| `logind.conf.d/50-hibernate.conf` | Low | Omarchy's own drop-in is `20-inhibit-delay.conf`; no filename collision |
| `sleep.conf.d/50-hibernate-delay.conf` | Low | Omarchy ships nothing in `sleep.conf.d/` |
| `~/.config/hypr/hypridle.conf` | Low | Not managed by Omarchy |
| `~/.config/hypr/autostart.lua` | Low–medium | Omarchy ships a default; `omarchy refresh hyprland` resets it (update does not) |

`install/hardware/nvidia.sh` writes the `MODULES+=(nvidia …)` line from step 1
unconditionally, but it is only invoked by `install/hardware/all.sh` and
`vulkan.sh` — i.e. install, `omarchy reinstall`, or a factory reset.

Migration `1786605598.sh` already *reads* `nvidia.conf` to decide whether `kms`
dropped out. It exits early on hybrid machines and only reads, but it confirms
migrations do inspect this file.

**After any update mentioning NVIDIA, hibernation, or initramfs:**

```sh
sudo hibernation-check
```

That script covers every row above and exits non-zero on failure. With sudo it
runs all 23 checks; without, 19 — the ones needing `/boot` and `btrfs
inspect-internal` are skipped.

It picks the boot image by matching each UKI's `.uname` against `uname -r`. A
kernel change can add a UKI under a new name and leave the old one in place, and
verifying the wrong one would report a healthy image while the one that actually
boots went unexamined. If nothing matches the running kernel, that is itself a
failure rather than a silent fallback.

- `NVIDIA is back in the initramfs MODULES` → redo step 1, then step 3
- `resume hook runs AFTER filesystems` → redo step 2, then step 3

`omarchy-hibernation-available` stays green in both cases — it only checks swap
size and that `omarchy_resume.conf` exists. Do not rely on it.

The script lives at `/usr/local/bin/hibernation-check`, copied there from
`modules/hibernation/system/` by the installer. **Edit the repo copy and re-run
`./install hibernation`** — editing `/usr/local/bin` directly puts a change on
the machine that the repo does not have, and the next install overwrites it.

`system/` is copied rather than symlinked on purpose: this repo is user-writable,
and `sudo hibernation-check` must not execute a file you can rewrite. The
`/usr/local/bin` location matters too — it is on sudo's `secure_path`, while
`~/.local/bin` is not, so a copy there would make plain `sudo hibernation-check`
fail with "command not found".

The script validates configuration, not behavior. After a kernel or NVIDIA driver
upgrade, a real cycle is the only proof — see **Verifying a resume**.

`omarchy_resume.conf` being replaced by #8888's migration is the desired
outcome: it swaps this hand-fix for the maintained one. That is why the literal
`HOOKS+=(resume)` line in step 2 must stay — it is the migration's trigger.

Upstream fixes are open but unmerged: PR #8888 (hook order), PR #8263 and
PR #10065 (NVIDIA initramfs).

### It adapts to other systems

The counts above are for this machine. The script discovers the system's shape
rather than assuming this one, so it is safe to copy to a different box. A check
that does not apply **skips**; it never fails.

| Differs how | What the script does |
| --- | --- |
| **NVIDIA-only GPU** | Early loading NVIDIA is *correct* there — it provides the KMS the iGPU gives us, and `omarchy_hooks.conf` drops the `kms` hook to suit. Step 1's rule is inverted, so the check passes instead of failing. Resume trouble on those systems is upstream #10039, a different defect. |
| **No NVIDIA at all** | The NVIDIA config, image, and sleep-unit checks skip. |
| **Desktop (no lid)** | The lid-close check skips instead of warning. |
| **Swap partition, not a file** | `resume_offset` is not required — only a swapfile needs one. |
| **Non-btrfs swapfile** | The offset comparison skips (`btrfs inspect-internal` does not apply). |
| **systemd-boot, GRUB, plain initramfs** | The boot image is found by searching `/boot`, `/efi` and `/boot/efi` for a UKI, then `initramfs-$(uname -r).img` and `initramfs-linux.img`. A layout it cannot recognise skips. |

The GPU rule is the important one: it uses the same sysfs vendor scan
`omarchy_hooks.conf` performs, so it agrees with Omarchy about when an early
NVIDIA load is a defect and when it is required.

Steps 1–8 themselves are **not** portable — they describe this hybrid laptop.
On different hardware, read them for the reasoning and let the script tell you
which parts apply.

### Running it automatically

`omarchy update` calls `omarchy-hook post-update` after system packages **and**
migrations — exactly where a regression lands, so the module installs a hook
there and the check runs itself.

The hook is `modules/hibernation/home/.config/omarchy/hooks/post-update.d/check-hibernation.hook`,
symlinked into place by `./install hibernation`. It is not reproduced here: a
copy in this file would drift from the one that actually runs, and it already
had. Read it there.

Silent when healthy. On failure it prints into the update log and sends a
critical desktop notification, but exits 0 so the update itself still succeeds.

Unprivileged mode skips the initramfs-contents check, so it cannot catch "config
repaired but the UKI never rebuilt". Migrations do rebuild, so run
`sudo hibernation-check` by hand after a major update to close that gap.

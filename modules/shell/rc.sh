# Interactive shell configuration — sourced BELOW ~/.bashrc's interactive guard.
#
# Aliases, prompt tweaks, completion: things only a human at a terminal needs.
# Anything a script must also see belongs in env.sh instead, or it will silently
# not apply — a non-interactive shell never reaches this file.

# Tell gpg-agent which terminal to prompt on. Arch's /usr/bin/pinentry picks a
# GUI backend when DISPLAY or a Wayland session is present, so this changes
# nothing inside a desktop session. It matters on a TTY login, over SSH, or
# anywhere else without a display, where pinentry falls back to curses or tty
# and signing otherwise fails with "Inappropriate ioctl for device".
#
# Here rather than in env.sh because `$(tty)` is meaningless to a shell that has
# no terminal. The git module exports it too, but only for the length of its own
# run, where it generates a key before this file exists; this is what every
# later shell gets. It governs every gpg passphrase prompt, not just commit
# signing — the git module is merely what makes it matter, by enabling
# commit.gpgsign.
#
# Guarded: with stdin redirected `tty` prints the literal "not a tty" and exits
# 1, and exporting that hands gpg-agent a path it cannot open.
[[ -t 0 ]] && export GPG_TTY=$(tty)

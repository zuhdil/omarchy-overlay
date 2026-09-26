# Route the Docker CLI and Compose at a rootless Podman socket.
# Above any interactive guard in the caller, so scripts and editor tasks get it
# too — not just interactive shells.
export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"

# Podman's Docker-API emulation serves the classic /build endpoint but not
# BuildKit's. With BuildKit on — Docker's default since 23 — `docker build` and
# `docker compose build` hang until interrupted:
#
#   #1 CANCELED
#   ERROR: failed to build: context canceled
#
# Selecting the legacy builder is a property of running against Podman, not
# something to remember per command.
export DOCKER_BUILDKIT=0

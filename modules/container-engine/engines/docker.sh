# Use Docker proper: leave DOCKER_HOST unset so the CLI finds its own default
# socket. Unset rather than omit, so toggling back within a live shell works.
unset DOCKER_HOST

# Real Docker serves BuildKit, so let it use its default builder. Unset for the
# same reason as above: a shell toggled from podman still has it set to 0.
unset DOCKER_BUILDKIT

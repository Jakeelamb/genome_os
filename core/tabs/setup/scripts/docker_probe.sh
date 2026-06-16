#!/usr/bin/env sh
set -e
echo "Docker availability (images are planned per menu labels)."
command -v docker >/dev/null 2>&1 && docker --version || echo "docker: not on PATH"
command -v podman >/dev/null 2>&1 && podman --version || echo "podman: not on PATH (optional)"

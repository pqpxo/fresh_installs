#!/usr/bin/env bash
# Install Docker Engine and Docker Compose on Ubuntu
# Also adds a user to the docker group to run docker without sudo
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/you/repo/main/install-docker.sh | bash -s -- --user sam
#   or
#   wget -qO- https://raw.githubusercontent.com/you/repo/main/install-docker.sh | bash -s -- --user sam
#
# Flags:
#   --user USERNAME    Target user to add to the docker group. Defaults to the invoking non-root user if available, otherwise root.

set -euo pipefail

log() { printf "%s\n" "[install-docker] $*"; }
fail() { printf "%s\n" "[install-docker] ERROR: $*" >&2; exit 1; }

# Require Ubuntu
if [ -r /etc/os-release ]; then
  . /etc/os-release
else
  fail "Cannot read /etc/os-release to detect OS."
fi

if [ "${ID:-}" != "ubuntu" ]; then
  fail "This script is intended for Ubuntu. Detected ID=${ID:-unknown}."
fi

# Parse args
TARGET_USER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --user)
      shift
      TARGET_USER="${1:-}"
      [ -n "$TARGET_USER" ] || fail "Missing value for --user"
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

# Determine target user
if [ -z "$TARGET_USER" ]; then
  if [ "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
  else
    # Fallback to current user
    TARGET_USER="$(id -un)"
  fi
fi

# Ensure we run as root
if [ "$(id -u)" -ne 0 ]; then
  log "Re-executing with sudo..."
  exec sudo -E bash "$0" --user "$TARGET_USER"
fi

log "Detected Ubuntu ${VERSION:-unknown} (${VERSION_CODENAME:-unknown})"
log "Target user for docker group: $TARGET_USER"

export DEBIAN_FRONTEND=noninteractive

# Base packages
log "Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Docker apt repository
log "Configuring Docker apt repository..."
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH="$(dpkg --print-architecture)"
CODENAME="${VERSION_CODENAME:?}"
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

# Install Docker Engine and plugins
log "Installing Docker Engine and Compose plugin..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker if systemd is present
if command -v systemctl >/dev/null 2>&1; then
  log "Enabling and starting Docker service..."
  systemctl enable docker
  systemctl start docker
else
  log "systemctl not found. Skipping service enable and start."
fi

# Provide docker-compose v2 convenience shim so docker-compose works
if ! command -v docker-compose >/dev/null 2>&1; then
  log "Creating docker-compose v2 shim at /usr/local/bin/docker-compose..."
  cat >/usr/local/bin/docker-compose <<'EOF'
#!/usr/bin/env bash
set -e
exec docker compose "$@"
EOF
  chmod +x /usr/local/bin/docker-compose
fi

# Create docker group if missing and add target user
if ! getent group docker >/dev/null 2>&1; then
  log "Creating docker group..."
  groupadd docker
fi

log "Adding user ${TARGET_USER} to docker group..."
usermod -aG docker "$TARGET_USER"

# Try to activate group membership for the current shell when appropriate
CURRENT_USER="${SUDO_USER:-$(id -un)}"
if [ "$TARGET_USER" = "$CURRENT_USER" ]; then
  if command -v newgrp >/dev/null 2>&1; then
    log "Attempting to activate new group in this session..."
    # newgrp starts a subshell. Run a no-op to verify and exit immediately.
    su -s /bin/bash -c 'newgrp docker <<NGDONE
true
NGDONE
' "$TARGET_USER" >/dev/null 2>&1 || true
  fi
fi

# Test installations
log "Verifying Docker installation..."
if ! docker --version >/dev/null 2>&1; then
  fail "docker command not found after installation."
fi
docker --version

log "Verifying Compose installation..."
if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose plugin not found."
fi
docker compose version

log "All done."
log "User ${TARGET_USER} has been added to the docker group."
log "If docker commands still require sudo, log out and back in to refresh group membership."

#!/usr/bin/env bash
# Install Docker Engine and Docker Compose on Raspberry Pi OS, Debian, or Ubuntu
# Adds the specified user to the docker group to allow running docker without sudo
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/you/repo/main/install-docker-pi.sh | bash -s -- --user sam
#   or
#   wget -qO- https://raw.githubusercontent.com/you/repo/main/install-docker-pi.sh | bash -s -- --user sam

set -euo pipefail

log() { echo "[install-docker] $*"; }
fail() { echo "[install-docker] ERROR: $*" >&2; exit 1; }

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

# Determine current OS
[ -r /etc/os-release ] || fail "Cannot detect OS (missing /etc/os-release)"
. /etc/os-release

ID_LOWER=$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')
ID_LIKE_LOWER=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')
CODENAME="${VERSION_CODENAME:-bookworm}" # default for Pi OS 12

if [[ "$ID_LOWER" =~ (raspbian|debian|ubuntu) ]] || [[ "$ID_LIKE_LOWER" =~ (debian|ubuntu) ]]; then
  log "Detected compatible OS: $PRETTY_NAME"
else
  fail "Unsupported OS detected: ${PRETTY_NAME:-unknown}"
fi

# Detect architecture (armv7l, aarch64, x86_64)
ARCH=$(dpkg --print-architecture)
log "System architecture: $ARCH"

# Determine target user
if [ -z "$TARGET_USER" ]; then
  if [ "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
  else
    TARGET_USER="$(id -un)"
  fi
fi
log "Target user for docker group: $TARGET_USER"

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  log "Re-running as root..."
  exec sudo -E bash "$0" --user "$TARGET_USER"
fi

export DEBIAN_FRONTEND=noninteractive

# Install prerequisites
log "Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker’s official GPG key
log "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
log "Configuring Docker repository..."
echo \
  "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $CODENAME stable" > /etc/apt/sources.list.d/docker.list

# Install Docker Engine and Compose plugin
log "Installing Docker and Compose..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker service
log "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# Add docker-compose alias for backward compatibility
if ! command -v docker-compose >/dev/null 2>&1; then
  log "Creating docker-compose v2 alias..."
  cat >/usr/local/bin/docker-compose <<'EOF'
#!/usr/bin/env bash
exec docker compose "$@"
EOF
  chmod +x /usr/local/bin/docker-compose
fi

# Add user to docker group
if ! getent group docker >/dev/null 2>&1; then
  groupadd docker
fi
usermod -aG docker "$TARGET_USER"
log "Added user '$TARGET_USER' to the docker group."

# Test Docker
log "Verifying installation..."
docker --version
docker compose version

log "Installation complete!"
log "Please log out and back in for group changes to take effect."

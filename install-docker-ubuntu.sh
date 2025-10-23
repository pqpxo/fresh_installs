#!/usr/bin/env bash
# install-docker-linux.sh
# Purpose: Install the latest Docker Engine on Ubuntu or Debian using Docker's official repository
# Usage examples:
#   curl -fsSL https://raw.githubusercontent.com/pqpxo/fresh_installs/main/install-docker-ubuntu.sh | bash
#   bash install-docker-linux.sh
#
# Options:
#   --force          proceed even if distro detection is unusual
#   --no-enable      install but do not enable the docker service
#   --no-start       install but do not start the docker service
#   --add-user USER  add USER to the docker group after install

set -euo pipefail

FORCE=0
NO_ENABLE=0
NO_START=0
ADD_USER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --no-enable) NO_ENABLE=1; shift ;;
    --no-start) NO_START=1; shift ;;
    --add-user) ADD_USER="${2:-}"; shift 2 ;;
    *) echo "[!] Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

log() { printf "%s\n" "[+] $*"; }
err() { printf "%s\n" "[!] $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Detect OS
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  err "/etc/os-release not found. Cannot determine OS."
  exit 1
fi

DIST_ID="${ID:-}"
DIST_LIKE="${ID_LIKE:-}"
CODENAME="${VERSION_CODENAME:-}"
ARCH="$($SUDO dpkg --print-architecture)"

# Determine docker repo family and validate
REPO_FAMILY=""
case "$DIST_ID" in
  ubuntu) REPO_FAMILY="ubuntu" ;;
  debian) REPO_FAMILY="debian" ;;
  *)
    if [[ "$DIST_LIKE" == *ubuntu* ]]; then
      REPO_FAMILY="ubuntu"
    elif [[ "$DIST_LIKE" == *debian* ]]; then
      REPO_FAMILY="debian"
    fi
    ;;
esac

if [[ -z "$REPO_FAMILY" ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    err "Unknown distro. Proceeding due to --force. Defaulting to debian family."
    REPO_FAMILY="debian"
  else
    err "Unsupported distribution. Detected ID='${DIST_ID:-unknown}', ID_LIKE='${DIST_LIKE:-unknown}'. Use --force to override."
    exit 1
  fi
fi

# Determine codename if missing
if [[ -z "$CODENAME" ]]; then
  if have lsb_release; then
    CODENAME="$(lsb_release -cs || true)"
  fi
fi
if [[ -z "$CODENAME" ]]; then
  err "Could not determine distro codename. Set VERSION_CODENAME or install lsb-release. You can run with --force but repo may be wrong."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Update and prerequisites
log "Updating package lists"
$SUDO apt-get update -y -qq

log "Installing prerequisites: ca-certificates curl gnupg lsb-release"
$SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release

# Add Docker GPG key
log "Adding Docker GPG key"
$SUDO install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${REPO_FAMILY}/gpg" | $SUDO tee /etc/apt/keyrings/docker.asc >/dev/null
$SUDO chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
log "Configuring Docker APT repository for ${REPO_FAMILY} ${CODENAME} (${ARCH})"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${REPO_FAMILY} ${CODENAME} stable" | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

# Update and install
log "Refreshing package lists after adding Docker repo"
$SUDO apt-get update -y -qq

log "Installing Docker Engine, CLI, containerd, buildx and compose plugin"
$SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start service
if have systemctl; then
  if [[ "$NO_ENABLE" -ne 1 ]]; then
    log "Enabling docker service"
    $SUDO systemctl enable docker
  else
    log "Skipping enable due to --no-enable"
  fi

  if [[ "$NO_START" -ne 1 ]]; then
    log "Starting docker service"
    $SUDO systemctl start docker || true
  else
    log "Skipping start due to --no-start"
  fi
else
  log "systemctl not found. Skipping enable and start."
fi

# Post install check
if have docker; then
  DOCKER_VERSION="$(docker --version 2>/dev/null || true)"
  log "Docker installed: ${DOCKER_VERSION}"
else
  err "Docker command not found after installation."
  exit 1
fi

# Optional group add
if [[ -n "$ADD_USER" ]]; then
  if id -u "$ADD_USER" >/dev/null 2>&1; then
    log "Adding user '${ADD_USER}' to docker group"
    $SUDO usermod -aG docker "$ADD_USER"
    log "User '${ADD_USER}' added. They must re login or run: newgrp docker"
  else
    err "User '${ADD_USER}' does not exist. Skipping group addition."
  fi
else
  cat <<EOF
[+] Optional: add your user to the docker group to run without sudo
    sudo usermod -aG docker \$USER
    newgrp docker
EOF
fi

log "Done."

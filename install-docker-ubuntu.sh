#!/usr/bin/env bash
# install-docker-ubuntu.sh
# Purpose: Install the latest Docker Engine on Ubuntu using Docker's official repository
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/USER/REPO/BRANCH/install-docker-ubuntu.sh -o install-docker-ubuntu.sh
#   bash install-docker-ubuntu.sh
# or
#   wget -qO install-docker-ubuntu.sh https://raw.githubusercontent.com/USER/REPO/BRANCH/install-docker-ubuntu.sh && bash install-docker-ubuntu.sh

set -euo pipefail

#---------------------------------------------
# Helpers and preflight checks
#---------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

log() {
  printf "%s\n" "[+] $*"
}

err() {
  printf "%s\n" "[!] $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

# Ensure running on Ubuntu
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
    err "This script is intended for Ubuntu. Detected ID='${ID:-unknown}', ID_LIKE='${ID_LIKE:-unknown}'."
    exit 1
  fi
else
  err "/etc/os-release not found. Cannot determine OS."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

#---------------------------------------------
# Update package lists
#---------------------------------------------
log "Updating package lists"
$SUDO apt-get update -y -qq

#---------------------------------------------
# Install dependencies
#---------------------------------------------
log "Installing prerequisites: ca-certificates curl gnupg lsb-release"
$SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release

# Determine codename and architecture
ARCH="$($SUDO dpkg --print-architecture)"
if require_cmd lsb_release; then
  CODENAME="$(lsb_release -cs)"
else
  # Fallback: parse VERSION_CODENAME from os-release
  CODENAME="${VERSION_CODENAME:-}"
fi

if [[ -z "${CODENAME}" ]]; then
  err "Could not determine Ubuntu codename."
  exit 1
fi

log "Detected architecture: ${ARCH}"
log "Detected Ubuntu codename: ${CODENAME}"

#---------------------------------------------
# Add Docker's official GPG key
#---------------------------------------------
log "Adding Docker GPG key"
$SUDO install -m 0755 -d /etc/apt/keyrings
if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO tee /etc/apt/keyrings/docker.asc >/dev/null; then
  :
else
  err "Failed to download Docker GPG key"
  exit 1
fi
$SUDO chmod a+r /etc/apt/keyrings/docker.asc

#---------------------------------------------
# Add the Docker repository
#---------------------------------------------
log "Configuring Docker APT repository"
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | $SUDO tee "${DOCKER_LIST}" >/dev/null

#---------------------------------------------
# Update package lists again
#---------------------------------------------
log "Refreshing package lists after adding Docker repo"
$SUDO apt-get update -y -qq

#---------------------------------------------
# Install Docker Engine and related components
#---------------------------------------------
log "Installing Docker Engine, CLI, containerd, buildx, and compose plugin"
$SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#---------------------------------------------
# Enable and start Docker service
#---------------------------------------------
if require_cmd systemctl; then
  log "Enabling and starting docker service"
  $SUDO systemctl enable docker
  $SUDO systemctl start docker
fi

#---------------------------------------------
# Post-install checks
#---------------------------------------------
if require_cmd docker; then
  DOCKER_VERSION="$(docker --version 2>/dev/null || true)"
  log "Docker installed: ${DOCKER_VERSION}"
else
  err "Docker command not found after installation."
  exit 1
fi

log "Optional: add the current user to the docker group to run without sudo"
log "Run: sudo usermod -aG docker \$USER && newgrp docker"

log "All done."

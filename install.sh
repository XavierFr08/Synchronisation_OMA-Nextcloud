#!/usr/bin/env bash
# installer for Synchronisation_OMA-Nextcloud
# usage: ./install.sh install   # initial install
#        ./install.sh update    # pull latest from git and refresh services
#
# This script must be executed with root privileges.  It copies the
# scripts and unit files from the repository to their destination,
# installs the minimal package set (rpi-usb-gadget, rclone) and enables
# the systemd services.  The update command will `git pull` the repo and
# re‑apply the copy+service steps so an existing installation can be
# refreshed.

set -euo pipefail

# location where the repository will be stored on the Pi when
# performing a network-based bootstrap.  users can override by
# setting INSTALL_DIR in the environment before running the script.
INSTALL_DIR=${INSTALL_DIR:-/opt/Synchronisation_OMA-Nextcloud}

# URL of the github repository containing this installer and the
# associated scripts.  change if you fork the project.
REPO_URL=${REPO_URL:-https://github.com/XavierFr08/Synchronisation_OMA-Nextcloud.git}

# directory where the installer script was invoked; may or may not be
# the repository itself.  we detect and possibly clone later.
# avoid direct indexed BASH_SOURCE access under strict mode (`bash -s` may not define it)
SCRIPT_SOURCE="$0"
if [[ -n "${BASH_SOURCE+x}" && -n "${BASH_SOURCE:-}" ]]; then
    SCRIPT_SOURCE="${BASH_SOURCE:-$0}"
fi
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This installer must be run as root (sudo)." >&2
        exit 1
    fi
}

install_packages() {
    echo "[install] Updating package lists and installing dependencies..."
    apt update
    apt upgrade -y
    apt install -y rpi-usb-gadget rclone git
}

copy_files() {
    local src="$1"  # repository root containing usr/ and etc/

    echo "[install] Installing binaries and service units from $src..."

    # ensure structure exists in provided source
    if [[ ! -d "$src/usr/local/bin" || ! -d "$src/etc/systemd/system" ]]; then
        echo "ERROR: expected directory structure not found under $src" >&2
        exit 1
    fi

    # scripts
    echo "  copying scripts to /usr/local/bin";
    cp -av "$src/usr/local/bin/"* /usr/local/bin/
    chmod +x /usr/local/bin/*.sh

    # systemd units
    echo "  copying systemd unit files to /etc/systemd/system";
    cp -av "$src/etc/systemd/system/"* /etc/systemd/system/
    systemctl daemon-reload
}

enable_and_start_services() {
    echo "[install] Enabling and starting services..."
    systemctl enable piusb-gadget.service piusb-mount.service piusb-sync.service
    systemctl restart piusb-gadget.service piusb-mount.service piusb-sync.service
}

configure_user() {
    local user=""

    # 1. Use the calling user when run via sudo
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        user="$SUDO_USER"
        echo "[install] Utilisateur détecté via SUDO_USER : $user"
    fi

    # 2. Search for non-system users (UID >= 1000)
    if [[ -z "$user" ]]; then
        local candidates
        candidates=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false|sync|halt|shutdown)$/ {print $1}')
        local count=0
        [[ -n "$candidates" ]] && count=$(echo "$candidates" | wc -l)

        if [[ "$count" -eq 1 ]]; then
            user="$candidates"
            echo "[install] Utilisateur détecté automatiquement : $user"
        elif [[ "$count" -gt 1 ]]; then
            echo "[install] Plusieurs utilisateurs trouvés :"
            echo "$candidates"
        fi
    fi

    # 3. Prompt if still undetermined
    if [[ -z "$user" ]]; then
        read -rp "[install] Entrez le nom d'utilisateur à utiliser pour la synchronisation : " user
    fi

    if [[ -z "$user" ]]; then
        echo "ERROR: aucun utilisateur spécifié." >&2
        exit 1
    fi

    # Validate username to prevent injection (Linux username rules)
    if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "ERROR: nom d'utilisateur invalide : '$user'." >&2
        exit 1
    fi

    if ! id "$user" &>/dev/null; then
        echo "ERROR: l'utilisateur '$user' n'existe pas sur ce système." >&2
        exit 1
    fi

    echo "PIUSB_USER=${user}" > /etc/piusb-sync.conf
    echo "[install] Configuration utilisateur écrite dans /etc/piusb-sync.conf (PIUSB_USER=${user})"
}

prepare_source() {
    # determine the directory which contains the repo we should operate
    # on.  priority order:
    # 1. if the script was run from inside a valid clone use that.
    # 2. else if INSTALL_DIR already contains a clone use it.
    # 3. otherwise clone from REPO_URL into INSTALL_DIR.

    if [[ -d "$SCRIPT_DIR/usr/local/bin" && -d "$SCRIPT_DIR/etc/systemd/system" ]]; then
        echo "[install] using repository at $SCRIPT_DIR" >&2
        echo "$SCRIPT_DIR"
        return
    fi

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        echo "[install] using existing clone at $INSTALL_DIR" >&2
        echo "$INSTALL_DIR"
        return
    fi

    echo "[install] cloning repository to $INSTALL_DIR" >&2
    git clone "$REPO_URL" "$INSTALL_DIR"
    echo "$INSTALL_DIR"
}

perform_install() {
    require_root
    install_packages
    configure_user
    local src
    src=$(prepare_source)
    copy_files "$src"
    enable_and_start_services
    echo "Installation complete."
}

perform_update() {
    require_root

    # determine where the repo lives
    local src
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
        src="$SCRIPT_DIR"
    elif [[ -d "$INSTALL_DIR/.git" ]]; then
        src="$INSTALL_DIR"
    else
        echo "Repository not found locally; performing initial clone first."
        git clone "$REPO_URL" "$INSTALL_DIR"
        src="$INSTALL_DIR"
    fi

    echo "[update] updating repository in $src"
    git -C "$src" pull --ff-only origin main

    copy_files "$src"
    enable_and_start_services
    echo "Update complete."
}

usage() {
    cat <<EOF
Usage: $0 <command>

Commands:
  install   perform a fresh installation using the files in this repo
  update    refresh an existing installation (git pull + reapply)

EOF
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

case "$1" in
    install)
        perform_install
        ;;
    update)
        perform_update
        ;;
    *)
        usage
        ;;
esac

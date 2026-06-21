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
    apt install -y rpi-usb-gadget rclone git dosfstools
}

ensure_piusb_image() {
    local img="/piusb.img"

    if [[ -f "$img" ]]; then
        echo "[install] USB image déjà présente: $img"
        return
    fi

    echo "[install] Création de $img (256MiB, FAT32)..."
    dd if=/dev/zero of="$img" bs=1M count=256 status=progress
    mkfs.vfat -F 32 "$img"
    sync
}

ensure_piusb_mount() {
    local mountpoint="/mnt/piusb"

    mkdir -p "$mountpoint"

    if findmnt -rn -M "$mountpoint" >/dev/null 2>&1; then
        echo "[install] Image déjà montée sur $mountpoint"
        return
    fi

    echo "[install] Montage de /piusb.img sur $mountpoint..."
    /usr/local/bin/mount-piusb-ro.sh
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

    if ! systemctl restart piusb-gadget.service; then
        echo "[warn] piusb-gadget.service n'a pas démarré." >&2
        echo "[warn] Vérifiez: systemctl status piusb-gadget.service" >&2
        echo "[warn] Détails:  journalctl -xeu piusb-gadget.service" >&2
        echo "[warn] Cause fréquente: image /piusb.img absente." >&2
        echo "[warn] Les services dépendants (piusb-mount, piusb-sync) ne sont pas démarrés pour l'instant." >&2
        return 0
    fi

    if ! systemctl restart piusb-mount.service; then
        echo "[warn] piusb-mount.service n'a pas démarré." >&2
        echo "[warn] Vérifiez: systemctl status piusb-mount.service" >&2
        echo "[warn] Détails:  journalctl -xeu piusb-mount.service" >&2
        echo "[warn] piusb-sync.service ne sera pas démarré tant que le montage échoue." >&2
        return 0
    fi

    if ! systemctl restart piusb-sync.service; then
        echo "[warn] piusb-sync.service n'a pas démarré." >&2
        echo "[warn] Vérifiez: systemctl status piusb-sync.service" >&2
        echo "[warn] Détails:  journalctl -xeu piusb-sync.service" >&2
    fi
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

get_piusb_hostname() {
    local hostname
    hostname=$(hostname -s)  # Get short hostname
    
    # Validate hostname (alphanumeric and hyphens only, max 63 chars)
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9-]+$ ]] || [[ ${#hostname} -gt 63 ]]; then
        echo "ERROR: Hostname invalide : '$hostname'. Doit contenir uniquement des lettres, chiffres et tirets." >&2
        exit 1
    fi
    
    echo "$hostname"
}

verify_nextcloud_config() {
    local conf_file="$1"
    
    # Vérifier que les paramètres existent
    if [[ ! -f "$conf_file" ]]; then
        return 1
    fi
    
    local has_url has_user has_pass
    has_url=$(grep -c '^NEXTCLOUD_URL=' "$conf_file" 2>/dev/null || true)
    has_user=$(grep -c '^NEXTCLOUD_USER=' "$conf_file" 2>/dev/null || true)
    has_pass=$(grep -c '^NEXTCLOUD_PASSWORD=' "$conf_file" 2>/dev/null || true)
    
    if [[ $has_url -eq 0 || $has_user -eq 0 || $has_pass -eq 0 ]]; then
        return 1
    fi
    
    return 0
}

test_nextcloud_access() {
    local nc_url nc_user nc_path
    
    # Charger la configuration
    if [[ ! -f "/etc/piusb-sync.conf" ]]; then
        return 1
    fi
    
    source /etc/piusb-sync.conf
    
    if [[ -z "${NEXTCLOUD_URL:-}" || -z "${NEXTCLOUD_USER:-}" || -z "${PIUSB_USER:-}" ]]; then
        return 1
    fi
    
    nc_path="${NEXTCLOUD_PATH:-${PIUSB_HOSTNAME}}"
    
    echo "[check] Test de l'accès à Nextcloud..." >&2
    echo "[check]   URL: ${NEXTCLOUD_URL}" >&2
    echo "[check]   Utilisateur: ${NEXTCLOUD_USER}" >&2
    echo "[check]   Chemin: ${nc_path}" >&2
    echo "" >&2
    
    # Tester l'accès via rclone
    if sudo -u "${PIUSB_USER}" rclone lsf "nextcloud:${nc_path}" >/dev/null 2>&1; then
        echo "[check] ✓ Accès Nextcloud OK" >&2
        return 0
    else
        echo "[check] ✗ Impossible d'accéder à Nextcloud" >&2
        echo "[check] Vérifications à effectuer:" >&2
        echo "[check]   1. URL du serveur correcte" >&2
        echo "[check]   2. Identifiants Nextcloud corrects" >&2
        echo "[check]   3. Le chemin '${nc_path}' existe sur Nextcloud" >&2
        echo "[check]   4. Configuration rclone valide" >&2
        return 1
    fi
}

check_and_configure_nextcloud() {
    local reconfigure answer
    
    if ! verify_nextcloud_config "/etc/piusb-sync.conf"; then
        echo "" >&2
        echo "[install] Configuration Nextcloud manquante ou incomplète." >&2
        read -rp "[install] Configurer Nextcloud maintenant? (o/n) [o] : " answer
        if [[ "${answer:-o}" == "o" || "${answer:-o}" == "O" ]]; then
            configure_nextcloud
        else
            echo "ERROR: Configuration Nextcloud requise pour continuer." >&2
            exit 1
        fi
        return 0
    fi
    
    # Configuration existe, tester l'accès
    if ! test_nextcloud_access; then
        echo "" >&2
        read -rp "[install] Reconfigurer Nextcloud? (o/n) [o] : " reconfigure
        if [[ "${reconfigure:-o}" == "o" || "${reconfigure:-o}" == "O" ]]; then
            # Sauvegarder les anciens paramètres
            cp /etc/piusb-sync.conf "/etc/piusb-sync.conf.bak"
            # Extraire et garder les paramètres non-Nextcloud
            grep '^PIUSB_' "/etc/piusb-sync.conf.bak" > /etc/piusb-sync.conf.tmp
            mv /etc/piusb-sync.conf.tmp /etc/piusb-sync.conf
            configure_nextcloud
            echo "[install] Configuration mise à jour. Ancien fichier sauvegardé: /etc/piusb-sync.conf.bak" >&2
        else
            echo "WARNING: Les paramètres Nextcloud ne sont pas accessibles." >&2
            echo "[install] La synchronisation risque de ne pas fonctionner." >&2
        fi
    fi
}

configure_nextcloud() {
    local nc_url nc_user nc_password app_name nc_path user_nc_path
    local piusb_hostname
    piusb_hostname=$(get_piusb_hostname)
    app_name="${piusb_hostname}-sync"  # Nom du mot de passe d'application
    nc_path="${piusb_hostname}"  # Chemin Nextcloud par défaut

    echo ""
    echo "[install] ===== Configuration Nextcloud ====="
    echo "[install] Entrez les paramètres de connexion Nextcloud pour la synchronisation."
    echo ""
    echo "[INFO] Hostname détecté: ${piusb_hostname}"
    echo ""

    # Instructions pour créer le mot de passe d'application
    echo "[INSTRUCTION] AVANT de continuer, créez un mot de passe d'application dans Nextcloud :"
    echo "  1. Connectez-vous à Nextcloud"
    echo "  2. Allez dans Paramètres → Sécurité"
    echo "  3. Cherchez 'Mots de passe d'application' en bas de la page"
    echo "  4. Entrez le nom: '${app_name}'"
    echo "  5. Cliquez sur 'Générer le mot de passe'"
    echo "  6. Copiez le mot de passe généré"
    echo ""
    read -rp "[install] Appuyez sur Entrée pour continuer quand le mot de passe est créé..." 
    echo ""

    # Prompt for Nextcloud URL
    read -rp "[install] URL du serveur Nextcloud (ex: https://nextcloud.example.com) : " nc_url
    if [[ -z "$nc_url" ]]; then
        echo "ERROR: URL Nextcloud requise." >&2
        exit 1
    fi

    # Remove trailing slash if present
    nc_url="${nc_url%/}"

    # Prompt for username
    read -rp "[install] Nom d'utilisateur Nextcloud : " nc_user
    if [[ -z "$nc_user" ]]; then
        echo "ERROR: Nom d'utilisateur requis." >&2
        exit 1
    fi

    # Prompt for app password
    read -rsp "[install] Mot de passe d'application Nextcloud : " nc_password
    echo ""
    if [[ -z "$nc_password" ]]; then
        echo "ERROR: Mot de passe d'application requis." >&2
        exit 1
    fi

    # Prompt for Nextcloud path (with default based on hostname)
    read -rp "[install] Chemin dans Nextcloud pour la synchronisation (défaut: ${nc_path}) : " user_nc_path
    if [[ -n "$user_nc_path" ]]; then
        nc_path="$user_nc_path"
    fi

    # Append Nextcloud configuration to /etc/piusb-sync.conf
    {
        echo "PIUSB_HOSTNAME=${piusb_hostname}"
        echo "NEXTCLOUD_URL=${nc_url}"
        echo "NEXTCLOUD_USER=${nc_user}"
        echo "NEXTCLOUD_PASSWORD=${nc_password}"
        echo "NEXTCLOUD_PATH=${nc_path}"
    } >> /etc/piusb-sync.conf

    chmod 600 /etc/piusb-sync.conf

    # Create rclone configuration for the user
    local user_home
    user_home=$(eval echo "~${PIUSB_USER}")
    local rclone_dir="${user_home}/.config/rclone"
    mkdir -p "$rclone_dir"

    # Create rclone.conf with Nextcloud remote
    cat > "${rclone_dir}/rclone.conf" <<EOF
[nextcloud]
type = webdav
url = ${nc_url}/remote.php/dav/files/${nc_user}/
vendor = nextcloud
user = ${nc_user}
pass = $(rclone obscure "${nc_password}")
EOF

    chown -R "${PIUSB_USER}:${PIUSB_USER}" "$rclone_dir"
    chmod 600 "${rclone_dir}/rclone.conf"

    echo "[install] Configuration Nextcloud sauvegardée dans /etc/piusb-sync.conf"
    echo "[install] Configuration rclone créée pour l'utilisateur ${PIUSB_USER}"
    echo "[install] Dossier Nextcloud: ${nc_path}"
    echo "[install] Mot de passe d'application nommé: ${app_name}"
}

prepare_source() {
    PREPARED_SOURCE=""

    # determine the directory which contains the repo we should operate
    # on.  priority order:
    # 1. if the script was run from inside a valid clone use that.
    # 2. else if INSTALL_DIR already contains a clone use it.
    # 3. otherwise clone from REPO_URL into INSTALL_DIR.

    if [[ -d "$SCRIPT_DIR/usr/local/bin" && -d "$SCRIPT_DIR/etc/systemd/system" ]]; then
        echo "[install] using repository at $SCRIPT_DIR" >&2
        PREPARED_SOURCE="$SCRIPT_DIR"
        return
    fi

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        echo "[install] using existing clone at $INSTALL_DIR" >&2
        PREPARED_SOURCE="$INSTALL_DIR"
        return
    fi

    echo "[install] cloning repository to $INSTALL_DIR" >&2
    git clone "$REPO_URL" "$INSTALL_DIR"
    PREPARED_SOURCE="$INSTALL_DIR"
}

perform_install() {
    require_root
    install_packages
    configure_user
    configure_nextcloud
    prepare_source
    if [[ -z "${PREPARED_SOURCE:-}" ]]; then
        echo "ERROR: impossible de déterminer le répertoire source." >&2
        exit 1
    fi
    copy_files "$PREPARED_SOURCE"
    ensure_piusb_image
    ensure_piusb_mount
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
    
    # Vérifier et configurer Nextcloud si nécessaire
    check_and_configure_nextcloud
    
    copy_files "$src"
    ensure_piusb_image
    ensure_piusb_mount
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

#!/usr/bin/env bash
# ------------------------------------------------------------
# Synchronisation en temps réel d'un disque USB virtuel vers
# Nextcloud en transformant les fichiers *.PTN en *.oma.
# ------------------------------------------------------------

set -euo pipefail

# ------------------- Utilisateur -------------------
CONF_FILE="/etc/piusb-sync.conf"
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi
PIUSB_USER="${PIUSB_USER:-}"
if [[ -z "$PIUSB_USER" ]]; then
    echo "ERROR: PIUSB_USER is not set. Run install.sh to configure the user." >&2
    exit 1
fi
# ---------------------------------------------------

export RCLONE_CONFIG="/home/${PIUSB_USER}/.config/rclone/rclone.conf"

# ------------------- Configuration -------------------
MOUNT_POINT="/mnt/piusb"
IMG="/piusb.img"
SCAN_INTERVAL=15
NEXTCLOUD_REMOTE="nextcloud:"
NEXTCLOUD_PATH="NIDEK/NIDEK-ICE9000"
SLEEP_AFTER_EVENT=1
RCLONE_OPTS=(--transfers=4 --checkers=8)
TMP_DIR="/tmp/piusb-sync-tmp"
USER_HOME="/home/${PIUSB_USER}"
STATE_FILE="${USER_HOME}/.piusb-sync/state.csv"
# ----------------------------------------------------

setup_nextcloud_remote_if_needed() {
    local remote_name="${NEXTCLOUD_REMOTE%:}"

    if sudo -u "${PIUSB_USER}" rclone listremotes | grep -qx "${remote_name}:"; then
        return
    fi

    if [[ ! -t 0 ]]; then
        echo "ERROR: remote rclone '${remote_name}:' introuvable et mode non interactif." >&2
        echo "       Lancez 'sudo ./install.sh install' ou exécutez ce script dans un terminal pour configurer Nextcloud." >&2
        exit 1
    fi

    local nc_url=""
    local nc_user=""
    local nc_pass=""

    echo "Configuration Nextcloud requise pour le remote '${remote_name}:'" >&2
    read -rp "URL Nextcloud (ex: https://cloud.example.com/remote.php/dav/files/<user>) : " nc_url
    read -rp "Nom d'utilisateur Nextcloud : " nc_user
    read -srp "Mot de passe Nextcloud : " nc_pass
    echo

    if [[ -z "$nc_url" || -z "$nc_user" || -z "$nc_pass" ]]; then
        echo "ERROR: URL, nom d'utilisateur et mot de passe Nextcloud sont obligatoires." >&2
        exit 1
    fi

    sudo -u "${PIUSB_USER}" mkdir -p "${USER_HOME}/.config/rclone"
    local obscured
    obscured=$(sudo -u "${PIUSB_USER}" rclone obscure "$nc_pass")

    sudo -u "${PIUSB_USER}" rclone config create "${remote_name}" webdav \
        url="$nc_url" \
        vendor="nextcloud" \
        user="$nc_user" \
        pass="$obscured" >/dev/null

    echo "Remote rclone '${remote_name}:' configuré avec succès." >&2
}

mkdir -p "$TMP_DIR" "$(dirname "$STATE_FILE")"
chown "${PIUSB_USER}:${PIUSB_USER}" "$TMP_DIR" "$(dirname "$STATE_FILE")"

setup_nextcloud_remote_if_needed

declare -A FILE_STATE

find_loop_device() {
    # "head" may close the pipe after getting one line, causing awk to
    # receive SIGPIPE and exit non-zero. with pipefail enabled the whole
    # pipeline would then abort the script.  we ignore errors and silence
    # awk stderr so that the service doesn't crash repeatedly.
    losetup -j "$IMG" | awk -F: '{print $1}' 2>/dev/null | head -n1 || true
}

load_state() {
    FILE_STATE=()
    if [[ -f "$STATE_FILE" ]]; then
        while IFS=, read -r rel mtime; do
            [[ -n "$rel" && -n "$mtime" ]] && FILE_STATE["$rel"]=$mtime
        done < "$STATE_FILE"
    fi
}

update_state() { FILE_STATE["$1"]=$2; }

save_state() {
    local tmp="${STATE_FILE}.tmp"
    > "$tmp"
    for rel in "${!FILE_STATE[@]}"; do
        printf '%s,%s\n' "$rel" "${FILE_STATE[$rel]}" >> "$tmp"
    done
    mv "$tmp" "$STATE_FILE"
}

echo "Début de la synchronisation" >&2

# ---------- Attente du montage initial ----------
timeout=60 elapsed=0
while [ ! -f "$IMG" ]; do
    sleep 1
    ((elapsed++))
    (( elapsed >= timeout )) && {
        echo "Timeout waiting for image $IMG" >&2
        exit 1
    }
done

mkdir -p "$MOUNT_POINT"

DEVICE=$(find_loop_device)
if [ -z "$DEVICE" ]; then
    DEVICE=$(losetup -f --show "$IMG")
fi

mount -o ro,uid=$(id -u "${PIUSB_USER}"),gid=$(id -g "${PIUSB_USER}") "$DEVICE" "$MOUNT_POINT"

echo "Montage prêt sur $MOUNT_POINT ($DEVICE)" >&2

load_state

# ---------- Copie initiale ----------
echo " Copie incrémentale initiale des fichiers" >&2
find "$MOUNT_POINT" -type f -print0 | while IFS= read -r -d '' f; do
    rel="${f#$MOUNT_POINT/}"
    [[ ! -f "$f" ]] && continue
    mtime=$(stat -c %Y "$f")

    if [[ "${FILE_STATE[$rel]+set}" && "${FILE_STATE[$rel]}" -eq "$mtime" ]]; then
        continue
    fi

    base="${rel##*/}"
    dir="${rel%/*}"
    [[ "$dir" == "$rel" ]] && dir=""

    shopt -s nocasematch
    if [[ "$base" == *.PTN ]]; then
        name_noext="${base%.*}"
        target_rel="${dir:+$dir/}$name_noext.oma"
    else
        target_rel="$rel"
    fi
    shopt -u nocasematch

    remote_target="${NEXTCLOUD_REMOTE}${NEXTCLOUD_PATH}/${target_rel}"

    # Renommage d’un .PTN déjà présent sur le remote
    if [[ "$base" == *.PTN ]]; then
        remote_ptn="${NEXTCLOUD_REMOTE}${NEXTCLOUD_PATH}/${dir:+$dir/}${base}"
        remote_oma="${NEXTCLOUD_REMOTE}${NEXTCLOUD_PATH}/${dir:+$dir/}${name_noext}.oma"
        if rclone lsf "${remote_ptn%/*}" --files-only | grep -qx "$(basename "$remote_ptn")"; then
            rclone moveto "${RCLONE_OPTS[@]}" --quiet "$remote_ptn" "$remote_oma"
        fi
    fi

    tmp_local="${TMP_DIR}/$(basename "$target_rel")"
    cp --reflink=auto --preserve=mode,timestamps "$f" "$tmp_local" 2>/dev/null || cp "$f" "$tmp_local"

    echo " Envoi du fichier $f → $remote_target" >&2
    if rclone copyto "${RCLONE_OPTS[@]}" --quiet "$tmp_local" "$remote_target"; then
        update_state "$rel" "$mtime"
        save_state
        echo "[STATE] $rel enregistré avec mtime $mtime dans $STATE_FILE" >&2
    else
        echo " Envoi du fichier a échoué pour $f" >&2
    fi
    rm -f "$tmp_local"
done

# ---------- Traitement des fichiers modifiés ou ajoutés ----------
process_file() {
    local fullpath="$1"
    local rel="${fullpath#$MOUNT_POINT/}"
    [[ ! -f "$fullpath" ]] && return
    local mtime=$(stat -c %Y "$fullpath")
    local base=$(basename "$rel")
    local dir=$(dirname "$rel")
    [[ "$dir" == "." ]] && dir=""

    shopt -s nocasematch
    if [[ "$base" == *.PTN ]]; then
        name_noext="${base%.*}"
        target_rel="${dir:+$dir/}$name_noext.oma"

        remote_ptn="${NEXTCLOUD_REMOTE}${NEXTCLOUD_PATH}/${dir:+$dir/}${base}"
        remote_oma="${NEXTCLOUD_REMOTE}${NEXTCLOUD_PATH}/${dir:+$dir/}${name_noext}.oma"
        if rclone lsf "${remote_ptn%/*}" --files-only | grep -qx "$(basename "$remote_ptn")"; then
            rclone moveto "${RCLONE_OPTS[@]}" --quiet "$remote_ptn" "$remote_oma"
        fi
    else
        target_rel="$rel"
    fi
    shopt -u nocasematch

    local remote="${NEXTCLOUD_REMOTE}${NEXTCLOUD_PATH}/${target_rel}"
    local tmp_local="${TMP_DIR}/$(basename "$target_rel")"

    cp --reflink=auto --preserve=mode,timestamps "$fullpath" "$tmp_local" 2>/dev/null || cp "$fullpath" "$tmp_local"

    sleep "$SLEEP_AFTER_EVENT"

    echo " Envoi de $fullpath → $remote" >&2
    if rclone copyto "${RCLONE_OPTS[@]}" --quiet "$tmp_local" "$remote"; then
        echo " Envoi effectué $target_rel" >&2
        update_state "$rel" "$mtime"
        save_state
        echo "[STATE] $target_rel enregistré avec mtime $mtime dans $STATE_FILE" >&2
    else
        echo " Echec de l'envoi $target_rel" >&2
    fi
    rm -f "$tmp_local"
}

# ------------------------------------------------------------
# Boucle find avec démontage/remontage pour rafraîchir la vue
# ------------------------------------------------------------
echo "Début de la recherche de fichiers modifiés" >&2

while true; do
    umount "$MOUNT_POINT" 2>/dev/null || true

    DEVICE=$(find_loop_device)
    if [ -n "$DEVICE" ]; then
        losetup -d "$DEVICE"
    fi

    DEVICE=$(losetup -f --show "$IMG")
    mount -o ro,uid=$(id -u "${PIUSB_USER}"),gid=$(id -g "${PIUSB_USER}") "$DEVICE" "$MOUNT_POINT"

    echo "[INFO] Scan du contenu du disque USB..." >&2

    load_state

    find "$MOUNT_POINT" -type f -print0 | while IFS= read -r -d '' f; do
        rel="${f#$MOUNT_POINT/}"
        [[ ! -f "$f" ]] && continue
        mtime=$(stat -c %Y "$f")
        if [[ ! "${FILE_STATE[$rel]+set}" || "${FILE_STATE[$rel]}" -ne "$mtime" ]]; then
            process_file "$f"
        fi
    done

    echo "Pause de $SCAN_INTERVAL s"
    sleep "$SCAN_INTERVAL"
done

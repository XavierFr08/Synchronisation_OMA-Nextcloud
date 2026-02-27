#!/bin/bash
# filepath: /usr/local/bin/mount-piusb-ro.sh

# ------------------------------------------------------------
# Script de montage local d'une image USB simulée (piusb.img)
# sur le Raspberry Pi, en lecture seule, pour permettre la
# lecture des fichiers copiés par une machine industrielle.
# ------------------------------------------------------------

set -e

# Charge la configuration utilisateur créée lors de l'installation
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

IMG="/piusb.img"                # Chemin de l'image disque à monter
MOUNTPOINT="/mnt/piusb"         # Point de montage local sur le Pi

mkdir -p "$MOUNTPOINT"

# Cherche le device loopback déjà associé à l'image (si existant)
DEVICE=$(losetup -j "$IMG" | awk -F: '{print $1}' | head -n1)

if [ -z "$DEVICE" ]; then
    # Si aucun device n'est associé, crée un nouveau device loopback
    DEVICE=$(losetup -f --show "$IMG")
fi

# Monte l'image en lecture seule, avec les bons UID/GID pour l'utilisateur configuré
mount -o ro,uid=$(id -u "${PIUSB_USER}"),gid=$(id -g "${PIUSB_USER}") "$DEVICE" "$MOUNTPOINT"

echo "Image $IMG montée en lecture seule sur $MOUNTPOINT via $DEVICE"

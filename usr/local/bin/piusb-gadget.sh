#!/bin/sh
set -eux

IMG="/piusb.img"
GADGET_DIR="/sys/kernel/config/usb_gadget/g1"

# -------------------------------------------------
# 1️⃣ Vérifier que l’image existe
[ -f "$IMG" ] || { echo "Image $IMG introuvable" >&2; exit 1; }

# 2️⃣ Charger le module libcomposite
modprobe libcomposite

# -------------------------------------------------
# 3️⃣ Nettoyer un gadget existant (si présent)
if [ -d "$GADGET_DIR" ]; then
    # 3a – Détacher le contrôleur s’il est lié
    if [ -e "$GADGET_DIR/UDC" ]; then
        echo "" > "$GADGET_DIR/UDC" || true
        # attendre que le noyau libère le gadget
        timeout=5
        while [ -e "$GADGET_DIR/UDC" ] && [ $timeout -gt 0 ]; do
            sleep 0.2
            timeout=$((timeout-1))
        done
    fi
    # 3b – Supprimer le répertoire complet (maintenant autorisé)
    rm -rf "$GADGET_DIR"
fi

# -------------------------------------------------
# 4️⃣ Créer le nouveau gadget
mkdir -p "$GADGET_DIR"
cd "$GADGET_DIR"

echo 0x1d6b > idVendor          # Linux Foundation
echo 0x0104 > idProduct         # Multifunction Composite Gadget
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo "0123456789" > strings/0x409/serialnumber
echo "Raspberry Pi" > strings/0x409/manufacturer
echo "Pi USB Mass Storage" > strings/0x409/product

mkdir -p configs/c.1
echo 250 > configs/c.1/MaxPower

# -------------------------------------------------
# 5️⃣ Fonction mass‑storage
mkdir -p functions/mass_storage.0
echo 1 > functions/mass_storage.0/stall
echo 0 > functions/mass_storage.0/lun.0/cdrom
echo 0 > functions/mass_storage.0/lun.0/ro
echo 1 > functions/mass_storage.0/lun.0/nofua
echo "$IMG" > functions/mass_storage.0/lun.0/file

ln -s functions/mass_storage.0 configs/c.1/

# -------------------------------------------------
# 6️⃣ Lier au contrôleur USB (UDC)
UDC=$(ls /sys/class/udc | head -n1)
if [ -z "$UDC" ]; then
    echo "No UDC found" >&2
    exit 1
fi
echo "$UDC" > UDC

exit 0

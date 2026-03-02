#!/bin/sh
set -eu

IMG="/piusb.img"
GADGET_DIR="/sys/kernel/config/usb_gadget/g1"

# -------------------------------------------------
# 1️⃣ Vérifier que l’image existe
[ -f "$IMG" ] || { echo "Image $IMG introuvable" >&2; exit 1; }

# 2️⃣ Charger le module libcomposite
modprobe libcomposite

# -------------------------------------------------
# 3️⃣ Réinitialiser proprement le gadget (si présent)
if [ -d "$GADGET_DIR" ] && [ -w "$GADGET_DIR/UDC" ]; then
    printf '' > "$GADGET_DIR/UDC" 2>/dev/null || true
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
# Nettoyage ciblé d'une instance précédente pour éviter les erreurs I/O
if [ -L configs/c.1/mass_storage.0 ]; then
    rm -f configs/c.1/mass_storage.0 || true
fi

if [ -d functions/mass_storage.0 ]; then
    printf '' > functions/mass_storage.0/lun.0/file 2>/dev/null || true
    rmdir functions/mass_storage.0/lun.0 2>/dev/null || true
    rmdir functions/mass_storage.0 2>/dev/null || true
fi

mkdir -p functions/mass_storage.0
echo 1 > functions/mass_storage.0/stall
echo 0 > functions/mass_storage.0/lun.0/cdrom
echo 0 > functions/mass_storage.0/lun.0/ro
echo 1 > functions/mass_storage.0/lun.0/nofua
echo "$IMG" > functions/mass_storage.0/lun.0/file

ln -sfn functions/mass_storage.0 configs/c.1/mass_storage.0

# -------------------------------------------------
# 6️⃣ Lier au contrôleur USB (UDC)
UDC=$(ls /sys/class/udc | head -n1)
if [ -z "$UDC" ]; then
    echo "No UDC found" >&2
    exit 1
fi
echo "$UDC" > UDC

exit 0

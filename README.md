# Synchronisation OMA‑Nextcloud

Ce dépôt contient les scripts et unités systemd destinés à transformer un
Raspberry Pi (Zero, 3, 4…) en périphérique USB mass storage et à
synchroniser en temps réel le contenu (`*.PTN` → `*.oma`) vers un
serveur Nextcloud via `rclone`.

## Installation

Vous pouvez soit cloner ce dépôt puis lancer le script, soit exécuter
le script directement depuis Internet ; dans tous les cas le programme se
charge lui‑même de récupérer le code nécessaire.

La commande ci‑dessous effectue l'installation sur un Pi neuf en partant
uniquement d'un système de base :

```sh
# exemple : téléchargement temporaire puis exécution
curl -fsSL https://raw.githubusercontent.com/XavierFr08/Synchronisation_OMA-Nextcloud/main/install.sh | sudo bash -s -- install
```

ou, si vous avez déjà cloné le dépôt :

```sh
git clone https://github.com/XavierFr08/Synchronisation_OMA-Nextcloud.git
cd Synchronisation_OMA-Nextcloud
sudo ./install.sh install
```

Le script :

1. met à jour le système (`apt update/upgrade`),
2. installe les dépendances (`rpi-usb-gadget`, `rclone`, `git`),
3. copie les scripts dans `/usr/local/bin` et les services dans
   `/etc/systemd/system`,
4. active et démarre les services `piusb-gadget`, `piusb-mount` et
   `piusb-sync`.

Pendant l'installation, le script demande maintenant les informations
de connexion Nextcloud :

- URL Nextcloud,
- nom d'utilisateur,
- mot de passe.

Ces informations sont utilisées pour créer automatiquement le remote
`nextcloud:` de `rclone` pour l'utilisateur configuré.

> Le service `piusb-sync` surveille une image `/piusb.img` exposée en
> gadget USB et synchronise son contenu vers Nextcloud. Un état est
> conservé dans `~/.piusb-sync/state.csv` pour éviter les transferts
> répétitifs.

### Mise à jour

Si vous êtes dans un clone git du dépôt, vous pouvez mettre à jour
l'installation en vous plaçant dans le répertoire et en lançant :

```sh
sudo ./install.sh update
```

Cela effectuera un `git pull` puis recopiera les fichiers et redémarrera
les services.

### Reconfigurer Nextcloud

Pour changer uniquement les identifiants Nextcloud (URL, utilisateur,
mot de passe) sans réinstaller, utilisez :

```sh
sudo ./install.sh reconfigure-nextcloud
```

## Personnalisation

Modifiez les variables en tête de `sync-piusb-to-nextcloud.sh` si vous
souhaitez changer le point de montage, le remote Nextcloud, etc.

Si le remote `nextcloud:` est absent, le script de synchronisation peut
également demander ces informations de manière interactive (lors d'un
lancement en terminal) pour le créer.

---

*(Ce README est généré automatiquement par l'assistant pour clarifier
la procédure.)*
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
- mot de passe,
- chemin distant de destination (ex: `NIDEK/NIDEK-ICE9000`).

Format attendu pour le chemin distant :

- vous pouvez saisir avec ou sans `/` au début (ex: `/NIDEK/NIDEK-ICE9000` ou `NIDEK/NIDEK-ICE9000`),
- évitez le `/` final,
- utilisez un chemin relatif dans le remote Nextcloud (pas d'URL complète).

Le script normalise automatiquement ce chemin (suppression du `/` initial et final).

Ces informations sont utilisées pour créer automatiquement le remote
`nextcloud:` de `rclone` pour l'utilisateur configuré.

> Le service `piusb-sync` surveille une image `/piusb.img` exposée en
> gadget USB et synchronise son contenu vers Nextcloud. Un état est
> conservé dans `~/.piusb-sync/state.csv` pour éviter les transferts
> répétitifs.

### Maintenance

Le script `install.sh` propose deux commandes utiles après l'installation.

#### 1) Mettre à jour les scripts et services

Depuis le dossier du dépôt :

```sh
sudo ./install.sh update
```

Cette commande :

- met à jour le dépôt local (`git pull --ff-only origin main`),
- recopie les scripts dans `/usr/local/bin`,
- recopie les unités systemd dans `/etc/systemd/system`,
- recharge systemd puis redémarre `piusb-gadget`, `piusb-mount` et `piusb-sync`.

#### 2) Mettre à jour les identifiants Nextcloud

Pour modifier l'URL, l'utilisateur, le mot de passe **et** le chemin distant
Nextcloud sans réinstallation complète :

```sh
sudo ./install.sh reconfigure-nextcloud
```

Cette commande met à jour la configuration du remote `nextcloud:` dans `rclone`
pour l'utilisateur configuré (`PIUSB_USER`), puis redémarre `piusb-sync.service`.

## Personnalisation

Modifiez les variables en tête de `sync-piusb-to-nextcloud.sh` si vous
souhaitez changer le point de montage, le remote Nextcloud, etc.

Si le remote `nextcloud:` est absent, le script de synchronisation peut
également demander ces informations de manière interactive (lors d'un
lancement en terminal) pour le créer.

---

*(Ce README est généré automatiquement par l'assistant pour clarifier
la procédure.)*
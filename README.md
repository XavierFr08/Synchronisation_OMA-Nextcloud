# Synchronisation OMA‑Nextcloud

Ce dépôt contient les scripts et unités systemd destinés à transformer un Raspberry Pi (Zero, 3, 4…) en périphérique USB mass storage et à synchroniser en temps réel le contenu (`*.PTN` → `*.oma`) vers un serveur Nextcloud via `rclone`.

## Pré-requis

Avant de pouvoir utiliser ce dépôt, assurez-vous que les pré-requis suivants sont satisfaits :

1. **Installation de Debian Trixie 64 bits Lite** :
   - Téléchargez et installez la version 64 bits lite de Debian Trixie sur votre Raspberry Pi.
   - Suivez [la documentation officielle](https://www.raspberrypi.org/documentation/installation/installing-images/) pour l'installation.

2. **Instance Nextcloud** :
   - Vous pouvez héberger Nextcloud localement ou utiliser un service cloud tiers comme Nextcloud.com.
   - Pour une installation locale, suivez les étapes décrites dans [la documentation officielle de Nextcloud](https://docs.nextcloud.com/server/latest/admin_manual/installation.html).
   - **Note** : Si vous hébergez Nextcloud localement, assurez-vous que le Raspberry Pi peut accéder à cette instance. Par exemple, si votre instance Nextcloud est sur un autre serveur ou sur le même réseau local.

## Installation

Vous pouvez soit cloner ce dépôt puis lancer le script, soit exécuter le script directement depuis Internet ; dans tous les cas le programme se charge lui-même de récupérer le code nécessaire.

La commande ci-dessous effectue l'installation sur un Pi neuf en partant uniquement d'un système de base :

```sh
curl -fsSL https://raw.githubusercontent.com/XavierFr08/Synchronisation_OMA-Nextcloud/main/install.sh | sudo bash -s -- install
```

ou, si vous avez déjà cloné le dépôt :

```sh
git clone https://github.com/XavierFr08/Synchronisation_OMA-Nextcloud.git
cd Synchronisation_OMA-Nextcloud
sudo ./install.sh install
```

Le script :

1. met à jour le système (`apt update/upgrade`),
2. installe les dépendances (`rpi-usb-gadget`, `rclone`, `git`, `dosfstools`),
3. vous demande de **configurer l'utilisateur** pour la synchronisation,
4. détecte le **hostname du Pi** (ex : `raspberrypi`, `pi-nidek`, etc.),
5. vous affiche les **instructions pour créer un mot de passe d'application** Nextcloud nommé `{hostname}-sync`,
6. vous demande les **paramètres de connexion Nextcloud** (URL, nom d'utilisateur, mot de passe d'application),
7. vous propose un **chemin Nextcloud par défaut** basé sur le hostname (ex : `raspberrypi`),
8. copie les scripts dans `/usr/local/bin` et les services dans `/etc/systemd/system`,
9. crée l'image USB virtuelle `/piusb.img` (256 MiB, FAT32),
10. active et démarre les services `piusb-gadget`, `piusb-mount` et `piusb-sync`.

### Personnalisation par Hostname

Cette installation utilise automatiquement le **hostname du Raspberry Pi** pour personnaliser l'installation et éviter les conflits en cas d'installations multiples :

- **Hostname** : Nom du Pi (ex : `raspberrypi`, `pi-nidek`, `pi-sync-1`, etc.)
  - Détecté automatiquement : `hostname -s`
  - Doit contenir uniquement des lettres, chiffres et tirets

- **Mot de passe d'application Nextcloud** : Nommé `{hostname}-sync`
  - Exemple : `raspberrypi-sync`, `pi-nidek-sync`
  - Facilite la gestion si plusieurs Pi utilisent le même compte Nextcloud

- **Chemin Nextcloud** : Par défaut `{hostname}`
  - Exemple : `raspberrypi/`, `pi-nidek/`
  - Personnalisable lors de l'installation ou dans `/etc/piusb-sync.conf`

- **Identifiant USB** : Serial number du disque USB = hostname
  - Le Pi apparaîtra avec son hostname sur les ordinateurs connectés via USB
  - Exemple : Disque nommé `raspberrypi` au lieu de `0123456789`

Si un service ne démarre pas au premier lancement, l'installation se termine maintenant avec un avertissement (sans interrompre la copie des fichiers). Vous pouvez ensuite corriger la cause et relancer les services.

> Le service `piusb-sync` surveille une image `/piusb.img` exposée en gadget USB et synchronise son contenu vers Nextcloud. Un état est conservé dans `~/.piusb-sync/state.csv` pour éviter les transferts répétitifs. Les fichiers `*.PTN` sont automatiquement transformés en `*.oma` lors du transfert vers Nextcloud.

## Mise à jour

Si vous êtes dans un clone git du dépôt, vous pouvez mettre à jour l'installation en vous plaçant dans le répertoire et en lançant :

```sh
sudo ./install.sh update
```

Cela effectuera un `git pull` puis recopiera les fichiers et redémarrera les services. Le script vous proposera optionnellement de reconfigurer les paramètres Nextcloud.

### Mettre à jour uniquement les paramètres Nextcloud

Pour reconfigurer les paramètres Nextcloud sans mettre à jour le dépôt :

```sh
sudo ./install.sh update
```

et répondez `o` quand le script vous demande si vous souhaitez reconfigurer Nextcloud.

Alternativement, vous pouvez éditer directement `/etc/piusb-sync.conf` :

```sh
sudo nano /etc/piusb-sync.conf
```

Puis redémarrer le service de synchronisation :

```sh
sudo systemctl restart piusb-sync.service
```

## Personnalisation

Les paramètres de configuration sont stockés dans `/etc/piusb-sync.conf` :

- **PIUSB_USER** : Utilisateur système pour la synchronisation (défini lors de l'installation)
- **PIUSB_HOSTNAME** : Hostname du Pi (ex : `raspberrypi`, `pi-nidek`)
  - Détecté automatiquement lors de l'installation
  - Utilisé pour le nom du mot de passe d'application et le chemin Nextcloud
- **NEXTCLOUD_URL** : URL de votre serveur Nextcloud
- **NEXTCLOUD_USER** : Nom d'utilisateur Nextcloud
- **NEXTCLOUD_PASSWORD** : Mot de passe d'application Nextcloud
- **NEXTCLOUD_PATH** : Chemin de destination sur Nextcloud (défaut : `{PIUSB_HOSTNAME}`)

Vous pouvez également modifier les variables dans `/usr/local/bin/sync-piusb-to-nextcloud.sh` :

- `MOUNT_POINT` : Point de montage de l'image USB (défaut : `/mnt/piusb`)
- `IMG` : Chemin de l'image disque USB (défaut : `/piusb.img`)
- `NEXTCLOUD_REMOTE` : Nom de la remote rclone (défaut : `nextcloud:`)
- `SCAN_INTERVAL` : Intervalle de scan en secondes (défaut : 15)
- `SLEEP_AFTER_EVENT` : Délai après un événement en secondes (défaut : 1)
- `RCLONE_OPTS` : Options de rclone (défaut : `--transfers=4 --checkers=8`)

## Dépannage rapide

### `piusb-gadget.service` en échec

Cause fréquente : l'image disque `/piusb.img` n'existe pas encore.

Exemple de création d'une image de 1 GiB en FAT32 :

```sh
sudo truncate -s 1G /piusb.img
sudo mkfs.vfat /piusb.img
```

Puis redémarrage des services :

```sh
sudo systemctl restart piusb-gadget.service
sudo systemctl restart piusb-mount.service
sudo systemctl restart piusb-sync.service
```

Diagnostic :

```sh
systemctl status piusb-gadget.service
journalctl -xeu piusb-gadget.service
```

### `piusb-sync.service` n'envoie pas les fichiers

**Cause probable** : Paramètres Nextcloud incorrects

Vérifiez la configuration :

```sh
cat /etc/piusb-sync.conf
```

Vérifiez la configuration rclone :

```sh
cat ~/.config/rclone/rclone.conf
```

Testez la connexion Nextcloud avec rclone :

```sh
sudo -u <PIUSB_USER> rclone ls nextcloud:/
```

Consultez les logs du service :

```sh
journalctl -xeu piusb-sync.service
```

### Erreurs de permissions rclone

Si rclone ne peut pas accéder aux fichiers de configuration :

```sh
sudo ls -la ~/.config/rclone/
```

Assurez-vous que le fichier `rclone.conf` est owné par `PIUSB_USER` :

```sh
sudo chown <PIUSB_USER>:<PIUSB_USER> ~/.config/rclone/rclone.conf
sudo chmod 600 ~/.config/rclone/rclone.conf
```

### Générer un mot de passe d'application Nextcloud

1. Connectez-vous à Nextcloud
2. Allez dans **Paramètres** (en haut à droite)
3. Allez dans l'onglet **Sécurité**
4. Descendez jusqu'à la section **Mots de passe d'application**
5. Entrez le **nom du mot de passe** fourni lors de l'installation : `{hostname}-sync`
6. Cliquez sur **Générer le mot de passe**
7. Utilisez le mot de passe généré

### Modifier le hostname du Pi

Si vous souhaitez changer le hostname du Pi **avant** l'installation :

```sh
sudo hostnamectl set-hostname nouveau-nom
```

Puis redémarrez et lancez l'installation.

**Note** : Ne changez pas le hostname **après** l'installation, car cela causerait une incohérence avec les paramètres stockés dans `/etc/piusb-sync.conf`.

--- *(Ce README est généré automatiquement par l'assistant pour clarifier la procédure.)*

```
```

---

**Remarque :**
- Assurez-vous que votre Raspberry Pi a accès à Internet lors de l'installation.
- Pour une installation locale de Nextcloud, vous pouvez suivre [cette documentation](https://docs.nextcloud.com/server/latest/admin_manual/installation.html) pour configurer un serveur Nextcloud sur le même réseau local ou sur un autre serveur.

### Fichiers Associés

- **`README.md`**
- **`etc/systemd/system/piusb-gadget.service`**
- **`etc/systemd/system/piusb-mount.service`**
- **`etc/systemd/system/piusb-sync.service`**

### Documentation et Liens Utiles

- [Installation de Debian Trixie](https://www.raspberrypi.org/documentation/installation/installing-images/)
- [Documentation Nextcloud (Admin Manual)](https://docs.nextcloud.com/server/latest/admin_manual/index.html)
- [Présentation du Service Nextcloud](https://nextcloud.com/)

---

### Événements Subséquents

Une fois que vous avez mis à jour le fichier `README.md`, assurez-vous de vérifier les autres fichiers pour s'assurer qu'ils sont bien configurés et fonctionnent correctement avec vos nouveaux pré-requis.

Si vous avez besoin d'aide supplémentaire ou si vous rencontrez des problèmes lors de la mise en place de ces pré-requis, n'hésitez pas à me contacter !

---
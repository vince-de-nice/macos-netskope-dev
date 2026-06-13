# Guide administrateur

Ce document explique comment déployer **macos-netskope-dev** sur les postes macOS de développeurs derrière **Netskope**.

> **Go-live Flutter complet (Android + iOS) :** suivez **[CHECKLIST-IT-FLUTTER.md](CHECKLIST-IT-FLUTTER.md)** — ce script ne couvre que la **couche CLI**. Pour **Xcode / App Store**, l'admin Netskope doit appliquer **[NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md)** en amont ou en parallèle.

## Point essentiel : configuration par utilisateur

Le script **n'est pas** une installation machine-wide (contrairement au client Netskope). Il écrit dans le **home de l'utilisateur qui l'exécute** :

| Ressource | Emplacement |
|-----------|-------------|
| Truststore Gradle | `~/.gradle/macos-netskope-dev/` |
| Gradle | `~/.gradle/gradle.properties` |
| Variables d'env | `~/.zshrc`, `~/.zprofile` ou `~/.bash_profile` (bloc marqué) |
| Git | `~/.gitconfig` (`http.sslCAInfo`) |
| npm | `~/.npmrc` |
| gcloud | `~/.config/gcloud/` |
| État / rollback | `~/.gradle/macos-netskope-dev/state/manifest.json` |

**Chaque développeur** doit disposer de sa propre exécution (ou un admin doit lancer le script **explicitement pour son compte**).

Le `sudo` interne au script sert uniquement à **lire le trousseau système** pour exporter les CA Netskope — il ne remplace pas l'identité cible de la configuration.

---

## Ce qu'il ne faut pas faire

| Commande | Problème |
|----------|----------|
| `sudo ./install.sh --all --netskope` | Configure **root** (`/var/root/.gradle`, etc.) — inutile pour le dev |
| Admin SSH sur son compte, `./install.sh` sans `--as-user` | Configure le compte **admin**, pas le développeur |
| Copier manuellement les fichiers entre utilisateurs | Chemins absolus dans `gradle.properties`, git/npm par user |

Le script **refuse** une exécution en root sans `--as-user`.

---

## Scénario 1 — Développeur en autonomie (recommandé)

Le développeur clone ou reçoit le script, puis exécute :

```bash
cd /chemin/vers/macos-netskope-dev
./install.sh --all --netskope --yes
source ~/.zshrc
./install.sh --status
```

Mot de passe admin demandé **une fois** (accès Keychain système). Aucune action IT requise au-delà de la distribution du script et de la doc.

---

## Scénario 2 — Admin à distance (SSH)

### Option A : `--as-user` (recommandée)

Depuis une session admin (root ou compte avec `sudo`) :

```bash
cd /chemin/vers/macos-netskope-dev
sudo ./install.sh --as-user jdupont --all --netskope --yes
```

Le script :
1. **Exporte les CA Netskope en root** (accès Keychain système — privilèges admin)
2. **Se ré-exécute** avec l'identité `jdupont` pour configurer son home (`/Users/jdupont/`)

> Le développeur **n'a pas besoin** de droits sudo pour la phase de configuration. Seul l'admin doit être privilégié pour l'export Keychain.

### Option B : `sudo -u` explicite

Cette option **ne déclenche pas l'export Keychain root**. À réserver si les certificats sont déjà exportés ou si le développeur a sudo :

```bash
sudo -u jdupont env HOME=/Users/jdupont \
  /chemin/vers/macos-netskope-dev/install.sh --all --netskope --yes
```

Préférez l'**Option A** (`sudo ./install.sh --as-user`) pour le déploiement IT standard.

### Vérification côté admin

```bash
sudo -u jdupont ./install.sh --status
ls -la /Users/jdupont/.gradle/macos-netskope-dev/
grep -A2 'macos-netskope-dev' /Users/jdupont/.zshrc
```

Demander au développeur d'**ouvrir un nouveau terminal** ou de lancer `source ~/.zshrc` (les IDE déjà ouverts peuvent ne pas voir les variables).

---

## Scénario 3 — Déploiement MDM / Jamf / Intune

> **Microsoft Intune :** guide complet pas-à-pas → **[INTUNE.md](INTUNE.md)**  
> (Proactive Remediation, package versionné, LaunchDaemon, `--compliance --json`).

Exécuter le script **via l'admin système** pour exporter le Keychain, puis configurer l'utilisateur connecté :

```bash
#!/bin/bash
INSTALL_DIR="/usr/local/share/macos-netskope-dev"
TARGET_USER="$(/usr/bin/stat -f%Su /dev/console)"

[[ "$TARGET_USER" == "root" || -z "$TARGET_USER" ]] && exit 0
[[ -x "$INSTALL_DIR/install.sh" ]] || exit 0

# Idempotent : ne relance que si pas déjà installé (vérifier aussi les stacks)
if ! sudo -u "$TARGET_USER" "$INSTALL_DIR/install.sh" --status 2>/dev/null | grep -q 'Installation opérationnelle'; then
  sudo "$INSTALL_DIR/install.sh" --as-user "$TARGET_USER" --all --netskope --yes
fi
```

> **Important :** utiliser `sudo ./install.sh --as-user` (pas `sudo -u` seul) pour que l'export Keychain s'exécute en root.

Points d'attention MDM :

- Placer le dépôt dans un chemin **lisible** par tous (`/usr/local/share/...`)
- Exécuter **par utilisateur connecté** (`stat -f%Su /dev/console`)
- Prévoir une **relance** après mise à jour du client Netskope (nouvelle CA)
- Le simulateur iOS (`--simulator`) nécessite un simulateur **déjà démarré** — à réserver au self-service dev

---

## Scénario 4 — Rollback par l'admin

Pour annuler la configuration d'un développeur :

```bash
sudo -u jdupont /chemin/vers/install.sh --rollback
```

Ou avec `--as-user` :

```bash
sudo ./install.sh --as-user jdupont --rollback
```

---

## Stacks à déployer selon le profil

| Profil | Commande suggérée |
|--------|-------------------|
| Flutter mobile (Android + iOS) | `--all --netskope` |
| Flutter + Firebase | `--gradle --dart --git --node --ruby --netskope` (ou `--all`) |
| Android seul | `--gradle --dart --netskope` |
| iOS seul | `--dart --git --ruby --netskope` |

Détail par stack : [README.md](README.md) et `./install.sh --docs <stack>`.

---

## Prérequis machine

### Client Netskope et script (couche CLI)

- macOS avec **client Netskope** installé et CA présente dans le Keychain
- Certificats Netskope visibles : `./install.sh --list-netskope`
- Outils selon stacks : `git`, `java`/`keytool` (Gradle), `openssl`, optionnellement `npm`, `gcloud`, Xcode (`--simulator`)

### Flutter iOS — prérequis IT Netskope (couche Apple)

**Obligatoire** si les développeurs installent Xcode ou des runtimes simulateur sur le réseau inspecté :

| Prérequis | Document | Validé ? |
|-----------|----------|----------|
| CPA **Apple App Store** (Mac) en Bypass | [NETSKOPE-APPLE-IT.md §4 étape 1](NETSKOPE-APPLE-IT.md#étape-1--vérifier-le-cpa-prédéfini-apple-app-store-mac) | ☐ |
| SSL Decryption bypass domaines Apple (Xcode, Apple ID, CDN) | [NETSKOPE-APPLE-IT.md §4 étape 2](NETSKOPE-APPLE-IT.md#étape-2--bypass-ssl-decryption-pour-domaines-apple-xcode-simulateurs-apple-id) | ☐ |
| Poste pilote : App Store + téléchargement runtime Xcode | [NETSKOPE-APPLE-IT.md §6](NETSKOPE-APPLE-IT.md#6-validation-bout-en-bout-poste-pilote) | ☐ |

Sans ces prérequis, `./install.sh --all` peut réussir alors que **Xcode reste inutilisable**.

---

## Dépannage admin

| Symptôme | Cause probable | Action |
|----------|----------------|--------|
| « Installation en root interdite » | `sudo ./install.sh` sans `--as-user` | Ajouter `--as-user <login>` |
| Dev dit que ça ne marche pas, `--status` OK chez admin | Config sur mauvais compte | Relancer avec `--as-user` |
| IDE ne voit pas les variables | Terminal non rechargé | `source ~/.zshrc`, redémarrer IDE |
| `--list-netskope` vide | Netskope absent ou CA non déployée | Vérifier client Netskope / IT |
| Gradle OK, `flutter pub get` échoue | Stack `--dart` absente | `./install.sh --dart --netskope` |
| Simulateur iOS SSL -1200 | Stack `--simulator` non faite | Dev démarre simulateur, relance `--simulator` |
| Gradle ne prend pas le truststore | Daemon Gradle actif | `cd android && ./gradlew --stop`, relancer le build |
| App Store / Xcode ne téléchargent pas | Bypass Apple Netskope manquant | [NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md) — pas le script |
| Xcode OK, `pod install` échoue | Stacks Ruby/Git ou script absent | `./install.sh --ruby --git --netskope --yes` |
| `--rollback` après install partielle | Comportement corrigé en v4.1 (manifest fusionné) | Mettre à jour le script si version < 4.1 |

Rapport d'installation : `~/.gradle/macos-netskope-dev/install-report.txt`

---

## Références

- [README développeur](README.md)
- [Checklist IT Flutter (go-live)](CHECKLIST-IT-FLUTTER.md)
- [Netskope — Apple / Xcode (admin réseau)](NETSKOPE-APPLE-IT.md)
- [Guide développeur iOS](DEV-IOS-XCODE.md)
- [Microsoft Intune](INTUNE.md)
- [Netskope — Configuring Developer Tools](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493)

# Guide administrateur

Ce document explique comment déployer **gradle-corporate-truststore** sur les postes macOS de développeurs derrière **Netskope**.

## Point essentiel : configuration par utilisateur

Le script **n'est pas** une installation machine-wide (contrairement au client Netskope). Il écrit dans le **home de l'utilisateur qui l'exécute** :

| Ressource | Emplacement |
|-----------|-------------|
| Truststore Gradle | `~/.gradle/corporate-truststore/` |
| Gradle | `~/.gradle/gradle.properties` |
| Variables d'env | `~/.zshrc` (bloc marqué) |
| Git | `~/.gitconfig` (`http.sslCAInfo`) |
| npm | `~/.npmrc` |
| gcloud | `~/.config/gcloud/` |
| État / rollback | `~/.gradle/corporate-truststore/state/manifest.json` |

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
cd /chemin/vers/gradle-corporate-truststore
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
cd /chemin/vers/gradle-corporate-truststore
sudo ./install.sh --as-user jdupont --all --netskope --yes
```

Le script :
1. **Exporte les CA Netskope en root** (accès Keychain système — privilèges admin)
2. **Se ré-exécute** avec l'identité `jdupont` pour configurer son home (`/Users/jdupont/`)

> Le développeur **n'a pas besoin** de droits sudo pour la phase de configuration. Seul l'admin doit être privilégié pour l'export Keychain.

### Option B : `sudo -u` explicite

```bash
sudo -u jdupont env HOME=/Users/jdupont \
  /chemin/vers/gradle-corporate-truststore/install.sh --all --netskope --yes
```

### Vérification côté admin

```bash
sudo -u jdupont ./install.sh --status
ls -la /Users/jdupont/.gradle/corporate-truststore/
grep -A2 'gradle-corporate-truststore' /Users/jdupont/.zshrc
```

Demander au développeur d'**ouvrir un nouveau terminal** ou de lancer `source ~/.zshrc` (les IDE déjà ouverts peuvent ne pas voir les variables).

---

## Scénario 3 — Déploiement MDM / Jamf / Intune

Exécuter le script **dans le contexte utilisateur** au login ou à la première connexion réseau :

```bash
#!/bin/bash
INSTALL_DIR="/usr/local/share/gradle-corporate-truststore"
TARGET_USER="$(/usr/bin/stat -f%Su /dev/console)"
TARGET_HOME="$(eval echo "~$TARGET_USER")"

[[ "$TARGET_USER" == "root" || -z "$TARGET_USER" ]] && exit 0
[[ -x "$INSTALL_DIR/install.sh" ]] || exit 0

# Idempotent : ne relance que si pas déjà installé
if [[ ! -f "$TARGET_HOME/.gradle/corporate-truststore/state/manifest.json" ]]; then
  sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" \
    "$INSTALL_DIR/install.sh" --all --netskope --yes
fi
```

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

- macOS avec **client Netskope** installé et CA présente dans le Keychain
- Certificats Netskope visibles : `./install.sh --list-netskope`
- Outils selon stacks : `git`, `java`/`keytool` (Gradle), `openssl`, optionnellement `npm`, `gcloud`, Xcode (`--simulator`)

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
| `--rollback` après install partielle | Comportement corrigé en v4.1 (manifest fusionné) | Mettre à jour le script si version < 4.1 |

Rapport d'installation : `~/.gradle/corporate-truststore/install-report.txt`

---

## Références

- [README développeur](README.md)
- [Netskope — Configuring Developer Tools](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493)

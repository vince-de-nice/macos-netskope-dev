# Documentation — gradle-corporate-truststore

Configuration TLS Netskope pour le développement **Flutter sur macOS d'entreprise**.

## Qui fait quoi ?

| Rôle | Document | Commande type |
|------|----------|---------------|
| **Développeur** | Ce README | `./install.sh --all --netskope --yes` |
| **Administrateur IT** | **[ADMIN.md](ADMIN.md)** | `sudo ./install.sh --as-user <login> --all --netskope --yes` |

> **Important :** la configuration est **par utilisateur** (`~/.gradle`, `~/.zshrc`, git/npm globaux). Un admin qui lance le script sur son propre compte ne configure **pas** les postes des développeurs. Voir [ADMIN.md](ADMIN.md).

## Principe

Netskope intercepte le HTTPS et re-signer le trafic avec une **CA d'entreprise**. Le Keychain macOS fait confiance à cette CA, mais la plupart des outils CLI utilisent **leur propre magasin de certificats**.

Ce projet configure chaque stack individuellement ou via `--all`.

## Stacks

| Stack | Commande | Doc |
|-------|----------|-----|
| Gradle / Android | `--gradle` | [gradle.md](stacks/gradle.md) |
| Profil shell | `--shell` | [shell.md](stacks/shell.md) |
| Dart / Flutter | `--dart` | [dart.md](stacks/dart.md) |
| Git | `--git` | [git.md](stacks/git.md) |
| Node / npm | `--node` | [node.md](stacks/node.md) |
| Python / pip | `--python` | [python.md](stacks/python.md) |
| Ruby / CocoaPods | `--ruby` | [ruby.md](stacks/ruby.md) |
| curl / Homebrew | `--curl` | [curl.md](stacks/curl.md) |
| Google Cloud SDK | `--gcloud` | [gcloud.md](stacks/gcloud.md) |
| AWS CLI | `--aws` | [aws.md](stacks/aws.md) |
| Simulateur iOS | `--simulator` | [simulator.md](stacks/simulator.md) |

## Usage rapide (développeur)

```bash
# Tout configurer (recommandé)
./install.sh --all --netskope --yes
source ~/.zshrc

# Une stack seule
./install.sh --dart --netskope

# Documentation d'une stack
./install.sh --docs gradle

# État actuel
./install.sh --status

# Annuler
./install.sh --rollback
```

## Usage rapide (administrateur)

```bash
# Installation pour le développeur jdupont
sudo ./install.sh --as-user jdupont --all --netskope --yes

# Vérification
sudo -u jdupont ./install.sh --status

# Rollback
sudo ./install.sh --as-user jdupont --rollback
```

Détails MDM, pièges (`sudo` sans `--as-user`), dépannage : **[ADMIN.md](ADMIN.md)**.

## Matrice : quand configurer quoi ?

| Activité Flutter | Stacks nécessaires |
|------------------|-------------------|
| `flutter pub get` | `--dart` (ou `--shell`) |
| Build Android (`flutter build apk`) | `--gradle` + `--dart` |
| Build iOS (`flutter build ios`) | `--dart` + `--ruby` + `--git` |
| `pod install` | `--ruby` + `--git` |
| Firebase CLI | `--node` |
| Projet Flutter + Firebase (complet) | `--gradle --dart --git --node --ruby` ou `--all` |
| Téléchargement SDK Flutter | `--dart` + `--curl` |
| App HTTPS en simulateur iOS | `--simulator` (runtime) |
| CI Docker local | Hors scope macOS (voir doc Netskope Docker) |

## Fichiers créés (par utilisateur)

| Fichier | Rôle |
|---------|------|
| `~/.gradle/corporate-truststore/corporate-truststore.p12` | Truststore JVM Gradle |
| `~/.gradle/corporate-truststore/nscacert_combined.pem` | Bundle CA pour CLI |
| `~/.gradle/gradle.properties` | JVM args Gradle |
| Variables d'env | `~/.zshrc`, `~/.zprofile` ou `~/.bash_profile` (bloc marqué) |
| `~/.gradle/corporate-truststore/state/manifest.json` | État pour rollback (fusionné à chaque stack) |

## Mot de passe truststore

Par défaut : `changeit` (truststore PKCS12 local, non sensible).

Alternative recommandée :

```bash
export GCT_STORE_PASSWORD="votre-mot-de-passe"
./install.sh --all --netskope --yes
```

Le mot de passe n'est **pas** stocké dans le manifest (uniquement dans `gradle.properties`).

## Références

- [Guide administrateur](ADMIN.md)
- [Netskope — Configuring Developer Tools](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493)
- [Netskope — Certificate Pinned Applications](https://docs.netskope.com/en/certificate-pinned-applications/)

## Tests automatisés

Sans Netskope installé (certificats mock injectés temporairement dans le Keychain) :

```bash
./test/run-tests.sh
./test/run-tests.sh --verbose
```

Couverture : syntaxe bash, **shellcheck** (`.shellcheckrc`), unitaires (admin, gradle, shell, bundle PEM, manifest merge), truststore **keytool réel**, TLS Java, dry-run `--all` / Firebase, **E2E réel Gradle** (si sudo sans mot de passe), rollback complet, garde anti-root, installations incrémentales.

```bash
# shellcheck manuel (depuis la racine du projet)
shellcheck -S warning -x install.sh lib/*.sh test/run-tests.sh
```

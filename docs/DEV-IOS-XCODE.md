# Guide développeur — Flutter iOS, Xcode et Netskope

Ce document explique **ce que vous configurez vous-même** vs **ce que l'IT doit faire**, pour développer Flutter **iOS + Android** derrière Netskope.

> Installation CLI : [README.md](README.md)  
> Si Xcode ou l'App Store ne fonctionne pas : **ticket IT** avec [NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md) — ce n'est **pas** corrigeable par `./install.sh` seul.

---

## Deux volets distincts

| Volet | Outils | Qui ? | Commande / action |
|-------|--------|-------|-------------------|
| **CLI & build** | Gradle, Dart, Git, CocoaPods, npm… | **Vous** | `./install.sh --all --netskope --yes` |
| **Apple (Store, Xcode, runtimes)** | App Store, Xcode, Apple ID | **IT Netskope** | Bypass réseau — voir checklist IT |

Sans le volet Apple, vous pouvez avoir `./install.sh --status` **OK** et rester bloqué sur l'installation de Xcode.

---

## Ordre recommandé (première installation)

1. **Vérifier** que l'IT a appliqué les bypass Apple ([CHECKLIST-IT-FLUTTER.md](CHECKLIST-IT-FLUTTER.md) phase B)
2. **Installer Xcode** (App Store ou [developer.apple.com/download](https://developer.apple.com/download/))
3. Ouvrir Xcode une fois → accepter licence → installer composants proposés
4. **Xcode → Settings → Platforms** → télécharger le runtime iOS dont vous avez besoin
5. Exécuter le script CLI :

```bash
cd /chemin/vers/macos-netskope-dev
./install.sh --all --netskope --yes
source ~/.zshrc
./install.sh --status
```

6. Vérifier Flutter :

```bash
flutter doctor
flutter pub get
cd ios && pod install && cd ..
```

7. **Simulateur + APIs HTTPS** (si vous testez le réseau en simulateur) :

```bash
# Démarrer un simulateur iOS d'abord
./install.sh --simulator --netskope --yes
```

Détail simulateur : [stacks/simulator.md](stacks/simulator.md)

---

## Matrice : mon problème vient d'où ?

| Symptôme | Cause probable | Action |
|----------|----------------|--------|
| App Store ne se connecte pas | Bypass Apple manquant (IT) | Ticket IT — [NETSKOPE-APPLE-IT.md §8](NETSKOPE-APPLE-IT.md#8-modèle-de-ticket--demande-changement) |
| Xcode bloqué sur « Downloading… » | `gdmf.apple.com` / CDN Xcode inspectés | Ticket IT |
| `flutter pub get` échoue (certificat) | Stack Dart / script | `./install.sh --dart --netskope --yes` |
| `pod install` échoue | Stack Ruby / Git | `./install.sh --ruby --git --netskope --yes` |
| Build Android échoue (Maven) | Stack Gradle | `./install.sh --gradle --netskope --yes` puis `./gradlew --stop` |
| App simulateur : SSL -1200 | Runtime simulateur | Simulateur **booté**, puis `--simulator` |
| IDE ne voit pas les variables | Terminal non rechargé | `source ~/.zshrc`, **redémarrer** VS Code / Android Studio |
| Tout OK sauf un registry privé | Domaine interne | Demander bypass SSL IT pour ce domaine |

---

## Xcode et App Store — limites du script

Ces éléments **n'utilisent pas** le bundle PEM ni `gradle.properties` :

- Application **App Store**
- Téléchargements **Xcode** (Platforms, additional components)
- **Connexion Apple ID**
- **Transporter**, notarisation, App Store Connect API

Ils exigent une **politique Netskope** côté IT (certificate pinning Apple).

**Contournement temporaire** (si IT en attente) : installer Xcode sur un réseau **sans inspection SSL** (domicile, partage 4G), puis revenir sur le réseau entreprise pour le développement quotidien une fois Xcode en place.

---

## Simulateur iOS vs appareil physique

| Environnement | Configuration TLS Netskope |
|---------------|----------------------------|
| **Simulateur** (dev API HTTPS) | `./install.sh --simulator --netskope` + confiance CA dans Réglages simulateur |
| **Appareil physique** | Profil MDM ou installation manuelle CA entreprise sur l'appareil — **hors scope** de ce script |
| **Build** (`flutter build ios`) | Stacks `--dart`, `--ruby`, `--git`, `--gradle` — pas `--simulator` |

---

## Commandes utiles

```bash
# État global
./install.sh --status

# Conformité (Intune / IT)
./install.sh --compliance

# Lister certificats Netskope Keychain
./install.sh --list-netskope

# Doc d'une stack
./install.sh --docs ruby

# Annuler toute la config script
./install.sh --rollback
```

---

## Après chaque mise à jour IT ou Netskope

Si l'IT renouvelle la CA Netskope ou pousse une nouvelle version du script :

```bash
./install.sh --all --netskope --yes
source ~/.zshrc
cd android && ./gradlew --stop
```

---

## Où demander de l'aide

| Sujet | Contact |
|-------|---------|
| App Store, Xcode download, Apple ID | **IT réseau / Netskope** — doc [NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md) |
| `flutter pub get`, Gradle, CocoaPods | `./install.sh --status` puis équipe plateforme / doc [README.md](README.md) |
| Intune, poste non conforme | IT endpoint — [INTUNE.md](INTUNE.md) |

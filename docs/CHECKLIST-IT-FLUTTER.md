# Checklist IT — déploiement Flutter macOS derrière Netskope

Guide **pas-à-pas** pour les équipes IT (endpoint, réseau, sécurité) afin qu'un développeur Flutter puisse travailler **Android + iOS** sans blocage TLS.

> Utilisez ce document comme **runbook de go-live** et comme base de **revue sécurité**.

---

## Vue d'ensemble des responsabilités

| Composant | Responsable | Document |
|-----------|-------------|----------|
| Client Netskope + CA Keychain | IT endpoint / Intune | [INTUNE.md](INTUNE.md) (si Intune) |
| **Bypass Apple / Xcode / App Store** | **Admin Netskope** | **[NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md)** |
| Truststores CLI (Gradle, Dart, Git…) | Script macos-netskope-dev | [ADMIN.md](ADMIN.md) |
| Distribution script (Intune / manuel) | IT endpoint | [INTUNE.md](INTUNE.md) |
| Installation Xcode, runtimes, dev day-to-day | Développeur | [DEV-IOS-XCODE.md](DEV-IOS-XCODE.md) |

---

## Phase A — Décisions avant déploiement

### A1. Périmètre utilisateurs

- [ ] Groupe Entra ID / AD défini : ex. `SG-Dev-Flutter-macOS`
- [ ] Politique documentée : postes **uniquement** dev mobile vs tous les Mac

**Justification :** Les bypass Apple réduisent la visibilité sur une partie du trafic ; limiter au groupe dev minimise la surface.

### A2. Choix bypass Apple

- [ ] Option retenue (cocher une) :
  - [ ] **A** — CPA Apple App Store + SSL Decryption bypass domaines (recommandé)
  - [ ] **B** — VLAN / réseau dev sans inspection SSL
  - [ ] **C** — Installation Xcode hors réseau entreprise (procédure manuelle)

Documenter le choix et l'approbation sécurité : _______________

Référence arbitrage : [NETSKOPE-APPLE-IT.md §3](NETSKOPE-APPLE-IT.md#31-matrice-de-décision-entreprise)

### A3. Ordre de déploiement validé

```
Netskope client → Bypass Apple → macos-netskope-dev → Xcode (dev) → validation
```

**Ne pas** déployer macos-netskope-dev seul en espérant qu'iOS fonctionne.

---

## Phase B — Infrastructure Netskope

### B1. Client Netskope

- [ ] Client installé sur les Mac du groupe dev
- [ ] CA Netskope visible dans Keychain (`./install.sh --list-netskope` ≥ 1 certificat)
- [ ] Steering config correcte (on-prem / off-prem si Dynamic Steering)

### B2. Bypass écosystème Apple (obligatoire pour iOS)

Suivre **[NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md)** intégralement :

- [ ] Étape 1 — CPA **Apple App Store** (Mac) en Bypass
- [ ] Étape 2 — SSL Decryption **Do Not Decrypt** — domaines Apple minimaux
- [ ] Étape 3 (si besoin) — CPA custom processus Xcode / Store
- [ ] Propagation attendue (~15 min) ou check-in client forcé

### B3. Bypass DevTools (optionnel, au-delà du script)

Si des services restent bloqués (registry privé, API interne) :

- [ ] Politique SSL Decryption bypass pour domaines dev internes
- [ ] Référence : [Netskope DevTools guide](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493)

---

## Phase C — macos-netskope-dev

### C1. Distribution

Choisir un mode :

- [ ] **Intune** — [INTUNE.md](INTUNE.md) : build-release → deploy package → Proactive Remediation
- [ ] **Manuel / Jamf** — [ADMIN.md](ADMIN.md) scénario 3
- [ ] **Autonomie dev** — [ADMIN.md](ADMIN.md) scénario 1

### C2. Installation

- [ ] Chemin standard : `/usr/local/share/macos-netskope-dev`
- [ ] Exécution : `sudo ./install.sh --as-user <login> --all --netskope --yes`
- [ ] **Pas** `sudo ./install.sh` sans `--as-user`

### C3. Conformité

- [ ] `./install.sh --compliance --json` → exit **0** sur poste pilote
- [ ] Intune detect/remediate configuré (si applicable)

---

## Phase D — Validation pilote (1 à 3 postes)

Exécuter sur chaque poste pilote :

### D1. Couche Apple (IT)

| Test | OK ? |
|------|------|
| App Store accessible, recherche Xcode | ☐ |
| Téléchargement composant Xcode / runtime simulateur | ☐ |
| Connexion Apple ID dans Xcode | ☐ |

### D2. Couche CLI (script)

| Test | OK ? |
|------|------|
| `./install.sh --compliance` exit 0 | ☐ |
| `flutter pub get` | ☐ |
| `cd android && ./gradlew dependencies` (ou build) | ☐ |
| `cd ios && pod install` | ☐ |

### D3. Couche simulateur (dev)

| Test | OK ? |
|------|------|
| `./install.sh --simulator --netskope` (simulateur booté) | ☐ |
| App Flutter appelle API HTTPS sans erreur -1200 | ☐ |

### D4. IDE

| Test | OK ? |
|------|------|
| Nouveau terminal : `source ~/.zshrc`, variables CA présentes | ☐ |
| Android Studio / VS Code redémarrés après install | ☐ |
| `./gradlew --stop` puis build Android | ☐ |

**Critère go-live :** 100 % des cases D1 + D2 sur pilote ; D3 si équipe fait du iOS simulateur.

---

## Phase E — Déploiement général

- [ ] Communication aux devs : [DEV-IOS-XCODE.md](DEV-IOS-XCODE.md) + [README.md](README.md)
- [ ] Runbook support L1 : tableau dépannage [ADMIN.md](ADMIN.md) + [NETSKOPE-APPLE-IT.md §7](NETSKOPE-APPLE-IT.md#7-dépannage-it)
- [ ] Procédure rotation CA Netskope → relance `intune-remediate.sh` ou `./install.sh --all --netskope --yes`
- [ ] Procédure mise à jour script → nouvelle archive + détection `script_version_outdated`

---

## Phase F — Ce que IT ne doit pas promettre

| Affirmation incorrecte | Réalité |
|------------------------|---------|
| « Le script configure Xcode » | Non — bypass Netskope requis |
| « Une seule install suffit pour toujours » | Relance après rotation CA, mise à jour script, nouveau simulateur |
| « Le simulateur est inclus dans --all » | Non — `--simulator` explicite |
| « Android Studio hérite du profil shell » | Non — redémarrer IDE ; Gradle via script OK |
| « CI Linux couverte » | Hors scope — macOS dev poste uniquement |

---

## Modèle de communication aux développeurs

```
Objet : Environnement Flutter macOS — prérequis et configuration

Le déploiement TLS pour Flutter comprend deux volets :

1. IT a configuré Netskope pour Xcode et l'App Store (certificate pinning Apple).
2. Vous devez exécuter (une fois, ou via Intune automatiquement) :
   ./install.sh --all --netskope --yes
   source ~/.zshrc

Guides :
- Usage quotidien : docs/README.md
- Xcode / simulateur : docs/DEV-IOS-XCODE.md

Support :
- Gradle, pub, pod : ./install.sh --status
- App Store / Xcode : ticket IT réseau (template NETSKOPE-APPLE-IT.md §8)
```

---

## Références rapides

- [NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md) — bypass Apple détaillé
- [ADMIN.md](ADMIN.md) — déploiement script
- [INTUNE.md](INTUNE.md) — Microsoft Intune
- [DEV-IOS-XCODE.md](DEV-IOS-XCODE.md) — guide développeur iOS

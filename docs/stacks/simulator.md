# Stack : Simulateur iOS (runtime)

## Résumé

Ajoute les certificats **Root Netskope** au Keychain du **simulateur iOS booté** pour que les apps fassent confiance au trafic intercepté **à l'exécution**.

**Commande :** `./install.sh --simulator --netskope`

> **Important :** distinct de la configuration **build** (Gradle, CocoaPods). Concerne le **runtime** de l'app dans le simulateur.

> **Prérequis :** Xcode et runtimes simulateur **installés** — nécessitent le bypass Netskope Apple côté IT ([NETSKOPE-APPLE-IT.md](../NETSKOPE-APPLE-IT.md)). Guide dev : [DEV-IOS-XCODE.md](../DEV-IOS-XCODE.md).

## Endpoints impactés

Tout HTTPS appelé par l'app Flutter **dans le simulateur** :
- APIs backend de dev/staging
- Firebase, analytics, CDNs
- Tout service passant par Netskope

## Erreur typique sans config

```
NSURLErrorDomain Code=-1200
An SSL error has occurred and a secure connection to the server cannot be made.
```

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| App appelle des APIs HTTPS en dev (simulateur) | **Oui** |
| App sans réseau / mock local | Non |
| Build iOS (`flutter build ios`) | Non (stack Ruby/Gradle) |
| **Appareil physique** iOS | Non — procédure manuelle séparée |
| Android Emulator | Non — magasin certificats Android distinct |

## Ce que le script configure

Pour chaque certificat Root exporté :
```bash
xcrun simctl keychain booted add-root-cert <cert.pem>
```

**Prérequis :** un simulateur iOS **démarré** (Booted).

Activation confiance totale (manuel) :
Réglages simulateur → Général → Informations → **Réglages des certificats de confiance** → activer la CA.

## Vérification manuelle

1. Démarrer un simulateur iOS
2. `./install.sh --simulator --netskope`
3. Lancer l'app et tester un appel HTTPS

## Limites

- À refaire pour **chaque simulateur** / après reset simulateur
- **Non réversible** automatiquement via `--rollback`
- Appareil physique : installer le profil CA via Réglages → VPN et gestion des appareils

## Nécessaire si…

- Tests API en simulateur derrière Netskope → **Oui**
- UI-only sans réseau → **Non**
- Inclus dans `--all` ? **Non** — explicite : `--all --simulator`

## Références

- [Apple Developer Forums — Certificat CA racine auto-signé dans le simulateur](https://developer.apple.com/forums/thread/124056) — `simctl keychain booted add-root-cert` et activation manuelle de la confiance
- [Documentation Xcode — Exécuter une app dans le simulateur](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) — contexte simulateur iOS ; aide CLI : `xcrun simctl help keychain`
- [Apple Platform Security — Certificats de confiance](https://support.apple.com/guide/security/trust-certificates-and-root-cas-sec509a87e405/web) — politique de confiance des CA racines sur les plateformes Apple
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — contexte TLS en environnement inspecté (runtime simulateur)

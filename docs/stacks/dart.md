# Stack : Dart / Flutter (CLI)

## Résumé

Configure **Dart VM** pour accepter la CA Netskope lors des téléchargements HTTPS (`pub get`, cache Flutter SDK).

**Commande :** `./install.sh --dart --netskope`

## Endpoints impactés

| Endpoint | Usage | Erreur sans config |
|----------|-------|-------------------|
| `pub.dev` | Packages Dart/Flutter (`flutter pub get`) | `CERTIFICATE_VERIFY_FAILED` |
| `pub.dartlang.org` | Ancien hôte pub (redirections) | Idem |
| `storage.googleapis.com` | Artifacts SDK Flutter, fonts, engine | Échec téléchargement cache |
| `github.com` | Packages Git (si source git dans pubspec) | Handshake error |
| `api.github.com` | Metadata packages | Idem |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| `flutter pub get` / `dart pub get` | **Oui** |
| `flutter pub upgrade` | **Oui** |
| `flutter upgrade` / cache SDK | **Oui** |
| `flutter create` | **Oui** (télécharge templates) |
| `flutter build` (si relance pub) | **Oui** |
| `flutter run` (deps déjà en cache) | Non si cache OK |
| Build Android Gradle | Non (stack Gradle) |
| Build iOS CocoaPods | Non (stack Ruby) |

## Ce que le script configure

- Bundle PEM : `~/.gradle/macos-netskope-dev/nscacert_combined.pem`
- Variable dans `~/.zshrc` :
  ```bash
  export DART_VM_OPTIONS="--root-certs-file=${NETSKOPE_CA_BUNDLE}"
  ```

## Vérification manuelle

```bash
source ~/.zshrc
DART_VM_OPTIONS="--root-certs-file=$HOME/.gradle/macos-netskope-dev/nscacert_combined.pem" dart pub get
flutter pub get -v
```

## Limites connues

- Flutter **n'honore pas toujours** `DART_VM_OPTIONS` sur toutes les plateformes/versions
- Le script **fusionne** vos `DART_VM_OPTIONS` existants (ex. `--enable-experiment=…`) avec `--root-certs-file`
- Contournement IT : bypass SSL pour `*.pub.dev`, `storage.googleapis.com`

## Nécessaire si…

- Vous utilisez **uniquement** des dépendances déjà en cache et ne mettez jamais à jour Flutter → optionnel
- Toute autre situation de dev Flutter normal → **recommandé**

## Références

- [Dart — Troubleshooting pub](https://dart.dev/tools/pub/troubleshoot) — erreurs réseau, proxy (`https_proxy`) et connectivité `pub.dev`
- [Dart SDK — DART_VM_OPTIONS et flags VM](https://dart.googlesource.com/sdk.git/+/refs/tags/3.6.1/docs/Settings-VM-flags-in-standalone-executables.md) — passage de `--root-certs-file` via `DART_VM_OPTIONS`
- [dart:io SecurityContext](https://api.dart.dev/stable/dart-io/SecurityContext-class.html) — contexte TLS programmatique (apps Flutter)
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — section Dart / Flutter et Python 3.13+

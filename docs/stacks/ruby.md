# Stack : Ruby / CocoaPods

## Résumé

Configure `SSL_CERT_FILE` pour **Ruby** et **CocoaPods** (`pod install`).

**Commande :** `./install.sh --ruby --netskope`

## Endpoints impactés

| Endpoint | Usage Flutter/iOS | Erreur sans config |
|----------|-------------------|-------------------|
| `github.com/CocoaPods/Specs` | Index des pods | `SSL certificate problem` |
| `cdn.cocoapods.org` | Téléchargement pods | Idem |
| `repo1.maven.org` | (transitif via Gradle, pas Ruby) | — |
| Registre CDN pods (S3, etc.) | Artifacts natifs iOS | Handshake error |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| `pod install` / `pod update` | **Oui** |
| `flutter build ios` | **Oui** |
| `flutter run` sur iOS | **Oui** (première sync pods) |
| `flutter build apk` | Non |
| `flutter pub get` | Non |

## Ce que le script configure

- `SSL_CERT_FILE` dans le profil shell
- Recommandé en complément : `--git` (CocoaPods clone git)

## Vérification manuelle

```bash
cd ios && SSL_CERT_FILE=$HOME/.gradle/corporate-truststore/nscacert_combined.pem pod install
```

## Prérequis souvent nécessaires

- Git récent (Homebrew) : `brew install git`
- Stack `--git` pour les clones HTTPS

## Nécessaire si…

- Cible **iOS** ou **macOS** → **Oui**
- Android uniquement → **Non**

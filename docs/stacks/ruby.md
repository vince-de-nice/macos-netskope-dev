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
cd ios && SSL_CERT_FILE=$HOME/.gradle/macos-netskope-dev/nscacert_combined.pem pod install
```

## Prérequis souvent nécessaires

- Git récent (Homebrew) : `brew install git`
- Stack `--git` pour les clones HTTPS

## Nécessaire si…

- Cible **iOS** ou **macOS** → **Oui**
- Android uniquement → **Non**

## Références

- [OpenSSL — Variables d'environnement (`SSL_CERT_FILE`)](https://docs.openssl.org/3.6/man7/openssl-env/) — magasin CA utilisé par Ruby/OpenSSL (distinct du Keychain macOS)
- [Ruby OpenSSL — SSLError et magasins de certificats](https://mislav.net/2013/07/ruby-openssl/) — `OpenSSL::X509::DEFAULT_CERT_FILE`, contournements proxy d'entreprise
- [Netskope — Certificate Pinned Applications (DevTools)](https://docs.netskope.com/en/certificate-pinned-applications/) — Ruby/CocoaPods et contournements CPA Netskope
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — section Ruby / CocoaPods

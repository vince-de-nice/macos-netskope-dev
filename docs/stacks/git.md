# Stack : Git (HTTPS)

## Résumé

Configure Git pour utiliser le bundle CA Netskope lors des opérations **HTTPS**.

**Commande :** `./install.sh --git --netskope`

## Endpoints impactés

| Endpoint | Usage Flutter/iOS | Erreur sans config |
|----------|-------------------|-------------------|
| `github.com` | Plugins Flutter (git deps), CocoaPods Specs | `SSL certificate problem` |
| `gitlab.com` | Repos internes | Idem |
| `dev.azure.com` | Azure DevOps | Idem |
| `bitbucket.org` | Repos privés | Idem |
| `cdn.cocoapods.org` | (via curl/ruby, pas git direct) | — |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| `pod install` (clone Specs git) | **Oui** |
| `flutter pub get` avec deps `git:` | **Oui** |
| Clone manuel de plugins | **Oui** |
| `flutter pub get` (pub.dev only) | Non |
| Build Android Gradle | Non (Maven HTTPS = stack Gradle) |
| SSH (`git@github.com:`) | **Non** — SSH n'utilise pas ce certificat |

## Ce que le script configure

```bash
git config --global http.sslCAInfo ~/.gradle/corporate-truststore/nscacert_combined.pem
```

## Vérification manuelle

```bash
git ls-remote https://github.com/flutter/flutter.git HEAD
```

## Nécessaire si…

- Développement **iOS** avec CocoaPods → **Oui**
- Dépendances pub en `git:` → **Oui**
- Projet Android sans pods ni deps git → optionnel

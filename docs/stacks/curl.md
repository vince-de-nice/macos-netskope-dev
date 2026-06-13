# Stack : curl / Homebrew

## Résumé

Configure `CURL_CA_BUNDLE` pour **curl** et outils qui s'appuient dessus (dont **Homebrew**).

**Commande :** `./install.sh --curl --netskope`

## Endpoints impactés

| Endpoint | Usage dev Flutter | Erreur sans config |
|----------|---------------------|-------------------|
| `raw.githubusercontent.com` | Scripts install, Homebrew | `curl: (60) SSL certificate problem` |
| `github.com` | Téléchargements releases | Idem |
| `storage.googleapis.com` | SDK Flutter (via curl scripts) | Idem |
| `pub.dev` | Tests connectivité | Idem |
| Formulae Homebrew | `brew install` | Échec git/curl |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| Installation Flutter via git/curl | **Oui** |
| `brew install` (cocoapods, git, etc.) | **Oui** |
| `flutter` CLI directement | Non (Dart HttpClient) |
| Build projet | Non (sauf scripts curl CI) |

## Ce que le script configure

```bash
export CURL_CA_BUNDLE="${NETSKOPE_CA_BUNDLE}"
```

## Vérification manuelle

```bash
CURL_CA_BUNDLE=$HOME/.gradle/macos-netskope-dev/nscacert_combined.pem curl -I https://pub.dev
brew update
```

## Nécessaire si…

- Environnement déjà installé et stable → optionnel
- Installation initiale Mac / mises à jour Homebrew → **Recommandé**

## Références

- [curl — SSL Certificates](https://curl.se/docs/sslcerts.html) — fonctionnement des CA et bundles PEM
- [curl — TLS certificate verification](https://everything.curl.dev/usingcurl/tls/verify.html) — variable `CURL_CA_BUNDLE` et vérification des certificats
- [Homebrew — FAQ (proxy / certificats)](https://docs.brew.sh/FAQ#how-do-i-install-behind-a-proxy) — proxy et TLS derrière inspection SSL
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — section cURL

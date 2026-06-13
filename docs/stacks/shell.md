# Stack : Profil shell (variables centralisées)

## Résumé

Écrit un bloc de **variables d'environnement** dans `~/.zshrc`, `~/.zprofile` ou `~/.bash_profile`.

**Commande :** `./install.sh --shell --netskope`

## Variables configurées

| Variable | Consommateurs |
|----------|---------------|
| `NETSKOPE_CA_BUNDLE` | Référence centrale |
| `DART_VM_OPTIONS` | Dart, Flutter CLI |
| `NODE_EXTRA_CA_CERTS` | Node.js, npm, Firebase CLI |
| `SSL_CERT_FILE` | Ruby, OpenSSL, divers CLI |
| `REQUESTS_CA_BUNDLE` | Python requests, pip |
| `CURL_CA_BUNDLE` | curl, Homebrew |
| `AWS_CA_BUNDLE` | AWS CLI |
| `GIT_SSL_CAINFO` | Git (doublon avec `--git`) |

## Endpoints impactés

Tous les endpoints des stacks consommant ces variables (voir docs individuelles).

## Usages Flutter concernés

| Situation | Nécessaire ? |
|-----------|--------------|
| `--all` (installation complète) | **Oui** (inclus automatiquement) |
| `--dart` seul | Configuré automatiquement si absent |
| Terminal IDE (VS Code, Android Studio) | **Oui** si lancé depuis le shell |
| Apps GUI macOS (Xcode, Android Studio) | **Non** — n'héritent pas du profil shell |
| App Store / téléchargements Xcode | **Non** — certificate pinning ; voir [NETSKOPE-APPLE-IT.md](../NETSKOPE-APPLE-IT.md) |

## Ce que le script configure

Bloc marqué `# BEGIN macos-netskope-dev` … `# END` dans le profil shell du **utilisateur courant** (voir [ADMIN.md](../ADMIN.md) si déploiement par un admin).

## Après installation

```bash
source ~/.zshrc
```

Redémarrer les terminaux et IDE pour propager les variables.

## Nécessaire si…

- Vous configurez `--dart`, `--python`, `--curl` ou `--aws` sans `--shell` → le script ajoute le bloc automatiquement
- Installation `--all` → **inclus**

## Références

- [OpenSSL — Variables d'environnement (SSL_CERT_FILE, SSL_CERT_DIR)](https://docs.openssl.org/3.6/man7/openssl-env/) — magasin CA partagé par de nombreux CLI
- [Node.js — Enterprise Network Configuration](https://nodejs.org/en/learn/http/enterprise-network-configuration) — `NODE_EXTRA_CA_CERTS`
- [Requests — SSL cert verification](https://requests.readthedocs.io/en/latest/user/advanced/#ssl-cert-verification) — `REQUESTS_CA_BUNDLE` et repli `CURL_CA_BUNDLE`
- [curl — TLS certificate verification](https://everything.curl.dev/usingcurl/tls/verify.html) — `CURL_CA_BUNDLE`
- [AWS CLI — Variables d'environnement](https://docs.aws.amazon.com/cli/latest/userguide/cli-environment.html) — `AWS_CA_BUNDLE`
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — vue d'ensemble des variables par outil

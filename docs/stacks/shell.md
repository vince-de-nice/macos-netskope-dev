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

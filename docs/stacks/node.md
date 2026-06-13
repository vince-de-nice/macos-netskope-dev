# Stack : Node.js / npm

## Résumé

Configure **npm** et la variable `NODE_EXTRA_CA_CERTS` pour les outils Node derrière Netskope.

**Commande :** `./install.sh --node --netskope`

## Endpoints impactés

| Endpoint | Usage Flutter | Erreur sans config |
|----------|---------------|-------------------|
| `registry.npmjs.org` | Packages npm (outils, scripts) | `UNABLE_TO_VERIFY_LEAF_SIGNATURE` |
| `registry.yarnpkg.com` | Yarn (si utilisé) | Idem |
| `www.npmjs.com` | Metadata npm | Idem |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| **Firebase CLI** (`firebase deploy`) | **Oui** |
| `npx` outils (eslint, etc.) | **Oui** si réseau requis |
| `npm install` dans projet web/admin | **Oui** |
| `flutter pub get` | Non (Dart) |
| Build mobile natif | Non (sauf scripts npm CI) |

## Ce que le script configure

- `npm config set cafile <bundle.pem>`
- `NODE_EXTRA_CA_CERTS` dans le profil shell

## Vérification manuelle

```bash
NODE_EXTRA_CA_CERTS=$HOME/.gradle/macos-netskope-dev/nscacert_combined.pem npm ping
firebase --version  # si installé
```

## Nécessaire si…

- Vous utilisez **Firebase CLI**, **Melos** (npm), ou scripts Node dans le workflow → **Oui**
- Flutter mobile pur sans outillage Node → **Non**

## Références

- [npm — Configuration `cafile`](https://docs.npmjs.com/cli/v11/using-npm/config#cafile) — bundle CA pour les requêtes HTTPS du registre npm
- [Node.js — Enterprise Network Configuration](https://nodejs.org/en/learn/http/enterprise-network-configuration) — `NODE_EXTRA_CA_CERTS` (fichier PEM, chargé au démarrage du processus)
- [Node.js — CLI `NODE_EXTRA_CA_CERTS`](https://nodejs.org/api/cli.html#node_extra_ca_certsfile) — référence API détaillée
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — section Node.js / npm / Yarn

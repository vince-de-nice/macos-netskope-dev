# Stack : Google Cloud SDK (gcloud)

## Résumé

Configure `gcloud` pour faire confiance à la CA Netskope.

**Commande :** `./install.sh --gcloud --netskope`

## Endpoints impactés

| Endpoint | Usage Flutter | Erreur sans config |
|----------|---------------|-------------------|
| `*.googleapis.com` | APIs Google Cloud | Erreurs SSL gcloud |
| `accounts.google.com` | Auth gcloud | Idem |
| `cloud.google.com` | Metadata | Idem |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| **Firebase** via gcloud (rare, plutôt Firebase CLI) | Optionnel |
| Déploiement Cloud Run / GCE backend Flutter | **Oui** si gcloud utilisé |
| `flutter build` / mobile | Non |
| **Firebase CLI** (npm) | Non — voir stack Node |

## Ce que le script configure

```bash
gcloud config set core/custom_ca_certs_file ~/.gradle/macos-netskope-dev/nscacert_combined.pem
```

## Vérification manuelle

```bash
gcloud auth list
gcloud config get-value core/custom_ca_certs_file
```

## Nécessaire si…

- Vous n'utilisez pas gcloud → **Non**
- Backend GCP ou ops infra avec gcloud → **Oui**

# Stack : AWS CLI

## Résumé

Configure `AWS_CA_BUNDLE` pour **AWS CLI** et SDKs AWS utilisant cette variable.

**Commande :** `./install.sh --aws --netskope`

## Endpoints impactés

| Endpoint | Usage Flutter | Erreur sans config |
|----------|---------------|-------------------|
| `*.amazonaws.com` | S3, STS, API Gateway, etc. | SSL verify failed |
| `s3.amazonaws.com` | Assets, CI artifacts | Idem |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| Upload S3 (CI, assets) | **Oui** si AWS CLI |
| `flutter build` / mobile local | Non |
| Amplify CLI (souvent Node) | Plutôt stack Node |
| Backend AWS depuis le Mac | **Oui** |

## Ce que le script configure

```bash
export AWS_CA_BUNDLE="${NETSKOPE_CA_BUNDLE}"
```

## Vérification manuelle

```bash
AWS_CA_BUNDLE=$HOME/.gradle/macos-netskope-dev/nscacert_combined.pem aws sts get-caller-identity
```

## Nécessaire si…

- Pas d'usage AWS sur le poste dev → **Non**
- CI/CD ou ops AWS depuis le Mac → **Oui**

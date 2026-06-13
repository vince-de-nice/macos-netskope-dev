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

## Références

- [AWS CLI — Variables d'environnement (`AWS_CA_BUNDLE`)](https://docs.aws.amazon.com/cli/latest/userguide/cli-environment.html) — chemin vers un bundle PEM pour la validation TLS
- [AWS CLI — Dépannage SSL (`CERTIFICATE_VERIFY_FAILED`)](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-troubleshooting.html) — erreurs proxy / CA d'entreprise
- [AWS SDKs — Configuration `ca_bundle`](https://docs.aws.amazon.com/sdkref/latest/guide/feature-gen-config.html) — équivalent dans `~/.aws/config` et variable `AWS_CA_BUNDLE`
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — section AWS CLI

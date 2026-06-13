# Stack Go

## Commande

```bash
./install.sh --go --netskope --yes
# ou --all (inclut go depuis v1.1)
```

## Mécanisme

Variables via le profil shell (`--shell` implicite) :

- `SSL_CERT_FILE` → bundle PEM Netskope
- `GODEBUG` : utiliser Go 1.20+ avec le bundle système

## Vérification

```bash
source ~/.zshrc
SSL_CERT_FILE=$HOME/.gradle/macos-netskope-dev/nscacert_combined.pem go env
curl -I https://proxy.golang.org
```

## Rollback

```bash
./install.sh --rollback-stack shell
```

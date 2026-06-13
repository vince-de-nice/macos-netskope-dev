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

## Références

- [Go — `crypto/x509` (`SystemCertPool`)](https://pkg.go.dev/crypto/x509#SystemCertPool) — `SSL_CERT_FILE` / `SSL_CERT_DIR` sur Unix (**non pris en charge sur macOS**)
- [OpenSSL — Variables d'environnement (`SSL_CERT_FILE`)](https://docs.openssl.org/3.6/man7/openssl-env/) — bundle CA PEM utilisé par la stack shell
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — contexte inspection SSL pour outils CLI

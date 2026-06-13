# Stack : Python / pip

## Résumé

Configure les variables `REQUESTS_CA_BUNDLE` et `SSL_CERT_FILE` pour Python et **pip**.

**Commande :** `./install.sh --python --netskope`

## Endpoints impactés

| Endpoint | Usage Flutter | Erreur sans config |
|----------|---------------|-------------------|
| `pypi.org` | Packages pip | `CERTIFICATE_VERIFY_FAILED` |
| `files.pythonhosted.org` | Wheels pip | Idem |
| APIs Python diverses | Scripts CI, ML, codegen | Idem |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| Scripts Python build/CI | **Oui** si HTTPS |
| **Fastlane** (Ruby, pas Python) | Non |
| `flutter` / `dart` | Non |
| TensorFlow Lite tooling Python | **Oui** si utilisé |

## Ce que le script configure

Variables dans le profil shell :
```bash
export REQUESTS_CA_BUNDLE="${NETSKOPE_CA_BUNDLE}"
export SSL_CERT_FILE="${NETSKOPE_CA_BUNDLE}"
```

## Piège Python 3.13+

Validation TLS plus stricte (`Missing Authority Key Identifier`). Peut échouer même avec le bundle → contacter IT Netskope pour rotation CA tenant ou bypass PyPI.

## Vérification manuelle

```bash
python3 -c "import urllib.request; urllib.request.urlopen('https://pypi.org')"
```

## Nécessaire si…

- Workflow Flutter **sans Python** → **Non**
- Scripts automation, CI local Python → **Oui**

## Références

- [pip — HTTPS Certificates](https://pip.pypa.io/en/stable/topics/https-certificates/) — `PIP_CERT`, `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE`
- [Requests — SSL cert verification](https://requests.readthedocs.io/en/latest/user/advanced/#ssl-cert-verification) — `REQUESTS_CA_BUNDLE` (repli `CURL_CA_BUNDLE`)
- [OpenSSL — Variables d'environnement](https://docs.openssl.org/3.6/man7/openssl-env/) — `SSL_CERT_FILE` / `SSL_CERT_DIR`
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — section Python / pip et contraintes Python 3.13+

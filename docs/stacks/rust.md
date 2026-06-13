# Stack Rust / cargo

## Commande

```bash
./install.sh --rust --netskope --yes
```

## Mécanisme

Variable `CARGO_HTTP_CAINFO` dans le profil shell, pointant vers le bundle PEM.

## Vérification

```bash
source ~/.zshrc
cargo search serde --limit 1
```

## Rollback

```bash
./install.sh --rollback-stack shell
```

## Références

- [Cargo — Configuration (`http.cainfo`)](https://doc.rust-lang.org/cargo/reference/config.html#httpcainfo) — chemin vers un bundle CA ; variable d'environnement `CARGO_HTTP_CAINFO`
- [Netskope — Configuring Developer Tools with SSL Inspection](https://community.netskope.com/next-gen-swg-2/configuring-developer-tools-with-netskope-ssl-inspection-8493) — contexte inspection SSL pour outils CLI

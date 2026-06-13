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

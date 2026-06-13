# macos-netskope-dev

Configuration TLS **Netskope** pour le développement mobile sur **macOS** (Gradle, Flutter/Dart, Git, npm, CocoaPods, etc.).

## Démarrage rapide

```bash
./install.sh --all --netskope --yes
source ~/.zshrc
```

## Documentation

| Audience | Document |
|----------|----------|
| Développeur | [docs/README.md](docs/README.md) |
| Administrateur IT | [docs/ADMIN.md](docs/ADMIN.md) |
| Microsoft Intune | [docs/INTUNE.md](docs/INTUNE.md) |
| Dépannage | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

## Tests

```bash
./test/run-tests.sh
```

## Release

```bash
./scripts/build-release.sh    # dist/mnd-VERSION.tar.gz
./scripts/build-pkg.sh        # dist/macos-netskope-dev-VERSION.pkg
```

MIT License — voir [LICENSE](LICENSE).

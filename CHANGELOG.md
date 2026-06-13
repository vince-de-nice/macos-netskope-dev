# Changelog

## [1.0.0] — 2026-06-13

Première version publique de **macos-netskope-dev**.

### Added
- Configuration TLS Netskope multi-stacks (`--all`, Gradle, shell, Dart, Git, npm, Python, Ruby, curl, gcloud, AWS, simulateur)
- Truststore PKCS12 : `~/.gradle/macos-netskope-dev/macos-netskope-dev.p12`
- Bundle CA PEM : `~/.gradle/macos-netskope-dev/nscacert_combined.pem`
- Mode admin `--as-user` pour déploiement IT
- `--status`, `--rollback`, `--compliance [--json]`
- Scripts Intune : détection, remédiation, déploiement package, LaunchDaemon post-connexion
- Archive MDM : `dist/mnd-VERSION.tar.gz` + SHA256
- Documentation : ADMIN, INTUNE, NETSKOPE-APPLE-IT, CHECKLIST-IT-FLUTTER, DEV-IOS-XCODE
- Variables d'environnement : préfixe `MND_*`
- Install system : `/usr/local/share/macos-netskope-dev`
- Logs : `/var/log/macos-netskope-dev`
- CI GitHub Actions, LICENSE MIT

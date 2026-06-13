# Changelog

## [1.1.0] — 2026-06-13

### Fixed
- `ensure_sudo` manquant avant export Keychain (install `--netskope` en échec)

### Added
- Stacks **Go** et **Rust** (`--go`, `--rust`, inclus dans `--all`)
- Profils compliance : `MND_COMPLIANCE_STACKS`, `MND_COMPLIANCE_PROFILE` (mobile-dev, minimal)
- `MND_STORE_PASSWORD_FILE` pour mot de passe hors ligne de commande
- `--cert-fingerprint`, `--shell-profile`, `--rollback-stack`
- Manifest `schema_version` + lecture/écriture **jq** si disponible
- Sauvegardes git/npm avant première modification
- Intune : `MND_NETSKOPE_REQUIRED`, `MND_RUN_ID`, `MND_TARGET_USERS`, vérif SHA256 deploy
- LaunchAgent (`install-login-agent.sh --agent launchagent`)
- `scripts/build-pkg.sh` pour package MDM
- `README.md`, `docs/TROUBLESHOOTING.md`
- CI : smoke dry-run + workflow release sur tag

### Changed
- Source unique `ALL_STACKS_DEFAULT` dans `lib/stacks.sh`
- Détection Intune sans user : JSON `compliant: false`, `status: skipped`
- Tests `--list-netskope` isolés via `MND_TEST_NETSKOPE_CERTS_FILE`

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

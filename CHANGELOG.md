# Changelog

## [4.1.0] — 2026-06-13

### Added
- Fusion du manifest pour installations incrémentales (`--gradle` puis `--git`, etc.)
- Export Keychain en root avant `--as-user` (déploiement admin sans sudo développeur)
- Réutilisation du bundle CA si empreinte inchangée (`ca_fingerprint`)
- Cache PEM dans `~/.gradle/corporate-truststore/certs/`
- Fusion des `DART_VM_OPTIONS` existants avec `--root-certs-file`
- Variable d'environnement `GCT_STORE_PASSWORD` pour le mot de passe truststore
- Tests : manifest merge, DART_VM_OPTIONS, bundle reuse, admin preparse
- CI GitHub Actions (shellcheck + tests sur macOS)
- LICENSE (MIT)

### Changed
- Le manifest ne stocke plus `store_password` en clair
- Sauvegardes gradle/shell/truststore conservées lors d'installations incrémentales
- Documentation admin, Gradle et Dart mises à jour

### Removed
- Code mort `build_ca_bundle_from_keychain_combined`

## [4.0.0] — 2026-06-13

- Support multi-stacks (`--all`, 11 stacks)
- Mode admin `--as-user`
- Documentation complète et suite de tests (107+)

# Changelog

## [4.2.0] — 2026-06-13

### Added
- `--status` enrichi : état réel des fichiers `[OK]`/`[ABSENT]`, détection installation incomplète
- Option `--force` requise pour `--discover-tls`
- Déduplication des alias certificats (suffixe empreinte SHA-256)
- Support profil shell `~/.zprofile`
- Fusion `DART_VM_OPTIONS` depuis tout le profil (y compris ancien bloc)

### Changed
- Stack `gcloud` / `simulator` : marquées configurées uniquement si action réelle effectuée
- Rollback supprime aussi le cache `certs/`
- Script MDM ADMIN.md utilise `sudo ./install.sh --as-user`
- Résumé install et `--status` : section **Actions pour prise en compte** selon les stacks configurées
- Option B admin (`sudo -u` seul) documentée comme limitée

### Removed
- Code mort `stack_is_selected`

## [4.1.0] — 2026-06-13

### Added
- Fusion du manifest pour installations incrémentales
- Export Keychain en root avant `--as-user`
- Réutilisation du bundle CA si empreinte inchangée
- Fusion des `DART_VM_OPTIONS` existants
- Variable `GCT_STORE_PASSWORD`
- CI GitHub Actions, LICENSE MIT

## [4.0.0] — 2026-06-13

- Support multi-stacks (`--all`, 11 stacks)
- Mode admin `--as-user`
- Documentation complète et suite de tests

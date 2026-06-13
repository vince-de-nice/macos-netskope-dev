# Dépannage — macos-netskope-dev

Guide des problèmes courants et des codes `reason` de `--compliance --json`.

## Commandes utiles

```bash
./install.sh --status
./install.sh --compliance --json
./install.sh --list-netskope
./install.sh --rollback
./install.sh --rollback-stack git
```

## Raisons compliance → action

| Reason | Signification | Action corrective |
|--------|---------------|-------------------|
| `no_manifest` | Jamais installé ou manifest supprimé | `./install.sh --all --netskope --yes` |
| `no_stacks_configured` | Manifest vide | Idem |
| `missing_stacks` | Stacks `--all` incomplètes | `./install.sh --all --netskope --yes` ou ajuster `MND_COMPLIANCE_STACKS` |
| `truststore_or_bundle_missing` | Fichiers CA absents | `./install.sh --all --netskope --yes` |
| `orphan_artifacts` | Fichiers sans stacks enregistrées | `./install.sh --rollback` puis réinstaller |
| `script_version_outdated` | Version script > manifest | `./install.sh --all --netskope --yes` |
| `manifest_unreadable` | JSON manifest corrompu | `./install.sh --rollback` ou supprimer `state/manifest.json` puis réinstaller |
| `ca_fingerprint_mismatch` | CA Keychain changées | `./install.sh --all --netskope --yes` |
| `ca_fingerprint_missing` | Manifest sans empreinte | Réinstaller |
| `ca_bundle_stale` | Bundle PEM obsolète | `./install.sh --all --netskope --yes` |
| `gradle_block_missing` | Pas de bloc dans gradle.properties | `./install.sh --gradle --netskope --yes` |
| `shell_block_missing` | Pas de bloc dans le profil shell | `./install.sh --shell --netskope --yes` |

## Intune

| Symptôme | Cause probable | Action |
|----------|----------------|--------|
| Détection exit 0 sans user | Mac au loginwindow | Normal si `MND_SKIP_IF_NO_USER=1` ; JSON `status: skipped` |
| Remédiation sans effet | Netskope pas prêt | Vérifier client Netskope ; `MND_NETSKOPE_WAIT_SECS` |
| Remédiation échoue | CA absentes | Logs `/var/log/macos-netskope-dev/remediate.log` |

## Profils compliance partiels

```bash
export MND_COMPLIANCE_PROFILE=mobile-dev   # gradle,shell,dart,git,node,ruby,curl
export MND_COMPLIANCE_STACKS=gradle,shell,dart
./install.sh --compliance --json
```

## Mot de passe truststore

Préférer un fichier restreint :

```bash
echo 'changeit' > ~/.config/mnd-store-password
chmod 600 ~/.config/mnd-store-password
export MND_STORE_PASSWORD_FILE=~/.config/mnd-store-password
./install.sh --all --netskope --yes
```

## Certificat Netskope multiple

```bash
./install.sh --list-netskope
./install.sh --cert-fingerprint ABC12345 --all --netskope --yes
```

## Hors scope script

- **Xcode / App Store** : [NETSKOPE-APPLE-IT.md](NETSKOPE-APPLE-IT.md)
- **Simulateur iOS** : [stacks/simulator.md](stacks/simulator.md)
- **Docker** : configuration Netskope séparée

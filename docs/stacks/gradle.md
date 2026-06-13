# Stack : Gradle / Android (JVM)

## Résumé

Configure la JVM utilisée par **Gradle** pour faire confiance à la CA Netskope via un **truststore PKCS12 dédié**, sans modifier les `cacerts` des JDK installés.

**Commande :** `./install.sh --gradle --netskope`

## Endpoints impactés

| Endpoint | Usage Flutter/Android | Erreur sans config |
|----------|----------------------|-------------------|
| `repo.maven.apache.org` | Dépendances Maven (Kotlin, libs Java) | `PKIX path building failed` |
| `dl.google.com` | Android Maven Repository, SDK Google | Idem |
| `plugins.gradle.org` | Gradle Plugin Portal | Idem |
| `services.gradle.org` | Téléchargement Gradle Wrapper | `SSLHandshakeException` |
| `jitpack.io` | Dépendances GitHub (plugins Flutter) | Idem |
| `maven.google.com` | Artifacts Google (Firebase, Play Services) | Idem |
| Artifactory interne | Repos Maven d'entreprise | HTTP 403 ou PKIX |

## Usages Flutter concernés

| Commande / action | Nécessaire ? |
|-------------------|--------------|
| `flutter build apk` / `appbundle` | **Oui** |
| `flutter run` sur Android | **Oui** (sync Gradle) |
| `./gradlew` dans `android/` | **Oui** |
| `flutter pub get` | Non (stack Dart) |
| `flutter build ios` | Non (stack Ruby/CocoaPods) |
| `flutter doctor` seul | Non |

## Ce que le script configure

- Export CA Netskope → truststore PKCS12 : `~/.gradle/macos-netskope-dev/macos-netskope-dev.p12`
- Bloc dans `~/.gradle/gradle.properties` :
  ```
  org.gradle.jvmargs=-Djavax.net.ssl.trustStore=... -Djavax.net.ssl.trustStoreType=PKCS12 ...
  ```
- Vérification TLS Java vers Maven Central, Google Maven, Gradle Plugin Portal

## Vérification manuelle

```bash
./install.sh --gradle --netskope --verbose
cd mon_projet_flutter/android && ./gradlew --stop
cd mon_projet_flutter/android && ./gradlew dependencies --refresh-dependencies
```

> Après une installation ou mise à jour, arrêtez le **Gradle daemon** (`./gradlew --stop`) pour que les nouveaux `org.gradle.jvmargs` (truststore PKCS12) soient pris en compte.

## Installations incrémentales

Vous pouvez ajouter des stacks sans tout réinstaller :

```bash
./install.sh --all --netskope --yes      # première fois
./install.sh --simulator --netskope --yes  # ajout simulateur
./install.sh --status                      # toutes les stacks restent visibles
```

Le manifest fusionne l'état de chaque stack. Le `--rollback` restaure **toute** la configuration enregistrée.

## Non couvert par cette stack

- JVM d'**Android Studio** en dehors de Gradle (IDE sync peut utiliser un autre JDK)
- **sdkmanager** / cmdline-tools si lancés avec une JVM différente
- Builds **Docker** (certificats à injecter dans l'image)

## Rollback

```bash
./install.sh --rollback
```

Restaure `gradle.properties` et supprime/restaure le truststore PKCS12.

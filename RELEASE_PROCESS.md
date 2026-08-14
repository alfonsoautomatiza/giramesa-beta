# Publicar una versión de prueba de Giramesa

La compilación y la firma ocurren siempre en el repositorio privado de la aplicación. El comando preferido, `release-all.ps1`, valida y dispara un único workflow privado con runners separados para Android, web, Windows e iOS. Nunca compila iOS en Windows.

## Flujo rápido

1. Editar `DONDE_COMER/app/pubspec.yaml` con `version: X.Y.Z[-prerelease]+N`, confirmar el cambio y sincronizarlo normalmente con la rama remota.
2. Preparar notas públicas sin datos internos y ejecutar `release-all.ps1`; no se proporciona versión ni build por parámetros.
3. El script valida el worktree privado, commit, autenticación, repositorios, visibilidad, rama, workflow, tag/Release y notas, y dispara un solo `workflow_dispatch` en el repositorio privado.
4. CI prueba antes de compilar; Android verifica firma no-debug, web y Windows generan ZIP, e iOS sube la IPA sólo a TestFlight.
5. Verificar el portal publicado desde Android y escritorio.
6. Gestionar TestFlight por separado y actualizar `docs/config.js` solo cuando haya un enlace público válido.

## Prerrequisitos

- Windows PowerShell 5.1 o PowerShell 7 y GitHub CLI (`gh`) ya autenticado; el controlador no autentica ni acepta tokens.
- Worktree privado local limpio en la rama elegida, con `HEAD` igual a `origin/<rama>` y al commit remoto de GitHub. El controlador no hace `fetch`, `pull`, `merge`, `commit` ni `push`.
- Repositorio de aplicación PRIVATE `wertyMSD/donde-comer`, repositorio beta PUBLIC `wertyMSD/giramesa-beta` y workflow instalado en la rama predeterminada y en la ref elegida.
- Secretos y firma privada configurados según [private-repo-template/SECRETS.md](private-repo-template/SECRETS.md).
- Plantilla instalada según [private-repo-template/INSTALL.md](private-repo-template/INSTALL.md). Por sí sola en este repositorio público no ejecuta nada.
- Apple Developer Program y App Store Connect preparados. El acceso externo por TestFlight puede requerir Beta App Review de Apple.

## Convenciones

| Elemento | Formato | Ejemplo |
|---|---|---|
| Flutter `version:` | SemVer estricto + entero positivo | `version: 1.4.0+14` |
| Versión de Release | Parte anterior a `+` | `1.4.0` |
| Build de plataformas | Parte posterior a `+` | `14` |
| Tag | `vX.Y.Z` | `v1.4.0` |
| APK CI | `giramesa-android-vX.Y.Z-bN.apk` | `giramesa-android-v1.4.0-b14.apk` |
| Web/Windows CI | `giramesa-<plataforma>-vX.Y.Z-bN.zip` | `giramesa-web-v1.4.0-b14.zip` |
| Checksum | `<asset>.sha256` | `giramesa-android-v1.4.0-b14.apk.sha256` |

`DONDE_COMER/app/pubspec.yaml` es la única autoridad de versión. El controlador y el workflow rechazan claves ausentes, duplicadas o malformadas y nunca preguntan, aceptan ni sobrescriben versión/build. Android rechaza o no ofrece como actualización un APK cuyo `versionCode` sea menor o igual al instalado; Apple también exige un `CFBundleVersion` válido para cada carga.

Las versiones previas pueden usar sufijos SemVer, por ejemplo `1.4.0-rc.1`. El tag conserva el sufijo (`v1.4.0-rc.1`) y la Release se marca prerelease automáticamente. Para Android, Flutter recibe el núcleo compatible `--build-name 1.4.0`; la identidad prerelease permanece en el tag y nombre del asset.

## Publicación multiplataforma preferida

Primero editá y confirmá la versión Flutter en el repositorio privado, por ejemplo:

```yaml
version: 0.1.1+2
```

Después simulá todos los controles no mutantes:

```powershell
./release-all.ps1 -ReleaseNotesFile ./release-notes.md -WhatIf
```

El comando principal de publicación es:

```powershell
./release-all.ps1 -ReleaseNotesFile ./release-notes.md -Wait
```

El controlador deriva por defecto el worktree privado desde el directorio hermano `DONDE_COMER` (`D:\py\@android\DONDE_COMER` en el layout estándar), usa la rama `main`, la aplicación `wertyMSD/donde-comer` y el destino `wertyMSD/giramesa-beta`. `-AppRepository`, `-AppRepositorySlug`, `-Branch` y `-BetaRepositorySlug` permiten ajustar esas ubicaciones explícitamente. `-SkipAndroid`, `-SkipWeb`, `-SkipWindows` y `-SkipIos` seleccionan trabajos; no se permite omitirlos todos. `-Wait` muestra URL y estado final. `-WhatIf` completa todas las lecturas, imprime versión/build y el comando planificado, pero no ejecuta `gh workflow run`.

El workflow recibe únicamente el SHA esperado, destino beta, notas codificadas, URL pública opcional y toggles de plataforma. Tras checkout, un job `metadata` verifica el SHA y vuelve a parsear de forma independiente el único `version:` top-level de `app/pubspec.yaml`; todos los jobs consumen esas mismas salidas.

Los nombres incluyen versión y build para evitar sustituciones silenciosas. La Release pública recibe sólo APK, ZIP web, ZIP Windows y checksums. La IPA nunca se publica ni se conserva como artifact de Actions: el job macOS la carga directamente a TestFlight y la elimina. El workflow usa un token fine-grained limitado al repositorio beta porque el `GITHUB_TOKEN` de la aplicación no puede escribir en otro repositorio.

El ZIP web es un artefacto descargable, no un despliegue vivo. Un despliegue público debe diseñarse por separado y no sobrescribir el portal beta. El ZIP Windows contiene la salida release; no se afirma que sea un instalador.

## Publicación Android local especializada

`publish-android-release.ps1` sigue disponible como herramienta secundaria cuando se necesita compilar y publicar únicamente Android desde una estación Windows ya configurada:

```powershell
./publish-android-release.ps1 -ReleaseNotesFile ./release-notes.md -WhatIf
```

Este flujo especializado también deriva versión/build de `DONDE_COMER/app/pubspec.yaml`; exige Flutter, Java, Android SDK Build-Tools y `apksigner.bat` locales. No incluye web, Windows ni iOS. `publish-public-repo.ps1` también se conserva exclusivamente para bootstrap/mantenimiento del portal y Pages.

Los binarios se adjuntan a GitHub Releases; **nunca se agregan al árbol Git**.

## Notas de publicación

Usar texto claro para testers:

```text
## Qué probar
- Flujo concreto que necesita validación.

## Cambios visibles
- Cambio observable por una persona usuaria.

## Problemas conocidos
- Limitación relevante y alternativa segura, si existe.

SHA-256: <checksum del APK>
```

No incluir incidencias privadas, nombres de personas, correos, endpoints internos, trazas con datos reales ni detalles que amplíen la superficie de ataque.

## Controles del publicador Android especializado

El script ejecuta `flutter pub get`, `flutter test` salvo `-SkipTests`, y únicamente `flutter build apk --release`. Después exige una firma válida con `apksigner verify --verbose --print-certs` y bloquea explícitamente certificados Android Debug.

Antes de crear `v<versión>`, comprueba que el tag y la Release no existan local ni remotamente, valida `scripts/validate_public_repo.py` y revisa patrones obvios de secretos en las notas sin imprimir coincidencias. `gh release create` apunta a `main`, adjunta sólo APK y checksum, y nunca hace commit, force push ni mueve material de firma.

Si no se indica `-ReleaseNotesFile`, el script especializado pide confirmación explícita antes de generar una plantilla neutral. El flujo unificado siempre exige el archivo. Ante un fallo, `.release-work\<versión>` se conserva ignorado para diagnóstico.

## Habilitar TestFlight

El publicador Android especializado de Windows **nunca publica iPhone**. En el flujo preferido, iOS se compila en `macos-latest`, se carga directamente a TestFlight y no llega a la Release pública. TestFlight requiere App Store Connect y su propio proceso de firma y revisión.

1. Subir y procesar la compilación iOS en App Store Connect desde el flujo privado.
2. Completar la revisión de TestFlight cuando Apple la requiera.
3. Crear o comprobar el enlace público con el límite de testers adecuado.
4. Sustituir el valor vacío de `testFlightUrl` en `docs/config.js` por una URL `https://testflight.apple.com/join/...`.
5. Abrir un pull request y comprobar que el validador acepta el dominio y el formato.
6. Verificar el botón desde un iPhone sin publicar ningún IPA.

## Rollback

Si una Release Android es insegura o inutilizable:

1. Marcarla inmediatamente como borrador o eliminar la Release para retirarla del endpoint `latest`.
2. No reutilizar el tag ni reemplazar silenciosamente un APK bajo el mismo nombre.
3. Corregir en el repositorio privado, incrementar la versión y publicar una Release nueva.
4. Documentar en las notas qué versión se retiró y la acción esperada.

Para iPhone, retirar la compilación o cerrar el enlace en App Store Connect. Si el enlace público deja de ser válido, vaciar `testFlightUrl` para que el portal vuelva al estado deshabilitado.

## Separación obligatoria

Nunca copies directorios del proyecto privado a este repositorio. El workflow transfiere sólo APK, ZIP web, ZIP Windows y checksums al límite público; el publicador especializado transfiere sólo APK y checksum. Ningún binario se agrega al índice Git. Ejecutá siempre:

```bash
python3 scripts/validate_public_repo.py
git status --short
```

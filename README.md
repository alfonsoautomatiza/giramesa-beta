# Giramesa Beta: acceso público a versiones de prueba

Este repositorio aloja el portal y las instrucciones públicas para probar Giramesa. **No contiene el código de la aplicación ni binarios de publicación.**

## Acceso rápido

| Necesidad | Acción |
|---|---|
| Probar en Android | Abrir el portal de GitHub Pages y descargar el APK de la última Release cuando exista. |
| Probar en iPhone | Abrir la invitación de TestFlight desde el portal cuando mantenimiento la configure. |
| Comunicar un problema | Crear una incidencia sin incluir datos personales, credenciales ni información sensible. |
| Publicar una versión | Seguir [RELEASE_PROCESS.md](RELEASE_PROCESS.md). |

## Estado actual

- El repositorio local tiene el commit `c4fed8b` y `origin` apunta a `https://github.com/alfonsoautomatiza/giramesa-beta.git`.
- El slug configurado es `alfonsoautomatiza/giramesa-beta`.
- El estado efectivo del repositorio remoto, GitHub Pages y las Releases debe verificarse en GitHub antes de anunciar disponibilidad.
- El enlace de TestFlight está vacío y su botón permanece deshabilitado.
- No se incluye ningún APK o IPA.

No debe anunciarse acceso Android hasta verificar una Release pública ni acceso para iPhone hasta configurar una invitación válida de TestFlight.

## Vista local

El portal no necesita instalar dependencias:

```bash
python3 -m http.server 8000 --directory docs
```

Abrir `http://localhost:8000`. La consulta a GitHub mostrará un estado vacío mientras no exista una Release pública.

## Verificación

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_public_repo.py
```

## Publicación desde Windows

### Preparar el portal una sola vez

Desde PowerShell, en `D:\py\@android\giramesa-beta`, el bootstrap del repositorio y Pages se ejecuta una sola vez:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\publish-public-repo.ps1 -InstallGitHubCli
```

Simulación sin commits, remotos, pushes ni cambios en GitHub:

```powershell
.\publish-public-repo.ps1 -WhatIf
```

`publish-public-repo.ps1` publica únicamente el portal. No compila, firma ni sube APK.

### Publicar todas las plataformas desde un comando

El comando preferido y único punto de entrada del operador para las cuatro plataformas es `release-all.ps1`. No compila localmente: valida el worktree privado y dispara un único workflow. Android, web y Windows se publican como assets de GitHub Release; iOS se compila en macOS CI y se carga sólo a TestFlight.

La versión y el build se definen **únicamente** en `DONDE_COMER/app/pubspec.yaml`. Por ejemplo, antes de publicar una actualización, editar y confirmar en la rama privada:

```yaml
version: 0.1.1+2
```

Después, desde este repositorio:

```powershell
./release-all.ps1 -ReleaseNotesFile ./release-notes.md -Wait
```

Simulación segura, sin compilar ni crear artefactos o Releases:

```powershell
./release-all.ps1 -ReleaseNotesFile ./release-notes.md -WhatIf
```

La instalación privada requerida está documentada en [private-repo-template/INSTALL.md](private-repo-template/INSTALL.md) y sus secretos en [private-repo-template/SECRETS.md](private-repo-template/SECRETS.md). La plantilla no hace nada hasta copiarla, adaptarla y confirmarla en el repositorio privado de la aplicación.

El valor debe ser `X.Y.Z[-prerelease]+N`: la parte anterior a `+` determina la versión y el tag `v...`; el entero positivo posterior determina el build de todas las plataformas, Android `versionCode` e iOS `CFBundleVersion`. `release-all.ps1` nunca pregunta, acepta ni infiere esos valores por otra vía.

Por defecto, `-AppRepository` apunta al directorio hermano `DONDE_COMER` (`D:\py\@android\DONDE_COMER` en el layout estándar). El script exige worktree limpio, rama correcta, `HEAD` igual a `origin/<rama>` y al commit remoto antes del dispatch. `-SkipAndroid`, `-SkipWeb`, `-SkipWindows` y `-SkipIos` permiten seleccionar plataformas; `-ApiBaseUrl` aplica una URL HTTPS pública y `-Wait` observa el run. El ZIP web es descargable; desplegarlo como sitio vivo requiere un workflow separado.

### Herramientas especializadas

`publish-android-release.ps1` se conserva para una publicación Android local y controlada desde Windows. `publish-public-repo.ps1` se conserva para preparar o mantener el portal y Pages. Ninguno reemplaza el flujo multiplataforma preferido.

## Límites del repositorio

Está permitido incluir documentación, HTML/CSS/JavaScript estático, SVG originales, workflows y metadatos públicos de publicación. Está prohibido incluir:

- Código fuente o artefactos internos de la aplicación.
- APK, IPA, AAB, mapas de ofuscación o símbolos.
- Keystores, certificados, perfiles y cualquier material de firma.
- Tokens, credenciales, archivos de Firebase o listas de testers.

La disponibilidad pública de este repositorio no concede licencia sobre la aplicación privada. Consultar [NOTICE.md](NOTICE.md).

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

- El repositorio está preparado localmente, sin commits ni remoto.
- El slug público previsto es `wertyMSD/giramesa-beta`.
- GitHub Pages no está publicado todavía.
- No existe ninguna GitHub Release en este repositorio local.
- El enlace de TestFlight está vacío y su botón permanece deshabilitado.
- No se incluye ningún APK o IPA.

Hasta que se cree el repositorio remoto, la URL prevista `https://wertyMSD.github.io/giramesa-beta/` no estará activa. Tampoco debe anunciarse acceso para iPhone hasta configurar una invitación válida de TestFlight.

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

Desde PowerShell, en `D:\py\@android\giramesa-beta`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\publish-public-repo.ps1 -InstallGitHubCli
```

Simulación sin commits, remotos, pushes ni cambios en GitHub:

```powershell
.\publish-public-repo.ps1 -WhatIf
```

El script publica únicamente este portal. No compila, firma ni sube APK, y no configura Apple ni TestFlight.

## Límites del repositorio

Está permitido incluir documentación, HTML/CSS/JavaScript estático, SVG originales, workflows y metadatos públicos de publicación. Está prohibido incluir:

- Código fuente o artefactos internos de la aplicación.
- APK, IPA, AAB, mapas de ofuscación o símbolos.
- Keystores, certificados, perfiles y cualquier material de firma.
- Tokens, credenciales, archivos de Firebase o listas de testers.

La disponibilidad pública de este repositorio no concede licencia sobre la aplicación privada. Consultar [NOTICE.md](NOTICE.md).

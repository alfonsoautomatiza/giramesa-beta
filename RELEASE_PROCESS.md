# Publicar una versión de prueba de Giramesa

La compilación y la firma ocurren siempre en el repositorio privado de la aplicación. Este repositorio público recibe únicamente el APK final destinado a testers, su checksum y notas depuradas.

## Flujo rápido

1. Verificar y firmar una compilación release en el entorno privado.
2. Renombrar el archivo como `giramesa-X.Y.Z.apk`.
3. Calcular `SHA-256` y preparar notas sin datos internos.
4. Crear el tag `vX.Y.Z` y una GitHub Release pública en este repositorio.
5. Adjuntar solo el APK y `giramesa-X.Y.Z.apk.sha256`.
6. Verificar el portal publicado desde Android y escritorio.
7. Gestionar TestFlight por separado y actualizar `docs/config.js` solo cuando haya un enlace público válido.

## Prerrequisitos

- Acceso autorizado al repositorio privado y al proceso de firma Android.
- Una compilación **release** probada; nunca una compilación debug.
- Acceso de mantenimiento al futuro repositorio público `wertyMSD/giramesa-beta`.
- Para iPhone: Apple Developer Program, App Store Connect, una compilación aprobada para el grupo correspondiente y un enlace público de TestFlight.

## Convenciones

| Elemento | Formato | Ejemplo |
|---|---|---|
| Versión | SemVer | `1.4.0` |
| Tag | `vX.Y.Z` | `v1.4.0` |
| APK | `giramesa-X.Y.Z.apk` | `giramesa-1.4.0.apk` |
| Checksum | `<apk>.sha256` | `giramesa-1.4.0.apk.sha256` |

Las versiones previas pueden usar sufijos SemVer, por ejemplo `v1.4.0-rc.1`, pero GitHub no las devolverá desde el endpoint `releases/latest` si se marcan como prerelease. El canal normal del portal debe usar Releases estables de prueba.

## Preparar el APK Android

En el repositorio privado:

```bash
sha256sum giramesa-1.4.0.apk > giramesa-1.4.0.apk.sha256
```

Antes de mover los dos archivos al flujo de publicación, comprobar:

- Firma de release conocida y coherente con versiones anteriores.
- Nombre conforme a la convención.
- Pruebas mínimas en un dispositivo limpio y como actualización.
- Ausencia de símbolos, mapas, credenciales o configuración interna junto al artefacto.
- Coincidencia del checksum recalculado.

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

## Publicar en GitHub Releases

Después de autenticar `gh` y configurar el remoto:

```bash
git tag v1.4.0
git push origin v1.4.0
gh release create v1.4.0 giramesa-1.4.0.apk giramesa-1.4.0.apk.sha256 --title "Giramesa 1.4.0" --notes-file release-notes.md
```

`release-notes.md` es un archivo temporal de trabajo y no debe contener información sensible. Revisar la Release pública antes de compartirla.

## Habilitar TestFlight

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

Nunca copies directorios del proyecto privado a este repositorio. Transferí solo el APK final y el checksum al paso de creación de la Release, fuera del índice de Git. Ejecutá siempre:

```bash
python3 scripts/validate_public_repo.py
git status --short
```

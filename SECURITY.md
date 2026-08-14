# Seguridad

## Comunicar una vulnerabilidad

No publiques vulnerabilidades explotables, credenciales, tokens, datos personales ni capturas sensibles en una incidencia pública.

Hasta que el repositorio remoto tenga habilitada una vía privada de reporte, no existe un canal seguro publicado. Mantenimiento debe activar **Private vulnerability reporting** en GitHub antes de anunciar el proyecto. Una vez activo, usá la opción **Report a vulnerability** de la pestaña Security.

Si no aparece esa opción, no compartas detalles técnicos sensibles en público. Indicá únicamente que necesitás un canal privado mediante una incidencia genérica sin información explotable.

## Alcance

Son relevantes los problemas del portal estático, el flujo de GitHub Releases, enlaces de distribución y exposición accidental de material privado. Los errores funcionales normales deben usar la plantilla de incidencias.

## Compromisos de publicación

- No almacenar secretos ni material de firma en Git.
- No aceptar IPA ni APK dentro del árbol del repositorio.
- Mostrar contenido remoto solo como texto.
- Limitar los workflows a los permisos mínimos.
- Retirar de inmediato una Release comprometida y publicar una versión nueva, sin reemplazo silencioso.

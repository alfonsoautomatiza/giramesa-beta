# Instalar Giramesa Beta en Android

Usá únicamente el APK enlazado por el portal oficial de este repositorio. La instalación manual evita Google Play y requiere autorizar temporalmente una fuente externa.

## Instalación

1. Abrí el portal de Giramesa Beta desde el teléfono.
2. Comprobá que el estado indica una Release disponible y pulsá **Descargar**.
3. Si se publica un SHA-256, comparalo con el archivo descargado antes de instalar.
4. Abrí el APK desde las descargas del navegador o el gestor de archivos.
5. Cuando Android lo solicite, permití a esa aplicación instalar fuentes desconocidas.
6. Confirmá la instalación y abrí Giramesa.
7. Volvé a **Ajustes > Aplicaciones > Acceso especial > Instalar aplicaciones desconocidas** y retirale el permiso al navegador o gestor de archivos.

Los nombres de los menús pueden variar según el fabricante y la versión de Android.

## Advertencia de seguridad

La instalación de APK fuera de Google Play reduce algunas protecciones del canal habitual. Cancelá la instalación si:

- El archivo no termina en `.apk` o su nombre no coincide con el anunciado.
- El sistema indica una firma distinta al actualizar una instalación previa.
- El navegador redirige a un dominio inesperado.
- El checksum publicado no coincide.
- Se solicita desactivar Play Protect de forma permanente.

No compartas capturas con correo, ubicación, identificadores del dispositivo o información de otras personas. Comunicá el problema mediante la plantilla pública de incidencias y describí solo lo necesario para reproducirlo.

## Actualizaciones

Cada nueva versión se publica como una GitHub Release separada. El portal apunta siempre a la última Release no marcada como borrador o prerelease por el endpoint `latest`. Instalar un APK firmado con la misma identidad actualiza la aplicación y conserva sus datos; ante cualquier advertencia de firma, cancelá.

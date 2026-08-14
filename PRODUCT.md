# Producto

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Sitio estático en HTML, CSS y JavaScript sin dependencias de ejecución, preparado para GitHub Pages.

## Usuarios

- Personas invitadas a probar Giramesa en Android o iPhone, con distintos niveles de experiencia técnica.
- Responsables de publicación que necesitan distribuir versiones de prueba sin exponer el repositorio privado de la aplicación.

## Propósito del producto

Ofrecer un punto público, claro y seguro para obtener la última versión Android publicada en GitHub Releases y acceder a la invitación oficial de TestFlight para iPhone. El éxito consiste en que cada persona identifique su plataforma, comprenda el proceso de instalación y reciba estados veraces cuando un canal aún no esté disponible.

## Posicionamiento

El portal separa deliberadamente la distribución pública de pruebas del código privado de Giramesa: descubre publicaciones Android desde GitHub y deriva iPhone exclusivamente a TestFlight, sin almacenar binarios, credenciales ni datos de testers en el repositorio.

## Contexto operativo

- Android: descarga manual de un APK de prueba desde la última GitHub Release pública y habilitación puntual de instalación desde el navegador o gestor de archivos.
- iPhone: incorporación mediante un enlace público de TestFlight configurado por mantenimiento.
- Mantenimiento: publicación de APK, notas y checksum en GitHub Releases; actualización independiente del enlace público de TestFlight.

## Capacidades y restricciones

- El repositorio solo contiene documentación, sitio estático, automatización segura y metadatos de ejemplo.
- No contiene código de la aplicación, material de firma, tokens, listas de testers, APK, IPA, archivos de símbolos ni configuración privada de servicios.
- Android solo ofrece activos con extensión `.apk` procedentes del repositorio público configurado.
- iPhone solo admite TestFlight. No se ofrecen IPA, perfiles, registro de UDID ni métodos alternativos.
- Las notas remotas se tratan como texto no confiable y nunca se inyectan como HTML.
- Los enlaces de GitHub Pages y TestFlight permanecen inactivos hasta que existan y se configuren.
- No hay analítica, cookies, trackers, fuentes externas, CDN ni dependencias de ejecución.

## Compromisos de marca

- Nombre: Giramesa.
- Voz pública: español profesional, neutral, directo y transparente.
- Paleta confirmada: verde `#146356`, naranja `#F4A261` y marfil `#F5F1E8`.
- Mundo reconocible: Cádiz, sobremesa y mesa compartida, sin recurrir a imaginería copiada de proveedores.

## Evidencia disponible

Solo están confirmados el propósito, los canales, las restricciones y la paleta descritos en este documento. No hay publicaciones, cifras, testimonios, capturas, enlaces activos ni disponibilidad pública que puedan presentarse como existentes.

## Principios de producto

1. Mostrar el estado real antes que prometer disponibilidad.
2. Facilitar la instalación sin ocultar sus implicaciones de seguridad.
3. Mantener Android e iPhone visibles aunque se detecte automáticamente una plataforma.
4. Separar por completo la distribución pública del desarrollo y firma privados.
5. Pedir solo la información necesaria para diagnosticar una incidencia y nunca datos sensibles.

## Accesibilidad e inclusión

El sitio debe utilizar HTML semántico, navegación completa por teclado, foco visible, contraste legible, anuncios de estado accesibles y movimiento reducido cuando el sistema lo solicite. La detección de plataforma ayuda a orientar, pero no oculta ninguna opción.

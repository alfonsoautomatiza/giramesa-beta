---
name: Giramesa Beta
description: Mesa compartida gaditana para una distribución de pruebas clara y segura.
colors:
  primary-green: "#146356"
  deep-green: "#0b4038"
  table-orange: "#f4a261"
  orange-ink: "#9b4b11"
  tablecloth: "#f5f1e8"
  plate-white: "#fffdf8"
  body-ink: "#17322e"
  muted-ink: "#526b66"
  divider: "#b9c8c3"
  error: "#8f351f"
  focus: "#005fcc"
typography:
  display:
    fontFamily: "Aptos, Trebuchet MS, Verdana, sans-serif"
    fontSize: "clamp(3rem, 6.5vw, 5.6rem)"
    fontWeight: 700
    lineHeight: 0.98
    letterSpacing: "-0.04em"
  body:
    fontFamily: "Aptos, Trebuchet MS, Verdana, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: "Aptos, Trebuchet MS, Verdana, sans-serif"
    fontSize: "0.78rem"
    fontWeight: 800
    lineHeight: 1.25
    letterSpacing: "0.03em"
rounded:
  square: "0"
  circular: "50%"
spacing:
  compact: "0.75rem"
  control: "1.25rem"
  section: "7rem"
components:
  button-primary:
    backgroundColor: "{colors.primary-green}"
    textColor: "{colors.plate-white}"
    rounded: "{rounded.square}"
    padding: "0.85rem 1.25rem"
    height: "3.5rem"
  button-disabled:
    backgroundColor: "#e5e9e6"
    textColor: "#687773"
    rounded: "{rounded.square}"
    padding: "0.85rem 1.25rem"
    height: "3.5rem"
---

# Design System: Giramesa Beta

## Overview

**Creative North Star: "La mesa corrida de Cádiz"**

El sistema convierte la lectura y la instalación en una mesa compartida vista desde arriba. El mantel marfil ofrece calma para leer; el verde estructura los tramos públicos y seguros; el corredor naranja une plataformas distintas sin ocultar sus diferencias. La personalidad procede de la composición, la señalética y los SVG originales, no de efectos de interfaz genéricos.

Es un sistema expresivo en el primer contacto y sobrio al explicar pasos o riesgos. La jerarquía debe permitir reconocer plataforma, disponibilidad y siguiente acción en pocos segundos.

**Key Characteristics:**

- Mesa cenital como silueta distintiva y motivo de encuentro.
- Grandes campos verdes y marfil unidos por naranja de sobremesa.
- Señalética directa, líneas nítidas y contenido con medida de lectura contenida.
- Estados veraces que siguen siendo comprensibles sin depender del color.

## Colors

La paleta reparte roles claros entre mesa, señalética, acción y seguridad; el frontmatter contiene los valores normativos.

### Primary

- **Verde Giramesa:** ocupa regiones estructurales, acciones primarias, ilustración y estados disponibles.
- **Verde profundo:** sostiene fondos extensos y el pie, siempre con texto claro.

### Secondary

- **Naranja de sobremesa:** une ambas plataformas, numera secuencias y aporta el único acento cálido amplio.
- **Tinta naranja:** asegura contraste en bordes o texto pequeño sobre fondos claros.

### Neutral

- **Mantel marfil:** fondo principal de lectura.
- **Blanco plato:** superficie de contenido sobre campos verdes.
- **Tinta corporal y tinta atenuada:** niveles de lectura principal y secundaria.
- **Línea de vajilla:** divisores discretos, nunca decoración gratuita.

**The Shared Table Rule.** El verde y el naranja deben ocupar regiones con función compositiva; no se dispersan como pequeños acentos intercambiables.

## Typography

**Display Font:** pila local Aptos / Trebuchet MS / Verdana.
**Body Font:** la misma pila local.
**Label/Mono Font:** Courier New solo para nombres de archivo y datos técnicos.

**Character:** una única voz sans robusta mantiene legibles las instrucciones y evita dependencias externas. La marca aporta lettering propio mediante un SVG original.

### Hierarchy

- **Display:** peso 700, escala fluida del frontmatter y línea muy compacta; reservado al mensaje principal.
- **Headline:** peso 700, entre `2.2rem` y `4.4rem`, línea `1.02`; abre secciones amplias.
- **Title:** peso 700, `1.65rem` a `2rem`; identifica plataforma o guía.
- **Body:** peso 400, `1rem`, línea `1.65`; los párrafos se mantienen cerca de `65ch`.
- **Label:** peso 800, escala pequeña y espaciado moderado; solo para estados o recomendaciones reales, nunca como adorno sobre un título.

**The One Reading Voice Rule.** La jerarquía cambia con peso, tamaño y espacio; no se introducen familias decorativas en controles o instrucciones.

## Layout

El ancho de lectura principal se limita a `1180px`. Las secciones usan separación generosa y alternan campos claros y verdes. La mesa de plataformas es una composición continua de tres columnas: Android, corredor naranja e iPhone. No son tarjetas independientes.

Por debajo de `900px`, la mesa pasa a una secuencia vertical y el corredor se vuelve horizontal. Por debajo de `640px`, las guías forman una sola columna, el encabezado compacta su navegación y todos los elementos de cuadrícula usan `minmax(0, 1fr)` para impedir desbordamientos.

## Elevation & Depth

El sistema es plano por defecto. La mesa ilustrada y la superficie conjunta de plataformas reciben una sombra ambiental con desplazamiento y desenfoque para separarse del mantel. Los botones solo elevan ligeramente al pasar el puntero; el foco usa un contorno azul inequívoco, no una sombra.

### Shadow Vocabulary

- **Mesa elevada:** `0 18px 42px rgba(11, 64, 56, 0.14)` para una única superficie principal.
- **Acción disponible:** `0 8px 18px rgba(11, 64, 56, 0.18)` únicamente durante hover.

**The Flat-by-Default Rule.** La profundidad comunica una superficie compartida o un cambio de estado; nunca sustituye contenido.

## Shapes

Los controles y paneles son rectos, como carteles y manteles plegados. Los círculos quedan reservados para platos, marca, puntos de estado y numeración. La gran mesa ilustrada puede usar extremos muy curvos porque representa el objeto físico que organiza el mundo visual.

## Components

### Buttons

- **Shape:** rectángulo sin radio y borde de `2px`.
- **Primary:** verde Giramesa con texto blanco, ancho completo en cada puesto.
- **Hover / Focus:** elevación vertical de `2px` y sombra ambiental; foco azul de `3px` con separación de `4px`.
- **Disabled:** gris visible, contraste conservado, sin enlace ni acceso por tabulación hasta que exista un destino válido.

### Cards / Containers

- **Corner Style:** la mesa de plataformas no tiene radio y funciona como un único contenedor.
- **Background:** blanco plato sobre verde profundo.
- **Shadow Strategy:** una sola sombra compartida; las plataformas no se elevan por separado.
- **Internal Padding:** entre `2rem` y `4rem` según ancho.

### Navigation

La navegación usa enlaces de texto en negrita, sin cápsulas. En escritorio es horizontal; en móvil se apila a la derecha. Hover subraya y el foco conserva el anillo global.

### Release State

Combina un punto, texto explícito y metadatos. Disponible, cargando y no disponible nunca se comunican solo mediante color. Las notas remotas conservan saltos de línea como texto plano.

## Do's and Don'ts

### Do:

- **Do** mantener ambos canales visibles aunque uno sea recomendado o no esté disponible.
- **Do** usar ilustraciones SVG originales con el mismo trazo limpio y la paleta confirmada.
- **Do** variar densidad entre una entrada expresiva y guías de lectura calmada.
- **Do** respetar movimiento reducido y contenido visible antes de cualquier animación.

### Don't:

- **Don't** convertir cada bloque en una tarjeta flotante independiente.
- **Don't** usar gradientes, vidrio, tipografía externa, iconos de proveedor o imágenes copiadas.
- **Don't** usar rótulos decorativos sobre títulos; todo estado debe aportar información operativa.
- **Don't** ocultar una plataforma basándose en el agente de usuario.

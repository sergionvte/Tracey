# Colocar en la hoja, Recortar y ajustar el Contorno — diseño

2026-11-26 · Tracey 1.0 (todavía sin publicar)

## Para qué

Hoy, al elegir una foto, la imagen aparece centrada sobre la cámara y la persona la acomoda a mano (mover, pellizcar, girar) hasta que coincide con su hoja. Además, si la foto trae bordes o fondo que no quiere calcar, no hay forma de quitarlos. Queremos dos herramientas que ahorren ese trabajo:

1. **Colocar en la hoja**: con un botón, la app encuentra la hoja de papel en la imagen de la cámara y acomoda la referencia sobre ella.
2. **Recortar**: quitarle a la imagen lo que sobra.
3. **Ajustar el Contorno**: un slider para sacar más o menos detalle con el filtro Contorno, y elegir el color de las líneas.

Colocar y Recortar se usan **con un botón**. En Configuración hay una opción para cada una que hace que pase sola al abrir una imagen nueva. Vienen **apagadas por defecto**.

## Metas

- Un toque deja la imagen centrada, girada y del tamaño de la hoja, lista para bloquear.
- Recortar una imagen en pocos segundos, con proporciones útiles para calcar (hoja carta, A4).
- Todo lo que hacen estas herramientas se puede deshacer y se sigue ajustando con los dedos como hoy.

## Fuera de alcance (por ahora)

- **Deformar la imagen a las 4 esquinas** (perspectiva). Se colocan con el mismo sistema de hoy (mover, escalar, girar), sin inclinarla. Se puede agregar después sobre esto.
- **AR que sigue a la hoja** (ARKit). La colocación es de una vez. Si el teléfono se mueve después, la imagen no lo sigue, igual que hoy.
- **Enderezar la foto elegida** (corregir una foto de un dibujo tomada de lado).
- **Aparecer en la hoja de compartir de Fotos.** Requiere la cuenta de Apple Developer (App Group) y no funciona en LiveContainer. Queda como proyecto aparte.

## Lo que no puede pasar (anti-metas)

- Que algo se mueva o cambie sin que la persona lo pida: con las opciones automáticas apagadas, abrir una imagen se comporta exactamente como hoy.
- Que una colocación mala deje la imagen en un lugar raro sin salida: siempre hay *Deshacer*.
- Romper el time-lapse, el zoom, el modo Foto/Video o las configuraciones guardadas en la Biblioteca.
- Dependencias de terceros: todo con frameworks de Apple (Vision, SwiftUI, Core Image).

## Enfoques considerados

| | Qué hace | A favor | En contra |
|---|---|---|---|
| **A. Encajar (elegido)** | Vision detecta la hoja en un cuadro de la cámara. La imagen se centra en la hoja, se gira como la hoja y se escala para caber dentro. | Usa el modelo actual (offset/escala/rotación): la Biblioteca guarda la posición como hoy y los gestos siguen igual. | Si el teléfono está inclinado, la hoja se ve como trapecio y la imagen (rectangular) no coincide perfecto en las orillas. |
| B. Deformar a 4 esquinas | Igual, pero la imagen se deforma (homografía) a las esquinas exactas. | Coincidencia exacta aunque el teléfono esté en ángulo. | Hay que rehacer cómo se dibuja, se mueve y se guarda la imagen. Mucho más trabajo y riesgo. |
| C. ARKit | Ancla la imagen a la hoja en 3D. | Sigue a la hoja aunque se mueva el teléfono. | ARKit se adueña de la cámara: habría que rehacer el time-lapse, el zoom y el modo Foto/Video. |

Para recortar solo hay una forma razonable: una pantalla propia en SwiftUI. iOS no ofrece un recortador del sistema que se pueda usar en la app.

**Decisión:** Sergio eligió **A**, el recorte y el ajuste del Contorno. Lo de compartir desde Fotos queda para después.

## Cómo funciona

### 1. Colocar en la hoja

**Dónde está el botón.** En la columna de herramientas, junto a Enfocar y la Linterna. Solo se ve cuando hay imagen. Con la imagen bloqueada responde como los demás controles de edición: un aviso de «Desbloquea para editar».
*(Mi decisión: el ícono será un símbolo SF de documento con un visor, p. ej. `doc.viewfinder`. Etiqueta: «Colocar en la hoja».)*

**Qué pasa al tocarlo:**
1. Se toma **un cuadro** de la cámara. Ya existe una salida de video (`videoDataOutput`) que hoy solo usa el time-lapse. Debe seguir funcionando **mientras se graba un time-lapse**, así que los cuadros pasan por un solo receptor que se los da al time-lapse y, cuando hace falta, entrega uno a la detección.
2. Vision busca la hoja: primero `VNDetectDocumentSegmentationRequest` (pensado para papel), y si no encuentra nada, `VNDetectRectanglesRequest`. Si hay varias, se queda con la más grande y con mejor confianza. *(Mi decisión.)*
3. Las 4 esquinas se convierten de coordenadas del cuadro a coordenadas de la pantalla de la cámara (`contentView`, donde viven la vista previa y la imagen), con la misma conversión que usa la vista previa. Ojo: los cuadros normalmente vienen en vertical (rotación 90), pero durante un time-lapse en iPad horizontal la rotación cambia. La conversión debe usar la rotación real de la conexión y el `videoGravity` del modo (Foto: aspect-fit; Video: aspect-fill).
4. De las esquinas sale un rectángulo «promedio»: centro = centro del cuadrilátero; ángulo = promedio de los ángulos de los lados largos; ancho/alto = promedio de los lados opuestos.
5. La imagen se acomoda: **centro** en el de la hoja, **rotación** igual a la de la hoja y **escala** para que quepa completa dentro de la hoja con un margen pequeño (~3 % por lado). Si la imagen es horizontal y la hoja vertical (o al revés), se gira 90° extra cuando eso la deja más grande. *(Mi decisión: el margen y el giro automático de 90°.)*
6. Se anima a la nueva posición (como «Centrar imagen») y aparece un aviso «Colocada en la hoja» con **Deshacer**, que regresa offset, escala y rotación a como estaban.

**Si no encuentra la hoja:** aviso «No encontré la hoja · que se vea completa y con buena luz». La imagen no se mueve.

**Mientras busca** (normalmente menos de medio segundo): el botón muestra un indicador de actividad y no acepta otro toque.

**Interacción con el resto:**
- La colocación se calcula con la vista sin mover (sin el zoom/paneo del modo bloqueado). Como solo se usa desbloqueada, eso ya se cumple.
- El zoom de la cámara no cambia. La hoja se detecta como se ve en ese momento.
- La Biblioteca guarda la posición como siempre: offset, escala y rotación.

### 2. Recortar

**Dónde está el botón.** En el panel Ajustar, como una fila «Recortar» junto a Filtro, Cuadrícula y Espejo. Con la imagen bloqueada se comporta como el resto del panel.

**Pantalla de recorte** (pantalla completa, fondo oscuro):
- La imagen completa, encajada, con un marco de recorte encima. Fuera del marco se oscurece.
- Se arrastran las esquinas y los lados para cambiar el marco, y el centro para moverlo. Pellizcar dentro del marco no hace falta en esta versión. *(Mi decisión.)*
- Proporciones: **Libre**, **Original**, **Carta** (8.5 × 11), **A4** (210 × 297) y **Cuadrado**. Carta y A4 se pueden voltear de vertical a horizontal con un toque.
- Botones **Cancelar** y **Listo**, y **Restablecer** (volver a la imagen completa).
- Se trabaja sobre la imagen original, sin filtro. El filtro elegido se vuelve a aplicar sobre la imagen recortada.

**El recorte siempre se puede deshacer** (decisión de Sergio): Tracey nunca tira la foto completa.
- El modelo guarda dos cosas: la **foto original** (la que se eligió, completa) y un **rectángulo de recorte**, normalizado 0–1 en el espacio de la foto ya orientada. Sin recorte, el rectángulo es la foto completa.
- Lo que se dibuja (`overlayImage`, y de ahí filtros y miniaturas) es la original recortada a ese rectángulo. Se genera al recortar y al cargar.
- La pantalla de recorte siempre abre sobre **la foto original**, con el recorte actual ya marcado. **Restablecer** vuelve a la foto completa. Así, recortar otra vez nunca pierde nada.

**Al tocar Listo:**
- Se guarda el nuevo rectángulo y se vuelve a generar `overlayImage`. Las miniaturas de filtros se regeneran solas, porque ya reaccionan al cambio de imagen.
- La posición en pantalla: el recorte queda donde estaba esa parte de la imagen, sin saltar. Se ajustan offset y escala para que lo que queda no se mueva. *(Mi decisión.)*
- Aviso «Imagen recortada» con **Deshacer**, que regresa el rectángulo y la posición anteriores.
- La orientación EXIF se normaliza antes de recortar, para que una foto tomada de lado no salga girada.

**Biblioteca:**
- Cada entrada guarda **la foto original** (como hoy) más un campo opcional nuevo en `SavedImageConfiguration` con el rectángulo de recorte. No ocupa más espacio que hoy: solo se guarda una imagen.
- Al cargar se aplica el recorte. Las entradas viejas, sin el campo, cargan completas.
- La miniatura de la Biblioteca muestra la imagen recortada, que es lo que la persona ve al usarla.
- «Guardar en la Biblioteca» sobre una entrada cargada guarda el rectángulo nuevo. La foto original de la entrada no cambia.
- El *Deshacer* de «Quitar imagen» también regresa la original y el recorte.

### 3. Detalle y color del Contorno

Hoy el filtro Contorno tiene todo fijo: gris → desenfoque 1.5 → `CILineOverlay` con umbral 0.2 → líneas azules #1E6BFF (`ReferenceFilterRenderer`). Pasa a ser ajustable:

- **Dónde:** en el panel Ajustar, debajo de los mosaicos de filtro. Aparece **solo con Contorno elegido** y se anima al mostrarse y ocultarse.
- **Detalle:** un slider de *Menos* a *Más*. Más detalle = umbral más bajo y menos desenfoque (salen más líneas finas); menos detalle = umbral más alto y más desenfoque (solo las formas principales). El valor actual (0.2 / 1.5) queda en el medio del slider. Quien lo construya elige el rango exacto, probándolo con una foto con mucha textura y con un dibujo de líneas limpias. Doble toque en el slider lo regresa al medio, como en los demás sliders del panel.
- **Color:** una fila de muestras (azul actual —el predeterminado—, negro, rojo, verde, morado y blanco) más el selector de color del sistema (`ColorPicker`) al final para cualquier otro. *(Mi decisión: la paleta.)* El color se convierte a lineal antes de pasarlo a Core Image, igual que hoy, para que no salga más claro.
- **En vivo:** al mover el slider, la imagen se actualiza mientras arrastras (con un pequeño retraso para no recalcular en cada movimiento) y sin parpadeo: la versión anterior queda visible hasta que la nueva está lista. Lo mismo al cambiar de color. La caché de filtros debe tomar en cuenta el detalle y el color, no solo el filtro.
- **Miniatura:** el mosaico de Contorno refleja el color elegido.
- **Qué se recuerda:**
  - El **color** es parte de cada imagen *y* hay un color preferido. Cada vez que la persona elige un color, ese pasa a ser el **preferido**, y cada imagen **nueva** empieza con él. Una entrada de la **Biblioteca** abre con **su propio color**, el que tenía al guardarla, y cargarla no cambia el preferido. *(Decisión de Sergio.)*
  - El **detalle** depende de cada foto: cada imagen nueva empieza en el medio. *(Mi decisión.)*
  - «Guardar en la Biblioteca» guarda el detalle y el color actuales, como campos opcionales nuevos en `SavedImageConfiguration`. Las entradas viejas cargan con el valor medio y el azul. El *Deshacer* de «Quitar imagen» también los regresa.
  - La miniatura del Contorno usa el color de la imagen actual.

### 4. Configuración

Una sección nueva, **«Al abrir una imagen»**, entre Velocidad del time-lapse e Ícono de la app:
- **Recortar al abrir**: apagado por defecto.
- **Colocar en la hoja al abrir**: apagado por defecto.
- Pie de sección: «Solo con imágenes nuevas de Fotos. Siempre puedes hacerlo con los botones.»

**Qué es «abrir»:** elegir una imagen nueva con «Elegir imagen». Cargar algo de la Biblioteca **no** dispara nada, porque ya trae su posición guardada.

**Orden si las dos están prendidas:** primero la pantalla de recorte. Al terminar (Listo o Cancelar), se coloca en la hoja.

**Colocar al abrir:** la cámara se enciende al haber imagen, así que se espera a tener cuadros, hasta ~2 s. Si no encuentra la hoja, el aviso es el mismo que con el botón, y la imagen se queda centrada como hoy.

### 5. Idiomas

Todos los textos nuevos en inglés y español (`Localizable.xcstrings`), como el resto de la app.

## Pruebas

- **Pruebas unitarias** (TraceyTests): que el Contorno con distinto detalle da resultados distintos y con el color pedido, que las configuraciones viejas cargan sin recorte y con los valores predeterminados del Contorno, el recorte se guarda y vuelve a aplicarse, y la geometría, que va en funciones puras: cuadrilátero → rectángulo promedio, encaje con margen y giro de 90°, conversión de coordenadas con cada rotación y `videoGravity`, recorte → nuevo offset/escala sin salto, y proporciones del recorte.
- **Simulador:** no tiene cámara. En DEBUG, el cuadro sintético que ya existe para el time-lapse dibuja una «hoja» blanca girada sobre fondo oscuro, y Vision corre de verdad sobre él. Así se prueba todo el flujo: botón, colocación, Deshacer, ajustes automáticos y recorte.
- **iPhone real:** lo prueba Sergio vía LiveContainer. Vision funciona ahí, a diferencia de las extensiones.

## Lo que queda al criterio de quien lo construya

- Los nombres de tipos y archivos, y cómo repartir el código (p. ej. `SheetDetector.swift`, `CropView.swift`).
- Los umbrales de Vision (confianza mínima, tamaño mínimo de la hoja en pantalla) que funcionen bien con papel real.
- Los detalles visuales de la pantalla de recorte, siguiendo el estilo de la app (vidrio, color de acento, hápticos).

## Detalles resueltos en la revisión (decisiones mías)

- **Ángulo de la hoja:** una hoja vista desde arriba da el mismo rectángulo a 0°, 90°, 180° o 270°. Se elige el ángulo más cercano a la rotación actual de la imagen, para que no gire de cabeza.
- **Espejo:** Colocar en la hoja respeta el espejo actual (solo cambia offset, escala y rotación). El recorte se hace sobre la imagen sin espejo, en el sentido de la foto original, y el espejo se sigue aplicando encima.
- **Simulador:** la detección necesita cuadros sintéticos aunque no se esté grabando un time-lapse. En DEBUG, la fuente sintética entrega un cuadro a la detección cuando no hay cámara.
- **Primera vez:** si el recorrido de bienvenida está abierto, «Recortar al abrir» espera a que se cierre.
- **Recortar y Contorno:** recortar no cambia el detalle ni el color del Contorno.

## Decisiones mías para revisar

1. Margen de ~3 % dentro de la hoja y giro automático de 90° si la imagen cabe más grande.
2. Botón de colocar en la columna de herramientas y Recortar como fila del panel Ajustar.
3. Proporciones de recorte: Libre, Original, Carta, A4 y Cuadrado.
4. El detalle del Contorno es por imagen y empieza en el medio.
5. Opciones automáticas apagadas por defecto y solo para imágenes nuevas, no al cargar de la Biblioteca.
6. Paleta del Contorno: azul, negro, rojo, verde, morado y blanco, más el selector libre.

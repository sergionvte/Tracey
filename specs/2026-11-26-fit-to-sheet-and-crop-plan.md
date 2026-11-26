# Colocar en la hoja, Recortar y Contorno ajustable — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Contorno con detalle y color ajustables, recorte recuperable y «Colocar en la hoja» con Vision, más dos opciones automáticas en Configuración.

**Architecture:** La geometría vive en funciones puras con pruebas: `OutlineStyle`, `ImageCropping`, `CropRectMath` y `SheetGeometry`. `CameraViewModel` guarda la foto original más el rectángulo de recorte; `overlayImage` es la original ya recortada. La detección toma un solo cuadro del `videoDataOutput` existente, sin romper el time-lapse, y lo pasa a Vision. La colocación resultante se aplica con el modelo de siempre: offset, escala y rotación.

**Tech Stack:** Swift, SwiftUI, AVFoundation, Vision, Core Image, Swift Testing. Sin dependencias.

**Spec:** `specs/2026-11-26-fit-to-sheet-and-crop-design.md`

**Ejecución:** nativa (Sergio pidió implementar directo al terminar el plan).

## Global Constraints

- iOS 18.5+, iPhone y iPad. Sin paquetes de terceros.
- Cada texto nuevo va en `Tracey/Localizable.xcstrings` con su traducción `es` (ver tabla de textos).
- Configuraciones viejas de la Biblioteca deben seguir cargando: todos los campos nuevos de `SavedImageConfiguration` son opcionales.
- Comentarios de código en inglés, como el resto del proyecto.
- Prueba: `xcodebuild test -project Tracey.xcodeproj -scheme Tracey -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TraceyTests`

### Textos (en → es)

| en | es |
|---|---|
| Detail | Detalle |
| Less detail / More detail (a11y) | Menos detalle / Más detalle |
| Line Color | Color de línea |
| Blue / Black / Red / Green / Purple / White | Azul / Negro / Rojo / Verde / Morado / Blanco |
| Custom color | Color personalizado |
| Crop | Recortar |
| Image cropped | Imagen recortada |
| Reset | Restablecer |
| Free / Original / Letter / A4 / Square | Libre / Original / Carta / A4 / Cuadrado |
| Fit to Sheet | Colocar en la hoja |
| Placed on the sheet | Colocada en la hoja |
| Couldn't find the sheet · show all of it, in good light | No encontré la hoja · que se vea completa y con buena luz |
| When Opening an Image | Al abrir una imagen |
| Crop on Open | Recortar al abrir |
| Fit to Sheet on Open | Colocar en la hoja al abrir |
| Only for new images from Photos. You can always use the buttons. | Solo con imágenes nuevas de Fotos. Siempre puedes hacerlo con los botones. |

## Review Focus

1. **Foto con orientación EXIF** (retrato de iPhone, `.right`): el recorte guardado y recargado debe cubrir la misma zona que se vio. → prueba en Task 3.
2. **Sin hoja o casi fuera de cuadro** (fondo vacío, cuadrilátero diminuto): no se mueve nada y sale el aviso. → prueba en Task 5 (`SheetGeometry.isPlausible`).
3. **Imagen horizontal sobre hoja vertical, u hoja girada ~180°**: giro de 90° si cabe más grande y nunca de cabeza. → prueba en Task 5.
4. **Biblioteca vieja** sin campos nuevos: carga completa, con detalle 0.5 y azul. → pruebas en Tasks 1 y 3.
5. **Colocar mientras se graba un time-lapse**: el cuadro de detección no le roba cuadros al time-lapse. → prueba en Task 6 (`TimelapseRecorder.requestNextFrame`).

---

### Task 1: `OutlineStyle` y renderer

**Files:** Create `Tracey/OutlineStyle.swift`; Modify `Tracey/ReferenceFilter.swift`, `Tracey/SavedImageConfiguration.swift`; Test `TraceyTests/TraceyTests.swift`

**Interfaces — Produces:**
- `struct OutlineColor: Codable, Hashable { var red, green, blue: Double }` (sRGB 0–1); `static let blue (#1E6BFF), black (#000000), red (#E53935), green (#2E9E4F), purple (#8E44EC), white (#FFFFFF)`; `static let presets: [OutlineColor]`; `init(_ color: UIColor)`; `var uiColor: UIColor`; `static var preferred: OutlineColor { get set }` (UserDefaults `outlineColor`, JSON; default `.blue`).
- `struct OutlineStyle: Codable, Hashable { var detail: Double = 0.5; var color: OutlineColor = .blue }`; `var lineThreshold: Double`, `var blurRadius: Double`. Interpolación por tramos: detalle 0 → (0.45, 3.0), 0.5 → (0.2, 1.5), 1 → (0.05, 0.5).
- `ReferenceFilterRenderer.render(_:filter:outline:maxLongSide:)`; la sobrecarga vieja llama con `OutlineStyle()`.
- `SavedImageConfiguration`: `outlineDetail: Double?`, `outlineColor: OutlineColor?`, `var outlineStyle: OutlineStyle` (con valores por defecto para los nil).

- [ ] Pruebas: `outlineMiddleKeepsTodaysLook` (detalle 0.5 → 0.2 / 1.5); `moreDetailLowersThreshold` (monótono); `outlineRendersInChosenColor` (render de una imagen con un cuadro negro en rojo → algún píxel opaco con R > 0.8, G < 0.3); `oldSavesLoadDefaultOutline` (JSON sin campos → detalle 0.5, `.blue`).
- [ ] Correr → fallan. Implementar. Correr → pasan. Commit.

### Task 2: Contorno en el modelo y la UI

**Files:** Modify `Tracey/CameraViewModel.swift`, `Tracey/TraceyControls.swift`, `Tracey/ImageStorageManager.swift`, `Tracey/SavedImagesView.swift`, `Tracey/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 1.
- Produces: `@Published private(set) var outlineStyle: OutlineStyle` en `CameraViewModel`; `func setOutlineDetail(_:)` (render con retraso de 0.12 s, `keepPrevious: true`); `func setOutlineColor(_:)` (también guarda `OutlineColor.preferred`). La caché se indexa por `(ReferenceFilter, OutlineStyle?)`: el estilo solo cuenta con `.outline`. `RemovedReference` lleva `outlineStyle`. Las imágenes nuevas usan `OutlineStyle(detail: 0.5, color: .preferred)`. Al cargar de la Biblioteca se usa `configuration.outlineStyle` y no se toca el preferido. `saveImageConfiguration(…, outlineStyle:)`.
- UI: `OutlineControls` en `AdjustPanel`, debajo de `FilterPicker`, visible solo con `.outline` (con transición): fila «Detail» con slider 0…1 (doble toque → 0.5) y fila «Line Color» con 6 muestras más `ColorPicker` (sin opacidad). Activo también con la imagen bloqueada, igual que los filtros. Las miniaturas de la Biblioteca usan el estilo guardado.

- [ ] Implementar. Agregar textos. Build. Revisar en el simulador: el slider cambia el detalle en vivo, el color cambia la imagen y la miniatura, y al guardar y cargar de la Biblioteca se conservan. Commit.

### Task 3: Recorte (geometría y modelo)

**Files:** Create `Tracey/ImageCropping.swift`; Modify `Tracey/CameraViewModel.swift`, `Tracey/SavedImageConfiguration.swift`, `Tracey/ImageStorageManager.swift`, `Tracey/SavedImagesView.swift`; Test `TraceyTests/TraceyTests.swift`

**Interfaces — Produces:**
- `enum ImageCropping`: `static func normalizedUp(_ image: UIImage) -> UIImage`; `static func crop(_ image: UIImage, to rect: CGRect) -> UIImage?` (rect normalizado 0–1, origen arriba-izquierda, sobre la imagen `.up`; `unitRect` → la misma imagen); `static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)`.
- `static func placementAfterCrop(sourceSize: CGSize, oldCrop: CGRect, newCrop: CGRect, layoutSize: CGSize, scale: CGFloat, offset: CGSize, rotation: Double, isFlipped: Bool, isFlippedVertically: Bool) -> (scale: CGFloat, offset: CGSize)`. Mantiene los puntos por píxel de la fuente (`fitNew·scaleNew = fitOld·scaleOld`, con `fit = min(W/w, H/h)` del tamaño recortado) y mueve el centro según el desplazamiento del centro del recorte en píxeles: espejo → escala → rotación, como en `layoutOverlay`.
- `enum CropAspect: CaseIterable { case free, original, letter, a4, square }` con `func ratio(sourceSize: CGSize, landscape: Bool) -> CGFloat?` (ancho/alto; letter 8.5/11, a4 210/297; landscape invierte).
- `CameraViewModel`: `private(set) var sourceImage: UIImage?`, `@Published private(set) var cropRect: CGRect`, `func applyCrop(_ rect: CGRect, layoutSize: CGSize) -> CropUndo?`, `func undoCrop(_ undo: CropUndo)` (`struct CropUndo { cropRect, scale, offset }`). `overlayImage` se vuelve el recorte de `sourceImage`. Nuevo de Fotos → `sourceImage = normalizedUp(img)`, `cropRect = unitRect`. Cargar → aplica `configuration.cropRect ?? unitRect`. Guardar escribe `sourceImage` y `cropRect`. `RemovedReference` lleva `sourceImage` y `cropRect`. La miniatura de la Biblioteca aplica el recorte antes del filtro.
- `SavedImageConfiguration.cropRect: CGRect?`.

- [ ] Pruebas: `cropTakesTheRightPixels` (imagen 4×2 de dos colores, recorte de la mitad derecha → solo color B); `cropRespectsExifOrientation` (CGImage con `.right` → `normalizedUp` + recorte de la mitad de arriba = la mitad que se veía arriba); `cropKeepsRemainingPartInPlace` (sin rotación: recortar la mitad derecha deja `offset.width > 0` y `fit·scale` sin cambio; con 90° el desplazamiento se vuelve vertical); `aspectRatios` (Carta vertical = 8.5/11, A4 horizontal = 297/210, original = ancho/alto de la fuente, libre = nil); `cropRectSurvivesSaving` y `oldSavesLoadUncropped`.
- [ ] Fallan → implementar → pasan. Commit.

### Task 4: Pantalla de recorte

**Files:** Create `Tracey/CropView.swift`; Modify `Tracey/TraceyControls.swift` (fila «Crop» en `AdjustPanel`, deshabilitada al bloquear), `Tracey/ContentView.swift`, `Tracey/Localizable.xcstrings`; Test `TraceyTests/TraceyTests.swift`

**Interfaces:**
- `enum CropHandle { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move }`
- `enum CropRectMath { static func adjust(_ rect: CGRect, handle: CropHandle, by translation: CGSize, aspect: CGFloat?, minSize: CGFloat) -> CGRect }`: trabaja en coordenadas normalizadas, siempre dentro de `unitRect`, mantiene la proporción (en píxeles: `aspect` ya convertido por la vista) y tiene un tamaño mínimo. `static func fitted(_ rect: CGRect, aspect: CGFloat) -> CGRect`: el rectángulo más grande con esa proporción, centrado en el actual.
- `struct CropView: View { image: UIImage; initialRect: CGRect; onCancel: () -> Void; onDone: (CGRect) -> Void }`. Fondo negro, imagen encajada, máscara oscura fuera del marco, 4 esquinas y 4 lados arrastrables, el centro para mover, fila de `CropAspect` (Carta/A4 con un toque para voltear), y botones Cancel / Reset / Done.
- `ContentView`: `@State cropSession: CropSession?` → `.fullScreenCover(item:)`. Done → `viewModel.applyCrop(rect, layoutSize:)` y aviso «Image cropped» con Undo (8 s).

- [ ] Pruebas: `dragCornerShrinks`, `handlesStayInsideImage`, `aspectIsKept` (con aspecto 1 → width·W == height·H), `minimumSize`.
- [ ] Fallan → implementar → pasan. Build y prueba en el simulador (abrir, recortar, Undo, recortar otra vez y Restablecer vuelve a la foto completa). Commit.

### Task 5: Geometría de la hoja

**Files:** Create `Tracey/SheetGeometry.swift`; Test `TraceyTests/TraceyTests.swift`

**Interfaces — Produces** (`enum SheetGeometry`):
- `struct Quad { var topLeft, topRight, bottomRight, bottomLeft: CGPoint }`
- `static func devicePoint(fromBuffer p: CGPoint, rotationAngle: CGFloat) -> CGPoint`: normalizado con origen arriba-izquierda; deshace la rotación de la conexión (0/90/180/270). Con 90: `(x_d, y_d) = (p.y, 1 − p.x)`.
- `static func isPlausible(_ quad: Quad, in size: CGSize) -> Bool`: convexo y con área ≥ 8 % de `size`.
- `static func sheetRect(_ quad: Quad) -> (center: CGPoint, size: CGSize, angle: Double)`: ángulo en grados, el promedio de los dos lados «horizontales».
- `static func placement(sheet: Quad, imageSize: CGSize, layoutRect: CGRect, currentRotation: Double, margin: CGFloat = 0.03) -> (offset: CGSize, scale: CGFloat, rotation: Double)`: prueba las rotaciones `angle + k·90`, k ∈ 0…3. Se queda con la de mayor escala que quepa; si empatan, la más cercana a `currentRotation`. Escala = el ajuste de la imagen girada dentro de la hoja menos el margen, dividido entre el `fit` base de `layoutRect`. Offset = centro de la hoja − centro de `layoutRect`.

- [ ] Pruebas: `deviceMappingRoundTrip` (90° y 270°); `tinyQuadIsNotASheet`; `axisAlignedSheetCentersAndFits` (hoja de 300×400 centrada → offset 0, imagen 3:4 de alto 400·0.94); `landscapeImageTurnsOnPortraitSheet` (rotación 90 o 270); `upsideDownSheetStaysUpright` (hoja a 178° con `currentRotation` 0 → rotación ≈ −2/358); `offsetFollowsSheetCenter`.
- [ ] Fallan → implementar → pasan. Commit.

### Task 6: Un cuadro de la cámara + Vision

**Files:** Create `Tracey/SheetDetector.swift`; Modify `Tracey/TimelapseRecorder.swift`, `Tracey/CameraView.swift`, `Tracey/SyntheticFrameSource.swift`; Test `TraceyTests/TraceyTests.swift`

**Interfaces:**
- `TimelapseRecorder.requestNextFrame(_ handler: @escaping (CVPixelBuffer) -> Void)`: thread-safe. En `consume`, antes de cualquier filtro, entrega el buffer a los handlers pendientes (una vez) y luego sigue normal.
- `CameraUIView.captureFrame(timeout: TimeInterval, completion: @escaping (CVPixelBuffer?, CGFloat) -> Void)` (main queue; el segundo valor es el ángulo de rotación del buffer). Si hay grabador activo usa `requestNextFrame`; si no, pone un delegado temporal `OneShotFrameGrabber` en su propia cola y lo quita después de un cuadro (en `sessionQueue`, sin pisar a un grabador que haya arrancado mientras tanto). En DEBUG, en el simulador sin cámara, entrega `SyntheticFrameSource.sheetFrame(size:)`: fondo gris oscuro con una hoja blanca girada 6°.
- `CameraUIView.layerPoint(fromBufferNormalized:rotationAngle:) -> CGPoint`: `devicePoint` → `previewLayer.layerPointConverted(fromCaptureDevicePoint:)`. En el simulador, aspect-fill directo del buffer a `bounds`.
- `enum SheetDetector { static func detect(in buffer: CVPixelBuffer, completion: @escaping (SheetGeometry.Quad?) -> Void) }`: primero `VNDetectDocumentSegmentationRequest` y, si falla o no hay resultado, `VNDetectRectanglesRequest` (`minimumConfidence 0.6`, `minimumSize 0.2`, `maximumObservations 4`, la de mayor área). Coordenadas devueltas normalizadas, origen arriba-izquierda. Completion en main.
- `CameraUIView.detectSheetPlacement(imageSize: CGSize, currentRotation: Double, timeout: TimeInterval, completion: @escaping ((offset: CGSize, scale: CGFloat, rotation: Double)?) -> Void)`: une todo y usa `overlayLayoutRect`. Si no hay cuadro dentro de `timeout`, reintenta hasta el plazo (para «al abrir», la cámara todavía arranca).

- [ ] Pruebas: `recorderHandsOutOneFrameAndKeepsRecording` (handler llamado una vez y `framesWritten` sigue subiendo); `detectorFindsSyntheticSheet` (Vision sobre `sheetFrame` → cuadrilátero con centro a ±5 % del dibujado); `detectorFindsNothingOnBlank` (gris liso → nil).
- [ ] Fallan → implementar → pasan. Commit.

### Task 7: Botón «Colocar en la hoja»

**Files:** Modify `Tracey/TraceyControls.swift` (`ToolColumn`: `GlassIconButton` `doc.viewfinder`, con `ProgressView` mientras busca), `Tracey/ContentView.swift`, `Tracey/CameraViewModel.swift`, `Tracey/Localizable.xcstrings`

**Interfaces:**
- `CameraViewModel.applyPlacement(offset:scale:rotation:) -> PlacementUndo` (animado como `centerImage`) y `undoPlacement(_:)`.
- `ContentView.fitToSheet(automatic: Bool)`: si está bloqueado → `lockedWarning()`. Si no, `isFittingSheet = true` → `detectSheetPlacement(timeout: automatic ? 2 : 1)` → aviso «Placed on the sheet» con Undo (8 s), o el aviso de error en rojo con `Haptics.warning()`.

- [ ] Build. En el simulador (hoja sintética): el botón coloca la imagen, Undo la regresa y con la imagen bloqueada sale el aviso. Commit.

### Task 8: Opciones automáticas

**Files:** Modify `Tracey/SettingsView.swift`, `Tracey/ContentView.swift`, `Tracey/Localizable.xcstrings`

**Interfaces:** `@AppStorage("autoCropOnOpen")` y `@AppStorage("autoFitSheetOnOpen")` (false). Nueva sección después de la del time-lapse. En `ContentView`, al elegir con `ImagePicker` (callback `onImagePicked`), se marca `pendingOpenActions`. En el `onDismiss` del picker, y cuando el recorrido no está abierto: recorte (si aplica) → al cerrarlo, Listo o Cancelar → colocar (si aplica, `automatic: true`). Cargar de la Biblioteca no dispara nada.

- [ ] Build. En el simulador: con las dos opciones prendidas, elegir una foto abre el recorte y luego se coloca. Con las dos apagadas, se comporta como hoy. Commit.

### Task 9: Verificación y entrega

- [ ] Todas las pruebas unitarias pasan.
- [ ] Revisar en el simulador, en español: panel Ajustar, recorte, colocar, Configuración y que se vea bien en modo oscuro.
- [ ] `git push origin main`, `Tools/make-ipa.sh` y mandar el .ipa.

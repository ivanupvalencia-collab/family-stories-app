# Encuadre de fotos

Todas las selecciones de galería pasan por `PhotoSelectionService.pick` antes
de modificar un borrador o llamar al almacenamiento. Cancelar la galería, el
editor o volver atrás devuelve `null` y conserva la foto anterior. Eliminar
una foto conserva su flujo existente y no abre el editor. Los avatares del
catálogo tampoco requieren seleccionar una foto de galería.

- `PhotoEditorScreen`: pantalla compartida, un único encuadre cuadrado,
  desplazamiento, pinza y slider sincronizados.
- `SquarePhotoCrop`: coordenadas de origen; limita zoom y desplazamiento para
  que el encuadre siempre esté cubierto. La pinza conserva su punto focal.
- `PhotoCropService`: decodificación y exportación mediante `dart:ui`, sin
  código específico de Android/iOS. La vista previa y
  la exportación usan el mismo rectángulo de origen.

La decodificación limita el lado mayor a 4096 píxeles. Se exporta JPEG al
90%, sin máscara circular, hasta 1536 píxeles por lado y sin ampliar fotos
pequeñas. La transparencia se aplana sobre el fondo crema neutro de Aritoria.
`PhotoJpegEncoder` aísla el paquete Dart `image`; su implementación codifica
los píxeles finales en un isolate para no bloquear la interfaz. El rectángulo
de origen y la resolución son los mismos que antes de cambiar el formato.
El archivo exportado no conserva los metadatos originales. Una imagen que el códec no pueda abrir muestra un error
y no permite guardar.

Los servicios existentes siguen gestionando rutas, permisos, subida, borrado
y cachés. El editor solo devuelve `PickedProfileImage` con sus bytes finales y
`image/jpeg`. Para añadir otra entrada de galería, reutilizar
`PhotoSelectionService.pick` en lugar de llamar directamente al picker.

Las nuevas subidas de avatar usan `usuario/profile.jpg`; las URLs antiguas sin
extensión o con otra extensión siguen leyéndose sin cambios. Las fotos de
familiares e historias derivan `.jpg` del MIME mediante el helper existente.
No se convierten imágenes existentes: PNG/WebP/JPEG conservan sus referencias,
lectores y cachés hasta que el usuario seleccione y guarde otra foto.

# Waveform de Historia: extracción y caché privada

Se usa audio_waveforms 2.0.2 exclusivamente en DeviceStoryWaveformService.
No se crea PlayerController ni RecorderController de ese paquete.
AudioAnswerService/audioplayers siguen controlando playback, tiempos y seek.

- Entrada: archivo local .m4a; remoto mediante localAudioPathFor, con descarga
  autenticada y validacion de la cache de audio existente.
- Extraccion: 256 amplitudes RMS reales. Se validan y normalizan al pico del audio;
  el silencio permanece plano. No se inventan barras ni se extrae de bytes AAC
  sin decodificar.
- Vista: agrupa muestras reales segun el ancho y colorea lo reproducido con la
  posicion de audioplayers. Tap/drag y accesibilidad reutilizan el seek existente.
- Carga: indicador circular integrado, sin slider temporal. El slider solo
  aparece si la recuperación/extracción falla. Extraer nunca inicia playback.
- Persistencia: JSON validado en ApplicationSupport/story_waveforms_v1,
  separado por backend, cuenta, familiar e historia; escritura staging + flush
  y rename. No se guarda audio adicional en esta caché.
- Identidad: audio_path + versión/parámetros del extractor. Los objetos remotos
  son inmutables en los uploads actuales (upsert: false); una ruta diferente
  invalida las muestras. El audio local valida además tamaño y modificación.
- Lectura: memoria (hasta 64 entradas), luego disco; solo un miss resuelve el
  archivo de audio y extrae. Reabrir una waveform remota cacheada no descarga audio.
- Concurrencia: los lectores y el precálculo comparten una única tarea por audio.
  Navegar atrás no cancela trabajo compartido; cambiar cuenta o eliminar el
  familiar lo invalida y bloquea resultados/escrituras tardías.
- Precálculo: después de guardar el audio local y cuando el archivo remoto ya
  está descargado/validado, sin esperar la extracción para completar el guardado
  o devolver la ruta del audio.
- Limpieza: borrar un familiar elimina sus muestras. Logout/cambio de cuenta
  elimina memoria y disco del ámbito remoto anterior y cancela sus extractores.
  La caché local del dispositivo permanece separada de las cuentas remotas.

Validacion nativa reproducible (sin backend):

```powershell
flutter run -d emulator-5554 -t tool/story_waveform_smoke.dart
```

La herramienta lee un .m4a ya presente en el almacenamiento privado de la app,
sin modificarlo. Si no existe, graba un clip AAC-LC mono con el servicio actual
(y requiere permiso de microfono). Solo imprime fuente generica, numero de
muestras y rango, nunca rutas, IDs, credenciales ni contenido de audio.
Comprueba deduplicación (dos lectores, una extracción) y reapertura desde disco
sin resolver el audio otra vez. Imprime WAVEFORM_CACHE_SMOKE_OK con el tiempo de
lectura. Usa un namespace de caché propio y muestra la onda real. No crea
historias ni inicializa Supabase. Al terminar, volver a ejecutar la app normal:

```powershell
flutter run -d emulator-5554
```

Android: se ha validado extraccion de 256 muestras de un .m4a privado existente
sobre Android 15/API 35 y build debug con la configuracion actual. El plugin
emite el aviso de Flutter sobre Kotlin antiguo; no se han cambiado flags Gradle.
La prueba de caché sobre el .m4a existente obtuvo 256 muestras, una extracción
para dos lectores y reapertura desde disco en 45 ms (Android 15/API 35).
iOS queda pendiente de validación nativa.

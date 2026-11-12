# Auditoría integral — family-stories-app

**Fecha:** 2026-11-11 · **Modo original:** solo lectura (ningún archivo modificado
por la auditoría) · **Stack:** Flutter + Supabase · **Cifras en el momento del
análisis:** 13.147 LOC en `lib/` (61 archivos) · 12.341 LOC en `test/` (289
tests) · 15 scripts SQL/MD en `supabase/manual/`

Esta tabla es la **fuente de verdad del estado**. Las fichas de cada eje
conservan el texto original de la auditoría; el estado puede haber cambiado
desde entonces.

| ID | Hallazgo | Sev. | Estado |
|---|---|---|---|
| S-1 | Frontera de autorización inauditable (esquema + RLS sin versionar) | Alto | ✅ `b878d8c` · `supabase/migrations/` |
| S-2 | Dominio de deep-link inexistente → App Links no verificables | Alto | ✅ `cd5a1e0` · scheme propio `familystories://` |
| S-3 | JWT + refresh token + verificador PKCE en SharedPreferences en claro | Alto | ✅ este commit · `secure_session_storage.dart` |
| S-4 | Release firmado con el keystore de debug + `applicationId` placeholder | Medio | ⏳ **veto: no tocar el keystore** |
| S-5 | `profiles.avatar_url` es URL libre → SSRF on-device / probing de LAN | Medio | ✅ este commit · allowlist en cliente + migración `20261112000001` (**no aplicada**) |
| S-6 | El logout no limpia fotos/audio/lista remota en disco | Medio | ⏳ abierto |
| S-7 | `signOut()` sin `finally` | Medio | ⏳ abierto |
| S-8 | Flag de borrado remoto activo sin el gate auditado | Medio | ⏳ abierto |
| S-9 | Tokens de invitación como oráculos de existencia | Medio | ↘️ Bajo (token de 256 bits, `sha256`, 7 días) |
| S-10 | `onAuthStateChange` sin `onError` en 5 puntos | Bajo | ⏳ abierto |
| S-11 | `detectSessionInUri` en `true` por defecto | Bajo | ✅ `cd5a1e0` |
| S-12/13/14/15 | Content-type por nombre · sin `maxLength` · `.gitignore` sin `.env*`/keystores · PII en docs | Bajo | ⏳ abierto |
| S-16 | Enlace inicial (`getInitialUri`) no capturado | Bajo | ✅ `cd5a1e0` |
| S-17 | SQL reescribe políticas ajenas con `alter policy ... format(...)` | Medio | ⏳ documentado |
| S-19 | `get_story_metadata` devuelve `can_edit` siempre `true` | Medio | ⏳ documentado en `0003` |
| S-23 | Buckets sin límite de tipo/tamaño | Medio | ✅ `b878d8c` · `0007` |
| S-24 | `TRUNCATE` para `anon`/`authenticated` | Alto | ✅ `b878d8c` · `0007` |
| S-25 | `question_text` sin límite superior | Medio | ✅ `b878d8c` · `0007` |
| S-26 | PII en comentario de una función | Bajo | ✅ `b878d8c` · `0003` |
| S-27 | `updated_at` sin trigger en 4 tablas | Bajo | ⏳ documentado en `0004` |
| S-28 | `get_family_invitation_preview` hace `FOR UPDATE` en una lectura | Medio | ⏳ documentado en `0003` |
| S-29 | Bucket `avatars` sin política `DELETE` | Bajo | ⏳ abierto |
| S-30 | Política muerta en `family_invitations` | Bajo | ⏳ documentado en `0002` |
| S-31 | Ver `0007_hardening.sql` | — | ✅ `b878d8c` |
| A-1…A-12 | Eje de arquitectura | — | ⏳ Fase 3 |
| C-1…C-18 | Eje de concurrencia y rendimiento | — | ⏳ ver plan por fases |

---

## Resumen ejecutivo

| Eje | Hallazgos | Críticos/Altos | Estado |
|---|---|---|---|
| 1. Seguridad | 22 | 3 | 🟠 Riesgo alto |
| 2. Arquitectura | 20+ | 5 | 🟠 Deuda estructural |
| 3. Concurrencia/Rendim. | 17 | 5 | 🔴 Correctidad en riesgo |

**Controles que SÍ están bien (verificados):** cero secretos `service_role`/
`sb_secret` en el árbol ni en los 34 commits del historial · cero SQL crudo en
Dart (todo query-builder o `.rpc()` con nombre fijo) · cero `print`/`debugPrint`
de PII · ninguna política `using (true)` en el SQL versionado · defensas de
path-traversal rigurosas (regex por segmento + base64url) · 168 guardas `mounted`
sin uso real de `BuildContext` tras `await` · cero ciclos de importación ·
`Future.wait` bien usado en los puntos paralelizables · guards anti-double-submit
correctos en `question_screen` y `accept_invitation_screen`.

---

# EJE 1 — SEGURIDAD

## 🔴 S-1 · La frontera de autorización completa es inauditable (Alto)

El esquema base y todas las RLS de `family_members`, `stories`,
`question_requests`, `family_invitations`, `profiles` no estaban versionados —
lo declaraba el propio repo (`supabase/manual/06_...sql:1` — *"The baseline
schema is not versioned in this repository"*). El cliente escribe directamente
con solo filtros de igualdad client-side:

```dart
// family_member_service.dart:121 — el filtro eq() no enforcea nada por sí solo
.from('family_members').select(...).eq('owner_id', ownerId)

// profile_service.dart:141 — profiles es escribible por el cliente
.update({'name': name, 'avatar_key': avatarKey, 'avatar_url': avatarUrl})
.eq('id', userId)
```

Si cualquier tabla base tiene una política permisiva, hay divulgación
cross-account y no hay forma de verlo en el repositorio. Lo mismo aplica a los
buckets `avatars` y `story-audio` y a los RPC `send_question_request` /
`accept_family_invitation`.

**Fix aplicado:** volcado del esquema a `supabase/migrations/`, más
`tool/lint_rls.sh`.

## 🔴 S-2 · El dominio de deep-link no existe → App Links no verificables (Alto)

Verificado en vivo: `nslookup familystories.app` → **NXDOMAIN**.

`AndroidManifest.xml` declaraba `autoVerify="true"` sobre
`https://familystories.app/invite/`. Consecuencias: (a) `assetlinks.json` es
imposible de publicar → el enlace de invitación (un bearer token) lo puede
reclamar cualquier otra app; (b) el dominio no registrado puede ser reclamado
por un tercero; (c) los enlaces compartidos simplemente no resuelven.

**Fix aplicado:** scheme propio `familystories://invite/<token>` (opción A,
decisión del propietario). Riesgo residual aceptado: cualquier app puede
registrar el scheme, y el scheme no se linkifica en mensajeros — por eso el
campo de código acepta el enlace entero pegado.

## 🔴 S-3 · JWT + refresh token + verificador PKCE en SharedPreferences en claro (Alto)

`flutter_secure_storage` no aparecía en `pubspec.lock` (0 coincidencias) y el
manifest no desactivaba backups. La sesión completa vivía en XML/plist sin
cifrar y viajaba en device-backup.

Verificado en el código del paquete: `supabase_flutter` instala por defecto
`SharedPreferencesLocalStorage` con la clave
`sb-hwqvdrtehvixqloegilg-auth-token` y `SharedPreferencesGotrueAsyncStorage`
con la clave `supabase.auth.token-code-verifier`.

**Fix aplicado:** `lib/services/secure_session_storage.dart` con
`SecureLocalStorage` y `SecureGotrueAsyncStorage` sobre un Keystore/Keychain,
migración idempotente que solo borra el texto plano tras verificar la lectura,
y `android:allowBackup="false"`.

**Decisión de producto:** al desactivar backups, los usuarios pierden la
restauración local de datos (familias/historias) al cambiar de teléfono. Era
incompatible con no filtrar la sesión en claro.

## 🟠 Otros hallazgos de seguridad

| # | Hallazgo | Sev. | Ubicación |
|---|---|---|---|
| S-4 | Release firmado con el keystore de debug (`signingConfig = debug`) + `applicationId` placeholder `com.example.*` | Medio | `android/app/build.gradle.kts:32-38` |
| S-5 | `profiles.avatar_url` es URL libre escribible por el cliente y se descarga sin allowlist de scheme/host, con redirects activos y sin timeout → SSRF on-device / probing de LAN | Medio | `profile_avatar_image_cache.dart:183-202` ← `profile_service.dart:141` |
| S-6 | El logout no limpia fotos de familiares y stories en disco, la lista remota de familiares en prefs, ni el audio descargado en temp | Medio | grep exhaustivo de `clearOwner` |
| S-7 | `signOut()` con `await` sin `finally`: si falla la llamada al servidor se saltan el sign-out de Google y `clearCache()` | Medio | `auth_service.dart:79-88`, `profile_screen.dart:194-209` |
| S-8 | Flag `familyMemberRemoteDeletionEnabled = true` activo con el esquema sin versionar | Medio | `family_member_deletion_service.dart:5-6` |
| S-9 | Los tokens de invitación son oráculos de existencia (preview devuelve nombres) sin rate-limit visible | Medio → **Bajo** | `invitation_service.dart:39-62` |
| S-17 | SQL reescribe dinámicamente políticas ajenas con `execute format('alter policy ... or ...')` sobre `storage.objects` | Medio | `07_...sql:239-249` |
| S-10 | `onAuthStateChange` suscrito sin `onError` en 5 puntos | Bajo | `main.dart:105`, `home_screen.dart:130`, `profile_screen.dart:65`, `answer_screen.dart:56`, `family_member_screen.dart:120` |
| S-11 | `detectSessionInUri` en default `true` | Bajo | `main.dart:32-35` |
| S-12/13/14/15 | Content-type por nombre de archivo sin sniffing · sin `maxLength` en alta de familiar/pregunta/invitación · `.gitignore` sin `.env*`/keystores · PII real (nombres) en docs del repo público | Bajo | varios |

**Limpio en este eje:** sin WebView, sin `url_launcher`, sin interpolación de
entrada en queries, path traversal imposible estructuralmente, mensajes de error
al usuario genéricos y localizados.

---

# EJE 2 — ARQUITECTURA Y ESCALABILIDAD

## 🔴 A-1 · No hay capa de dominio ni de casos de uso (Crítico)

16/16 pantallas importan servicios directamente; 7/13 widgets también, y uno
importa Supabase. Las transacciones multi-servicio viven dentro de `State`:

```dart
// family_member_screen.dart:501-535 — _delete() orquesta 5 servicios con compensación
final plan = await _deletionService.delete(...);
await _photoService.forgetPhotos(...);   await _storyPhotos.forgetPhotos(...);
await _remoteStoryService?.clearAudioCache();  await _storyStorage.deleteFamily(...);
```

Igual en `question_request_screen.dart:37-95` (upload → RPC → delete
compensatorio → attach) y `home_screen.dart:506-563`. Esta lógica debe ser
consistente entre pantallas y se re-implementa por pantalla.

**Fix:** `lib/domain/` (reglas puras) + casos de uso `DeleteFamilyMember`,
`SubmitAnswer`, `AddFamilyMember` con resultado tipado; las pantallas solo
mapean resultado → UI.

## 🔴 A-2 · Lógica de dominio dentro de widgets (Alto)

`selectHomeHero`, `requestSubtitle`, `requestDate` son funciones de dominio en
`aritoria_home_view.dart:26-76`, consumidas por un screen
(`home_screen.dart:275`). El mismo archivo hace lectura/escritura de caché en
disco y clasifica códigos de error de PostgREST (`:665-666`), duplicado en
`visible_account_avatar_service.dart:177`. Es el único import `supabase_flutter`
fuera de `services/`.

## 🔴 A-3 · Acoplamiento concreto y singletons globales (Alto)

- `Supabase.instance.client` directo en 13 servicios.
- 40+ fallbacks `?? Concrete()` en la UI (p. ej. `account_avatar_view.dart:48`).
- 6 cachés `static final Expando` + 2 singletons `.shared`.
- Configuración hardcodeada: `main.dart:26-28` (URL + publishable key pegadas,
  sin `--dart-define` ni rotación).
- Sin framework de estado: solo `setState` (hasta 28 llamadas por pantalla).

## 🔴 A-4 · Fugas de ciclo de vida en constructores de servicios (Alto)

```dart
// family_member_service.dart:53 — la suscripción no se guarda ni se cancela
_client.auth.onAuthStateChange.listen((state) { ... });
```

Cada `SupabaseFamilyMemberService()` añade un listener permanente y la interfaz
no expone `dispose()`. Mismo patrón en `story_photo_service.dart:108`,
`family_member_photo_service.dart:118`,
`persistent_story_waveform_service.dart:309`. (Solo
`visible_account_avatar_service.dart:25` lo hace bien.)

## 🟠 Otros hallazgos de arquitectura

| # | Hallazgo | Sev. | Evidencia |
|---|---|---|---|
| A-5 | God files: `home_screen.dart` 989 LOC / 35 campos de estado / 13 dependencias inyectadas | Alto | `home_screen.dart:71-105` |
| A-6 | Violaciones OCP: switch de strings en categorías y en acciones de menú; 9 sitios `if (service is! X) throw` + cast redundante; flag `isRemoteFamilyMember` 31 veces en 6 archivos | Alto | ver fichas |
| A-7 | Duplicación estructural: gemelos `story_photo_service` (436) vs `family_member_photo_service` (411) → ~250-280 LOC duplicados; máquina de estado de audio en `story_screen` vs `question_screen` → ~180 LOC; 3 helpers `_showMessage` + ~20 strings idénticos | Crítico/Alto | §D1, D2 |
| A-8 | Tokens de carrera reinventados en 8 archivos (~150 líneas) | Alto | `if (!mounted \|\| request != _loadRequest) return;` ×8 |
| A-9 | Estado triplicado de un mismo familiar; cada vuelta de navegación recarga todo (`_loadStories()` ×7) | Medio | `family_member_screen.dart:77,309-318` |
| A-10 | Question no enlaza hint ni icono · `familyRelationships` es `List<String>` sin tipado · añadir un servicio toca 4+ archivos y ~60 líneas | Medio | `predefined_questions.dart:4-79` |
| A-11 | Sin CI (`.github/` ausente), `flutter_lints` por defecto sin `strict-casts`/`unawaited_futures`, README intacto del template | Medio | `analysis_options.yaml` |
| A-12 | `test/widget_test.dart` = 3.467 líneas / 73 tests con 14 fakes | Bajo | `:2760-2787` |

**Positivos:** cobertura ~94% por líneas, cero ciclos, cero código muerto, cero
TODO, disciplina `mounted` excelente, inyección por constructora existente (el
patrón ya funciona — solo hay que eliminar los fallbacks).

---

# EJE 3 — CONCURRENCIA Y RENDIMIENTO

## 🔴 C-1 · Descargas concurrentes de audio escriben el mismo fichero (Crítico)

```dart
// family_story_service.dart:59-113 — sin dedup en vuelo; _audioCache se llena AL FINAL (L110)
final file = File('${cacheDirectory.path}${...}${story.id}.m4a');
await file.writeAsBytes(bytes, flush: true);   // ← dos llamadas concurrentes, misma ruta
```

Dos llamantes concurrentes pasan ambos la comprobación de caché y escriben el
mismo `.m4a` de forma intercalada → fichero truncado o corrupto. El guard de
`story_screen.dart:64,130-140` solo protege una instancia de pantalla.

**Fix:** mapa de futuros in-flight por `audioPath` (patrón ya usado en
`visible_account_avatar_service.dart:58`) + escritura a fichero temporal único
y `rename()` atómico.

## 🔴 C-2 · Read-modify-write sin serializar en SharedPreferences (Crítico)

```dart
// family_story_storage.dart:161-167 — load → mutate → save, sin mutex
final stories = await _loadAll()..add(story);
await _preferences.setStringList(_storageKey, ...);
```

`saveRecording`, `updatePhoto`, `deleteFamily` y `FamilyMemberStorage.save` se
solapan → updates perdidos a nivel de lista completa (no de clave). Irónico:
`remote_family_member_cache.dart:38-41` ya tiene el `_enqueue` correcto; solo
falta aplicarlo aquí.

## 🔴 C-3 · Cero índices en todo el repo (Alto)

`grep -ri "create index"` → 0 coincidencias. Todo se filtra por columnas FK
(`stories.family_member_id`, `question_requests.recipient_id`+`status`,
`family_members.owner_id`), y cada política RLS re-evalúa esos subqueries por
fila.

**Fix parcial:** `0006_indexes.sql` añade los 6 índices compuestos (C-3). El
casteado en políticas sigue abierto (C-4).

## 🔴 C-4 · Las políticas de storage derrotan el índice PK con casts `::text` (Alto)

```sql
-- 01_family_member_photos.sql:41 (×7 políticas, + 07_...sql:39)
where fm.id::text = (storage.foldername(storage.objects.name))[2]
```

Castea el uuid PK a texto → no puede usar `family_members_pkey`; y
`storage.foldername()` se re-evalúa dos veces por política por fila.

**Fix:** invertir el cast (`[2]::uuid` con guarda de regex previa) y calcular
`foldername` una sola vez.

## 🔴 C-5 · N+1 de RPC por cuenta en avatares (Alto)

```dart
// visible_account_avatar_service.dart:152-157 — el RPC admite ≤100 ids y se le manda 1
params: {'p_account_ids': [accountId]},
```

`aritoria_home_view.dart:318-326` hace `Future.wait(accounts.map(load))` → 50
familiares = 50 RPC donde 1 bastaría.

## 🔴 C-6 · Cero paginación (Alto)

`grep "\.range(\|\.limit(" en lib/` → 0 coincidencias. Consultas sin tope:
todas las stories por familiar, todos los requests pendientes/contestados, todos
los familiares por owner.

## 🟠 Otros hallazgos de concurrencia/rendimiento

| # | Hallazgo | Sev. | Ubicación |
|---|---|---|---|
| C-7 | Cero timeouts de red; HttpClient nuevo por descarga; un request colgado bloquea el avatar (**parcial resuelto en S-5**: `connectionTimeout` 10 s + `requestTimeout` 30 s + `followRedirects = false` en la descarga de avatares; queda compartir el `HttpClient` con el resto de descargas) | Medio | `profile_avatar_image_cache.dart:176-225` |
| C-8 | Doble-tap: `_isSaving` se pone tras el `await` del picker → dos filas creadas | Medio | `home_screen.dart:506-524,821,895` |
| C-9 | Cola de escritura serializada y lecturas que esperan TODO el backlog | Medio | `remote_family_photo_disk_cache.dart:20,89-92,145` |
| C-10 | Bucles `await` secuenciales: chunks de RPC 100 en 100 y un `storage.remove` por objeto | Medio | `received_request_details_service.dart:29-44`, `family_member_deletion_service.dart:70-87` |
| C-11 | Cachés de disco sin techo | Medio | 3 clases de caché |
| C-12 | Caché de bytes con evicción por inserción, no LRU; `_byteCount` no resta la longitud previa | Medio | `profile_avatar_image_cache.dart:216-220` |
| C-13 | Tempestad de reloads: `notifyListeners()` en cada evento de auth | Medio | `account_avatar_view.dart:53-59` |
| C-14 | `ListView(children:)` no lazy en 4 sitios | Medio | `family_member_screen.dart:570-584` |
| C-15 | `TextPainter..layout()` dentro de `build()` | Medio | `aritoria_requests_view.dart:85-100` |
| C-16 | Refresco de un familiar cargando la lista completa y escaneando en lineal | Medio | `family_member_screen.dart:309-318` |
| C-17 | Re-sort en cliente de resultados ya ordenados por SQL | Bajo | `home_screen.dart:402-408,470` |
| C-18 | Caché de waveform compartida estática entre cuentas | Bajo | `persistent_story_waveform_service.dart:339-347` |

**Positivos:** un único `Supabase.instance.client` compartido, `Future.wait`
correcto donde corresponde, dedup de trabajos de waveform por clave, colas
`_enqueue` en el caché remoto de familiares, y todas las disposiciones de
`TextEditingController`/`Timer`/`StreamSubscription`/`TextPainter` en widgets
correctas.

---

# Plan de remediación por fases

## Fase 0 — Parada de emergencia

1. ✅ C-1 dedup in-flight + `rename()` atómico en descargas de audio.
2. ✅ C-2 mutex `_enqueue` en `family_story_storage` y `family_member_storage`.
3. ✅ C-7 timeouts + HttpClient compartido + liberación garantizada de `_pendingBytes` → **parcial** (timeouts y sin redirects en el avatar, con S-5; comparten `HttpClient` pendiente).
4. ✅ S-7 `finally` en el sign-out (Google + cachés se ejecutan siempre).

## Fase 1 — Frontera de seguridad

5. ✅ S-1 versionar esquema base + `pg_policies` → `supabase/migrations/`, y lint de políticas.
6. ✅ S-2 deep links (scheme propio). S-4 release keystore → **vetoado por el propietario**.
7. ✅ **S-3 sesión en Keystore/Keychain + `allowBackup="false"`.**
8. ⏳ C-3 ✅ + C-4 invertir casts `::text` en las 8 políticas de storage.
9. ✅ **S-5 allowlist de host en `avatar_url`** (política en cliente + `CHECK` en `20261112000001`, esta sin aplicar) · ⏳ S-6 barrido completo de cachés en `signedOut`.

## Fase 2 — Escala de datos

10. ⏳ C-5 lote de `get_visible_account_avatars` (≤100 ids) + `warmCached` único en Home.
11. ⏳ C-6 `.range()`/`limit` en las 4 consultas sin tope · C-16 usar `loadMemberForOwner` · C-10 paralelizar bucles · C-17 borrar los re-sort.

## Fase 3 — Arquitectura

12. ⏳ A-1/A-2 casos de uso fuera de pantallas + `selectHomeHero` a `domain/` + mapeo `AppFailure`.
13. ⏳ A-3 `AppGraph` único en `main()`: eliminar los 40 fallbacks `?? Concrete()`, los `.shared`, y mover la config a `String.fromEnvironment`.
14. ⏳ A-4 `dispose()` en los servicios + suscripciones de auth centralizadas en un `SessionMonitor`.
15. ⏳ A-7/A-8 extraer `RemotePhotoStore<T>` y `AudioPlaybackController`; utilidad `AsyncValueLoader<T>`.
16. ⏳ A-5 trocear `home_screen.dart` · A-6/A-10 `Question`/`QuestionCategory`/`FamilyRelationship` tipados.

## Fase 4 — Rendimiento de UI y testabilidad

17. ⏳ C-14/C-15 `ListView.builder` + caché de `TextPainter` · C-11/C-12 presupuestos de caché + LRU real · C-13 debounce de `notifyListeners`.
18. ⏳ CI (`flutter analyze && flutter test` con lints estrictos) + README real + split de `test/widget_test.dart`.
